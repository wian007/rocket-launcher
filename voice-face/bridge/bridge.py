"""Spraakbrug voor de raketlanceerder.

Draait op een pc of Raspberry Pi 5 in hetzelfde wifi-netwerk als het "hoofd"
(ESP32-S3). Per vraag:

  1. ontvangt PCM-audio van de praatknop via WebSocket
  2. spraak -> tekst met faster-whisper (lokaal, Nederlands)
  3. tekst -> antwoord met Claude; Claude kan de lanceerder richten en het
     gezicht van expressie laten wisselen via tools
  4. antwoord -> spraak met Piper (lokaal, Nederlandse stem)
  5. streamt de audio terug naar de ESP32-S3

Claude krijgt bewust GEEN tool om te lanceren: afvuren gaat alleen via de
fysieke armeerschakelaar en de bedieningsapp.

Configuratie via omgevingsvariabelen, zie config.example.env.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import subprocess
import time
import urllib.parse
import urllib.request
from pathlib import Path

import anthropic
import numpy as np
import websockets
from faster_whisper import WhisperModel

log = logging.getLogger("bridge")

HOST = os.environ.get("BRIDGE_HOST", "0.0.0.0")
PORT = int(os.environ.get("BRIDGE_PORT", "8765"))
WHISPER_MODEL = os.environ.get("WHISPER_MODEL", "small")
PIPER_BIN = os.environ.get("PIPER_BIN", "piper")
PIPER_VOICE = os.environ.get("PIPER_VOICE", "voices/nl_NL-mls-medium.onnx")
CLAUDE_MODEL = os.environ.get("CLAUDE_MODEL", "claude-opus-5-5")
CLAUDE_EFFORT = os.environ.get("CLAUDE_EFFORT", "low")
# Basis-URL van de ESP32-CAM-firmware van de lanceerder. Leeg = simulatie.
LAUNCHER_URL = os.environ.get("LAUNCHER_URL", "").rstrip("/")
PAN_RANGE = (0, 180)
TILT_RANGE = (20, 85)
HISTORY_TIMEOUT_S = 300
MAX_HISTORY_MESSAGES = 40

SYSTEM_PROMPT = """\
Je bent Raketje, de vrolijke stem van een zelfgebouwde raketlanceerder met een \
camera, twee servo's (draaien en kantelen) en een klein OLED-gezicht. Je praat \
Nederlands met de maker en zijn gasten.

Je antwoorden worden hardop voorgelezen door een kleine luidspreker:
- Antwoord in één tot drie korte zinnen, als gesproken taal.
- Geen opmaak, lijstjes, emoji of afkortingen die raar klinken als je ze voorleest.

Je kunt de lanceerder richten met de tool richt_lanceerder en je gezicht laten \
veranderen met de tool gezicht. Je kunt NIET lanceren en hebt daar ook geen tool \
voor. Vraagt iemand om te lanceren, leg dan vriendelijk uit dat dat alleen kan \
met de armeerschakelaar en de app, en dat er niemand in de buurt mag staan.\
"""

TOOLS = [
    {
        "name": "richt_lanceerder",
        "description": (
            "Richt de lanceerbuis. pan is de draaihoek in graden "
            f"({PAN_RANGE[0]} = helemaal links, 90 = recht vooruit, {PAN_RANGE[1]} = helemaal rechts). "
            f"tilt is de kantelhoek in graden ({TILT_RANGE[0]} = laag, {TILT_RANGE[1]} = bijna recht omhoog). "
            "Geeft de nieuwe stand terug."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "pan": {"type": "integer", "description": "Draaihoek in graden"},
                "tilt": {"type": "integer", "description": "Kantelhoek in graden"},
            },
            "required": ["pan", "tilt"],
            "additionalProperties": False,
        },
        "strict": True,
    },
    {
        "name": "status_lanceerder",
        "description": "Vraagt de huidige stand en status van de lanceerder op (hoeken, gearmeerd of niet).",
        "input_schema": {"type": "object", "properties": {}, "additionalProperties": False},
    },
    {
        "name": "gezicht",
        "description": "Verandert de gezichtsuitdrukking op het OLED-scherm. Gebruik dit om je antwoord te ondersteunen.",
        "input_schema": {
            "type": "object",
            "properties": {
                "expressie": {
                    "type": "string",
                    "enum": ["neutraal", "blij", "verbaasd", "boos", "verdrietig"],
                }
            },
            "required": ["expressie"],
            "additionalProperties": False,
        },
        "strict": True,
    },
]


# ------------------------------------------------------------------ lanceerder

def _launcher_get(path: str, params: dict | None = None) -> dict:
    """Roept de HTTP-API van de ESP32-CAM aan. Zonder LAUNCHER_URL: simulatie."""
    if not LAUNCHER_URL:
        log.info("SIMULATIE %s %s", path, params)
        return {"gesimuleerd": True, **(params or {})}
    url = f"{LAUNCHER_URL}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=3) as resp:
        body = resp.read().decode() or "{}"
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        return {"antwoord": body}


def run_tool(name: str, args: dict, send_face) -> str:
    try:
        if name == "richt_lanceerder":
            pan = max(PAN_RANGE[0], min(PAN_RANGE[1], int(args["pan"])))
            tilt = max(TILT_RANGE[0], min(TILT_RANGE[1], int(args["tilt"])))
            return json.dumps(_launcher_get("/aim", {"pan": pan, "tilt": tilt}))
        if name == "status_lanceerder":
            return json.dumps(_launcher_get("/status"))
        if name == "gezicht":
            send_face(args["expressie"])
            return "ok"
        return f"Onbekende tool {name}"
    except Exception as exc:  # noqa: BLE001 - fout teruggeven aan Claude
        return f"FOUT: {exc}"


# ------------------------------------------------------------------ spraak

class Speech:
    def __init__(self) -> None:
        log.info("Whisper-model '%s' laden...", WHISPER_MODEL)
        self.stt = WhisperModel(WHISPER_MODEL, device="auto", compute_type="int8")
        cfg = json.loads(Path(PIPER_VOICE + ".json").read_text())
        self.tts_rate = int(cfg["audio"]["sample_rate"])

    def transcribe(self, pcm16: bytes) -> str:
        audio = np.frombuffer(pcm16, dtype=np.int16).astype(np.float32) / 32768.0
        segments, _ = self.stt.transcribe(audio, language="nl", vad_filter=True, beam_size=1)
        return " ".join(s.text.strip() for s in segments).strip()

    def synthesize(self, text: str) -> bytes:
        """Geeft ruwe PCM16 mono op self.tts_rate terug."""
        proc = subprocess.run(
            [PIPER_BIN, "--model", PIPER_VOICE, "--output_raw"],
            input=text.encode(),
            capture_output=True,
            check=True,
        )
        return proc.stdout


# ------------------------------------------------------------------ Claude

class Brain:
    def __init__(self) -> None:
        self.client = anthropic.Anthropic()
        self.history: list[dict] = []
        self.last_turn = 0.0

    def ask(self, text: str, send_face) -> str:
        if time.time() - self.last_turn > HISTORY_TIMEOUT_S or len(self.history) > MAX_HISTORY_MESSAGES:
            self.history = []
        self.last_turn = time.time()
        self.history.append({"role": "user", "content": text})

        for _ in range(6):  # max aantal tool-rondes per vraag
            response = self.client.beta.messages.create(
                model=CLAUDE_MODEL,
                max_tokens=2000,
                system=SYSTEM_PROMPT,
                tools=TOOLS,
                messages=self.history,
                output_config={"effort": CLAUDE_EFFORT},
                betas=["server-side-fallback-2026-07-01"],
                fallbacks="default",
            )
            self.history.append({"role": "assistant", "content": response.content})

            if response.stop_reason == "refusal":
                return "Daar kan ik je helaas niet mee helpen."
            if response.stop_reason != "tool_use":
                return "".join(b.text for b in response.content if b.type == "text").strip()

            results = [
                {
                    "type": "tool_result",
                    "tool_use_id": b.id,
                    "content": run_tool(b.name, b.input, send_face),
                }
                for b in response.content
                if b.type == "tool_use"
            ]
            self.history.append({"role": "user", "content": results})

        return "Oei, ik raakte even in de war. Probeer het nog eens."


# ------------------------------------------------------------------ WebSocket

AUDIO_CHUNK_BYTES = 2048


async def handle(ws, speech: Speech, brain: Brain) -> None:
    log.info("Hoofd verbonden: %s", ws.remote_address)
    loop = asyncio.get_running_loop()
    recording: bytearray | None = None

    async def send(obj: dict) -> None:
        await ws.send(json.dumps(obj))

    def send_face(expr: str) -> None:  # aangeroepen vanuit de Claude-thread
        asyncio.run_coroutine_threadsafe(send({"type": "face", "expr": expr}), loop)

    async for msg in ws:
        if isinstance(msg, bytes):
            if recording is not None:
                recording.extend(msg)
            continue

        data = json.loads(msg)
        if data.get("type") == "start":
            recording = bytearray()
        elif data.get("type") == "end" and recording is not None:
            pcm, recording = bytes(recording), None
            try:
                await send({"type": "state", "state": "thinking"})
                text = await asyncio.to_thread(speech.transcribe, pcm)
                log.info("Gehoord: %r", text)
                if not text:
                    send_face("verbaasd")
                    text_reply = "Sorry, dat verstond ik niet."
                else:
                    text_reply = await asyncio.to_thread(brain.ask, text, send_face)
                log.info("Antwoord: %r", text_reply)

                audio = await asyncio.to_thread(speech.synthesize, text_reply)
                await send({"type": "audio_start", "rate": speech.tts_rate})
                for i in range(0, len(audio), AUDIO_CHUNK_BYTES):
                    await ws.send(audio[i : i + AUDIO_CHUNK_BYTES])
                await send({"type": "audio_end"})
            except Exception:
                log.exception("Fout bij verwerken van vraag")
                await send({"type": "face", "expr": "verdrietig"})
            finally:
                await send({"type": "state", "state": "idle"})


async def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    speech = Speech()
    brain = Brain()
    async with websockets.serve(lambda ws: handle(ws, speech, brain), HOST, PORT, max_size=None):
        log.info("Bridge luistert op ws://%s:%d/", HOST, PORT)
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
