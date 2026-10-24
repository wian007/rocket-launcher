#include "face.h"

#include <U8g2lib.h>
#include <Wire.h>

// Kies je scherm: 0,96" is meestal SSD1306, 1,3" is meestal SH1106.
#ifdef OLED_SH1106
static U8G2_SH1106_128X64_NONAME_F_HW_I2C u8g2(U8G2_R0, U8X8_PIN_NONE);
#else
static U8G2_SSD1306_128X64_NONAME_F_HW_I2C u8g2(U8G2_R0, U8X8_PIN_NONE);
#endif

namespace {
volatile FaceState gState = FaceState::Offline;
volatile Expression gExpr = Expression::Neutral;
volatile uint8_t gMouth = 0;

constexpr int kEyeW = 28, kEyeH = 30, kEyeR = 7;
constexpr int kLeftX = 36, kRightX = 92, kEyeY = 26;  // middelpunten

// Animatietoestand (alleen gebruikt door de facetaak)
uint32_t nextBlink = 0, blinkStart = 0, nextGlance = 0;
float lookX = 0, lookY = 0, lookTargetX = 0, lookTargetY = 0;
float mouthSmooth = 0;

void drawEye(int cx, int cy, int w, int h, bool left, Expression e) {
  if (h < 2) {
    u8g2.drawBox(cx - w / 2, cy - 1, w, 2);
    return;
  }
  int r = min(kEyeR, h / 2 - 1);
  u8g2.drawRBox(cx - w / 2, cy - h / 2, w, h, r);

  // Expressies door delen van het oog weg te "knippen" met zwart
  u8g2.setDrawColor(0);
  int top = cy - h / 2, bottom = cy + h / 2;
  switch (e) {
    case Expression::Happy:  // lachende ogen: onderkant als boog weg
      u8g2.drawFilledEllipse(cx, bottom + 4, w / 2 + 4, h / 2);
      break;
    case Expression::Angry: {  // schuine wenkbrauw naar binnen
      int inner = left ? cx + w / 2 : cx - w / 2;
      int outer = left ? cx - w / 2 : cx + w / 2;
      u8g2.drawTriangle(outer, top - 1, inner + (left ? 1 : -1), top - 1, inner, top + h / 2);
      break;
    }
    case Expression::Sad: {  // schuine wenkbrauw naar buiten
      int inner = left ? cx + w / 2 : cx - w / 2;
      int outer = left ? cx - w / 2 : cx + w / 2;
      u8g2.drawTriangle(inner, top - 1, outer + (left ? -1 : 1), top - 1, outer, top + h / 2);
      break;
    }
    default:
      break;
  }
  u8g2.setDrawColor(1);
}

void drawMouth(FaceState s, Expression e, uint32_t now) {
  const int cx = 64, cy = 56;
  if (s == FaceState::Speaking) {
    int h = 2 + (int)(mouthSmooth * 12.0f / 255.0f);
    int w = 18 + h;
    u8g2.drawRBox(cx - w / 2, cy - h / 2, w, max(h, 2), min(3, h / 2));
    return;
  }
  if (e == Expression::Surprised || s == FaceState::Listening) {
    u8g2.drawCircle(cx, cy, 4);
    return;
  }
  if (e == Expression::Sad) {
    for (int dx = -10; dx <= 10; dx++) u8g2.drawPixel(cx + dx, cy + 3 - (100 - dx * dx) / 30);
    return;
  }
  if (e == Expression::Happy) {
    for (int dx = -12; dx <= 12; dx++) {
      int y = cy - 3 + (144 - dx * dx) / 30;
      u8g2.drawPixel(cx + dx, y);
      u8g2.drawPixel(cx + dx, y + 1);
    }
    return;
  }
  u8g2.drawHLine(cx - 8, cy, 16);
}

void drawThinkingDots(uint32_t now) {
  int n = (now / 300) % 4;
  for (int i = 0; i < n; i++) u8g2.drawDisc(104 + i * 7, 6, 2);
}

void render() {
  uint32_t now = millis();
  FaceState s = gState;
  Expression e = gExpr;

  // Knipperen: elke 2-6 s, 150 ms dicht
  if (now >= nextBlink) {
    blinkStart = now;
    nextBlink = now + random(2000, 6000);
  }
  float blink = 1.0f;
  uint32_t bt = now - blinkStart;
  if (bt < 150) blink = fabsf((float)bt - 75.0f) / 75.0f;

  // Rondkijken als hij niets te doen heeft
  if (s == FaceState::Idle && now >= nextGlance) {
    lookTargetX = random(-8, 9);
    lookTargetY = random(-3, 4);
    nextGlance = now + random(1200, 4000);
  } else if (s == FaceState::Thinking) {
    lookTargetX = 6;
    lookTargetY = -6;
  } else if (s != FaceState::Idle) {
    lookTargetX = 0;
    lookTargetY = 0;
  }
  lookX += (lookTargetX - lookX) * 0.25f;
  lookY += (lookTargetY - lookY) * 0.25f;
  mouthSmooth += ((float)gMouth - mouthSmooth) * 0.5f;

  int w = kEyeW, h = kEyeH;
  if (s == FaceState::Listening || e == Expression::Surprised) {
    w += 4;
    h += 4;
  }
  if (s == FaceState::Offline) h = 4;  // "slaapt"
  h = (int)(h * blink);

  u8g2.clearBuffer();
  drawEye(kLeftX + (int)lookX, kEyeY + (int)lookY, w, h, true, e);
  drawEye(kRightX + (int)lookX, kEyeY + (int)lookY, w, h, false, e);
  drawMouth(s, e, now);
  if (s == FaceState::Thinking) drawThinkingDots(now);
  if (s == FaceState::Offline) {
    u8g2.setFont(u8g2_font_5x7_tr);
    u8g2.drawStr(100, 8, "zZz");
  }
  u8g2.sendBuffer();
}

void faceTask(void *) {
  for (;;) {
    render();
    vTaskDelay(pdMS_TO_TICKS(33));  // ~30 fps
  }
}
}  // namespace

namespace face {
void begin(int sda, int scl) {
  Wire.begin(sda, scl);
  Wire.setClock(400000);
  u8g2.begin();
  // Core 0; de hoofdlus (WiFi-audio) draait op core 1
  xTaskCreatePinnedToCore(faceTask, "face", 4096, nullptr, 1, nullptr, 0);
}

void setState(FaceState s) {
  gState = s;
  if (s != FaceState::Speaking) gMouth = 0;
}

FaceState state() { return gState; }

void setExpression(Expression e) { gExpr = e; }

void setMouthLevel(uint8_t level) { gMouth = level; }

Expression expressionFromName(const char *name) {
  if (!name) return Expression::Neutral;
  if (!strcmp(name, "blij")) return Expression::Happy;
  if (!strcmp(name, "verbaasd")) return Expression::Surprised;
  if (!strcmp(name, "boos")) return Expression::Angry;
  if (!strcmp(name, "verdrietig")) return Expression::Sad;
  return Expression::Neutral;
}
}  // namespace face
