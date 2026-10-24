// Geanimeerd gezicht op een 128x64 OLED. Draait in een eigen FreeRTOS-taak
// zodat het blijft bewegen terwijl de hoofdlus audio verwerkt.
#pragma once
#include <Arduino.h>

enum class FaceState : uint8_t {
  Idle,       // rustig, knippert af en toe en kijkt rond
  Listening,  // grote ogen, luistert naar de praatknop-opname
  Thinking,   // kijkt omhoog, puntjes lopen
  Speaking,   // mond beweegt mee met het geluid
  Offline,    // geen verbinding met de bridge
};

enum class Expression : uint8_t { Neutral, Happy, Surprised, Angry, Sad };

namespace face {
void begin(int sda, int scl);
void setState(FaceState s);
FaceState state();
void setExpression(Expression e);
// 0..255, wordt tijdens het spreken bijgewerkt vanuit het audiovolume
void setMouthLevel(uint8_t level);
Expression expressionFromName(const char *name);
}  // namespace face
