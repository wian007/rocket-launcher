// "Hoofd" van de raketlanceerder: praatknop + microfoon + luidspreker + OLED-gezicht.
//
// Deze ESP32-S3 doet zelf geen spraakherkenning. Hij stuurt de opname via een
// WebSocket naar bridge.py (pc of Raspberry Pi), die verstaat, nadenkt (Claude),
// de lanceerder richt en het antwoord als audio terugstuurt.
//
// Protocol (ws://BRIDGE_HOST:BRIDGE_PORT/):
//   S3 -> bridge  tekst  {"type":"start","rate":16000}   knop ingedrukt
//                 binair PCM16 mono 16 kHz                tijdens het praten
//                 tekst  {"type":"end"}                   knop losgelaten
//   bridge -> S3  tekst  {"type":"state","state":"idle|thinking"}
//                 tekst  {"type":"face","expr":"blij|verbaasd|boos|verdrietig|neutraal"}
//                 tekst  {"type":"audio_start","rate":22050}
//                 binair PCM16 mono                       af te spelen
//                 tekst  {"type":"audio_end"}

#include <Arduino.h>
#include <ArduinoJson.h>
#include <WebSocketsClient.h>
#include <WiFi.h>
#include <driver/i2s.h>

#include "face.h"
#include "pins.h"
#include "secrets.h"

static constexpr i2s_port_t kMicPort = I2S_NUM_0;
static constexpr i2s_port_t kAmpPort = I2S_NUM_1;
static constexpr uint32_t kMicRate = 16000;
static constexpr size_t kMicChunk = 512;           // samples per WebSocket-pakket (32 ms)
static constexpr uint32_t kMaxRecordMs = 15000;    // veiligheidslimiet per vraag

static WebSocketsClient ws;
static bool recording = false;
static uint32_t recordStart = 0;
static int32_t micRaw[kMicChunk];
static int16_t micPcm[kMicChunk];

// ---------------------------------------------------------------- I2S

static void setupMic() {
  i2s_config_t cfg = {};
  cfg.mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX);
  cfg.sample_rate = kMicRate;
  cfg.bits_per_sample = I2S_BITS_PER_SAMPLE_32BIT;  // INMP441 levert 24 bit in 32-bit slot
  cfg.channel_format = I2S_CHANNEL_FMT_ONLY_LEFT;
  cfg.communication_format = I2S_COMM_FORMAT_STAND_I2S;
  cfg.intr_alloc_flags = ESP_INTR_FLAG_LEVEL1;
  cfg.dma_buf_count = 8;
  cfg.dma_buf_len = 256;
  i2s_driver_install(kMicPort, &cfg, 0, nullptr);

  i2s_pin_config_t pins = {};
  pins.mck_io_num = I2S_PIN_NO_CHANGE;
  pins.bck_io_num = PIN_MIC_SCK;
  pins.ws_io_num = PIN_MIC_WS;
  pins.data_out_num = I2S_PIN_NO_CHANGE;
  pins.data_in_num = PIN_MIC_SD;
  i2s_set_pin(kMicPort, &pins);
}

static void setupAmp() {
  i2s_config_t cfg = {};
  cfg.mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_TX);
  cfg.sample_rate = 22050;
  cfg.bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT;
  cfg.channel_format = I2S_CHANNEL_FMT_ONLY_LEFT;
  cfg.communication_format = I2S_COMM_FORMAT_STAND_I2S;
  cfg.intr_alloc_flags = ESP_INTR_FLAG_LEVEL1;
  cfg.dma_buf_count = 8;
  cfg.dma_buf_len = 512;
  cfg.tx_desc_auto_clear = true;  // stilte i.p.v. herhaling bij een haperende stream
  i2s_driver_install(kAmpPort, &cfg, 0, nullptr);

  i2s_pin_config_t pins = {};
  pins.mck_io_num = I2S_PIN_NO_CHANGE;
  pins.bck_io_num = PIN_AMP_BCLK;
  pins.ws_io_num = PIN_AMP_LRC;
  pins.data_out_num = PIN_AMP_DIN;
  pins.data_in_num = I2S_PIN_NO_CHANGE;
  i2s_set_pin(kAmpPort, &pins);
}

// ---------------------------------------------------------------- afspelen

static void playChunk(const uint8_t *data, size_t len) {
  const int16_t *s = (const int16_t *)data;
  size_t n = len / 2;
  uint32_t peak = 0;
  for (size_t i = 0; i < n; i++) peak = max(peak, (uint32_t)abs(s[i]));
  face::setMouthLevel(min<uint32_t>(255, peak >> 6));

  size_t written;
  i2s_write(kAmpPort, data, len, &written, portMAX_DELAY);
}

static void handleText(const char *txt, size_t len) {
  JsonDocument doc;
  if (deserializeJson(doc, txt, len)) return;
  const char *type = doc["type"] | "";

  if (!strcmp(type, "state")) {
    const char *st = doc["state"] | "idle";
    face::setState(!strcmp(st, "thinking") ? FaceState::Thinking : FaceState::Idle);
  } else if (!strcmp(type, "face")) {
    face::setExpression(face::expressionFromName(doc["expr"] | "neutraal"));
  } else if (!strcmp(type, "audio_start")) {
    i2s_set_clk(kAmpPort, doc["rate"] | 22050, I2S_BITS_PER_SAMPLE_16BIT, I2S_CHANNEL_MONO);
    i2s_zero_dma_buffer(kAmpPort);
    face::setState(FaceState::Speaking);
  } else if (!strcmp(type, "audio_end")) {
    face::setMouthLevel(0);
    face::setState(FaceState::Idle);
  }
}

static void onWsEvent(WStype_t type, uint8_t *payload, size_t len) {
  switch (type) {
    case WStype_CONNECTED:
      Serial.println("Bridge verbonden");
      face::setState(FaceState::Idle);
      break;
    case WStype_DISCONNECTED:
      recording = false;
      face::setState(FaceState::Offline);
      break;
    case WStype_TEXT:
      handleText((const char *)payload, len);
      break;
    case WStype_BIN:
      if (face::state() == FaceState::Speaking) playChunk(payload, len);
      break;
    default:
      break;
  }
}

// ---------------------------------------------------------------- opnemen

static void startRecording() {
  i2s_zero_dma_buffer(kAmpPort);
  i2s_zero_dma_buffer(kMicPort);
  ws.sendTXT("{\"type\":\"start\",\"rate\":16000}");
  face::setExpression(Expression::Neutral);
  face::setState(FaceState::Listening);
  recording = true;
  recordStart = millis();
}

static void stopRecording() {
  recording = false;
  ws.sendTXT("{\"type\":\"end\"}");
  face::setState(FaceState::Thinking);
}

static void pumpMic() {
  size_t got = 0;
  i2s_read(kMicPort, micRaw, sizeof(micRaw), &got, pdMS_TO_TICKS(50));
  size_t n = got / sizeof(int32_t);
  for (size_t i = 0; i < n; i++) {
    // 24-bit waarde staat links uitgelijnd; >>14 geeft een bruikbaar 16-bit niveau
    int32_t v = micRaw[i] >> 14;
    micPcm[i] = (int16_t)constrain(v, -32768, 32767);
  }
  if (n) ws.sendBIN((uint8_t *)micPcm, n * sizeof(int16_t));
}

// ---------------------------------------------------------------- setup/loop

void setup() {
  Serial.begin(115200);
  pinMode(PIN_TALK_BTN, INPUT_PULLUP);
  face::begin(PIN_OLED_SDA, PIN_OLED_SCL);
  setupMic();
  setupAmp();

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);  // minder vertraging in de audiostream
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) delay(200);
  Serial.printf("WiFi ok: %s\n", WiFi.localIP().toString().c_str());

  ws.begin(BRIDGE_HOST, BRIDGE_PORT, "/");
  ws.onEvent(onWsEvent);
  ws.setReconnectInterval(2000);
  ws.enableHeartbeat(15000, 3000, 2);
}

void loop() {
  ws.loop();

  bool pressed = digitalRead(PIN_TALK_BTN) == LOW;
  bool canTalk = ws.isConnected() && face::state() == FaceState::Idle;

  if (!recording && pressed && canTalk) {
    delay(20);  // ontdenderen
    if (digitalRead(PIN_TALK_BTN) == LOW) startRecording();
  } else if (recording && (!pressed || millis() - recordStart > kMaxRecordMs)) {
    stopRecording();
  }

  if (recording) pumpMic();
}
