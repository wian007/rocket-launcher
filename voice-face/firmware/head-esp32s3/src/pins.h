// Pinindeling ESP32-S3-DevKitC-1. Vermijd GPIO 19/20 (USB), 26-32 (flash)
// en 35-37 (octal PSRAM op N16R8/N8R8).
#pragma once

// INMP441 microfoon (I2S0, ontvangen). L/R-pin van de mic aan GND = linkerkanaal.
#define PIN_MIC_SCK   5
#define PIN_MIC_WS    6
#define PIN_MIC_SD    4

// MAX98357A versterker (I2S1, zenden). SD-pin los laten = mono (L+R)/2.
#define PIN_AMP_BCLK  15
#define PIN_AMP_LRC   16
#define PIN_AMP_DIN   7

// SSD1306 / SH1106 OLED (I2C)
#define PIN_OLED_SDA  8
#define PIN_OLED_SCL  9

// Praatknop naar GND (interne pull-up)
#define PIN_TALK_BTN  10
