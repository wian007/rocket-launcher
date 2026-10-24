# Spraak en OLED-gezicht

Je drukt op een praatknop, zegt iets in het Nederlands ("draai eens naar links en kijk omhoog"), het gezicht op het OLED-schermpje gaat nadenken, de lanceerder draait mee en je hoort een gesproken antwoord terug.

## Waarom een tweede ESP32

De ESP32-CAM heeft bijna geen vrije pinnen over. Camera, SD-kaart en de twee servo's gebruiken ze al, en I2S-audio heeft ook nog eens 3 pinnen per richting nodig. Daarom komt er een apart "hoofd" bij: een **ESP32-S3**. Die doet de microfoon, de luidspreker, het scherm en de praatknop. De ESP32-CAM blijft gewoon camera en servo's doen.

Echte Nederlandse spraakherkenning en een slim gesprek passen niet op een microcontroller (Espressif's eigen ESP-SR kent geen Nederlands). Het zware werk gebeurt daarom op een pc of Raspberry Pi 5 in hetzelfde wifi-netwerk.

```
 [praatknop] [INMP441-mic]   [OLED-gezicht]   [MAX98357A + luidspreker]
        \          |              |                 /
         +-------- ESP32-S3 "hoofd" ---------------+
                          |  WebSocket (wifi)
                          v
              bridge.py op pc / Raspberry Pi 5
     Whisper (spraak→tekst, lokaal)  →  Claude (gesprek + tools)  →  Piper (tekst→spraak, lokaal)
                          |  HTTP (wifi)
                          v
              ESP32-CAM: camera + pan/tilt-servo's
```

Alleen de tekst van je vraag gaat naar de cloud (naar Claude). Spraakherkenning en de stem draaien lokaal.

**Veiligheid:** Claude kan richten en het gezicht veranderen, maar heeft bewust **geen** tool om te lanceren. Afvuren gaat alleen via de fysieke armeerschakelaar en de app.

## Onderdelen

| Onderdeel | Type | Ca. prijs |
|---|---|---|
| Microcontroller | ESP32-S3-DevKitC-1 **N16R8** (16 MB flash, 8 MB PSRAM) | € 8-12 |
| Microfoon | INMP441 I2S MEMS-module | € 2-4 |
| Versterker | MAX98357A I2S class-D, 3 W | € 2-5 |
| Luidspreker | 40 mm rond, 4 Ω, 3 W | € 2-4 |
| Scherm | 0,96" SSD1306 128x64 I2C (of 1,3" SH1106) | € 3-6 |
| Praatknop | 12 mm drukknop, maakcontact | € 1 |

## Bedrading

| Module | Pin module | ESP32-S3 GPIO |
|---|---|---|
| INMP441 | VDD | 3V3 |
| | GND | GND |
| | L/R | GND (linkerkanaal) |
| | SCK | 5 |
| | WS | 6 |
| | SD | 4 |
| MAX98357A | VIN | 5V |
| | GND | GND |
| | BCLK | 15 |
| | LRC | 16 |
| | DIN | 7 |
| | GAIN | los = 9 dB (aan GND = 12 dB, harder) |
| | SD | los (mono) |
| OLED | VCC | 3V3 |
| | GND | GND |
| | SDA | 8 |
| | SCL | 9 |
| Praatknop | ene kant | 10 |
| | andere kant | GND |

De pinnen staan ook in [`firmware/head-esp32s3/src/pins.h`](firmware/head-esp32s3/src/pins.h). GPIO 19/20 (USB), 26-32 (flash) en 35-37 (PSRAM) zijn bewust vermeden.

**Voeding:** servo's (vooral de MG995) trekken pieken van 1-2 A en geven storing op de audio. Gebruik een 5V-voeding van minstens 3 A, zet een elco van 1000 µF bij de servo's, en verbind alle GND's met elkaar. Hoor je gezoem of tikken in de luidspreker, geef de servo's dan een eigen 5V-regelaar.

## Afmetingen voor de behuizing

Typische maten van de gangbare modules. Ze verschillen per leverancier, dus meet je eigen exemplaar na met een schuifmaat voordat je print.

| Onderdeel | Maat |
|---|---|
| ESP32-S3-DevKitC-1 | 63 × 25,5 mm printplaat, ca. 15 mm hoog met pinheaders; USB-C-poorten aan de korte kant moeten bereikbaar blijven |
| SSD1306 0,96" | printplaat 27 × 27 mm; glas 26,7 × 19,3 mm; zichtbaar beeld 21,7 × 10,9 mm; 4 gaten Ø 2 mm op ca. 23 × 23 mm; pinheader aan de bovenrand |
| SH1106 1,3" | printplaat 35,5 × 33,5 mm; zichtbaar beeld 29,4 × 14,7 mm; gaten Ø 3 mm op ca. 30,5 × 28 mm |
| INMP441 | ronde printplaat Ø 14 mm (sommige 15 × 13 mm); geluidsgaatje in de printplaat moet achter een opening van 2-3 mm in de behuizing zitten, met een rubbertje of foam ertussen tegen trillingen |
| MAX98357A | 18 × 18 mm (Adafruit 17,8 × 19,3 mm), ca. 3 mm dik plus headers |
| Luidspreker 40 mm | Ø 40 mm, 15-20 mm diep; een gesloten kamertje erachter klinkt voller, voorkant een rooster van gaatjes Ø 2 mm |
| Drukknop 12 mm | gat Ø 12 mm, wanddikte max ca. 5 mm |

Houd de microfoon zo ver mogelijk van de luidspreker en de servo's.

## Firmware van het hoofd (ESP32-S3)

PlatformIO-project in [`firmware/head-esp32s3`](firmware/head-esp32s3).

1. Kopieer `src/secrets.example.h` naar `src/secrets.h` en vul je wifi en het IP-adres van de pc/Pi met de bridge in.
2. Gebruik je een 1,3" SH1106-scherm, voeg dan `-DOLED_SH1106` toe aan `build_flags` in `platformio.ini`.
3. `pio run -t upload -t monitor`

Het gezicht slaapt ("zZz") tot de bridge verbonden is. Daarna knippert het en kijkt het rond, krijgt het grote ogen terwijl je de knop vasthoudt, kijkt het omhoog met puntjes terwijl het nadenkt, en beweegt de mond mee met het geluid. Claude kan ook de uitdrukking kiezen: blij, verbaasd, boos of verdrietig.

## Bridge (pc of Raspberry Pi 5)

```bash
cd bridge
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt

# Nederlandse stem downloaden (andere opties: nl_NL-ronnie-medium, nl_BE-nathalie-medium)
mkdir -p voices && python -m piper.download_voices --data-dir voices nl_NL-mls-medium

cp config.example.env .env      # vul je ANTHROPIC_API_KEY in
set -a; . ./.env; set +a
python bridge.py
```

Op een Raspberry Pi is `WHISPER_MODEL=base` sneller; op een pc geeft `small` duidelijk beter Nederlands.

De bridge gebruikt de [Claude API](https://platform.claude.com) en vangt een geweigerd verzoek op met de automatische fallback (`fallbacks="default"`). Zet `CLAUDE_EFFORT` op `low` voor een vlot gesprek.

### Koppeling met de lanceerder

De bridge stuurt de ESP32-CAM aan met:

- `GET {LAUNCHER_URL}/aim?pan=<0-180>&tilt=<20-85>`
- `GET {LAUNCHER_URL}/status` (JSON terug)

Zolang `LAUNCHER_URL` leeg is, wordt het richten alleen gelogd. Pas deze twee paden aan als de CAM-firmware andere endpoints krijgt.

## Protocol hoofd ↔ bridge

WebSocket op `ws://BRIDGE_HOST:8765/`.

| Richting | Bericht |
|---|---|
| hoofd → bridge | `{"type":"start","rate":16000}`, dan binaire PCM16 mono 16 kHz, dan `{"type":"end"}` |
| bridge → hoofd | `{"type":"state","state":"thinking"\|"idle"}` |
| | `{"type":"face","expr":"blij"\|"verbaasd"\|"boos"\|"verdrietig"\|"neutraal"}` |
| | `{"type":"audio_start","rate":22050}`, binaire PCM16 mono, `{"type":"audio_end"}` |
