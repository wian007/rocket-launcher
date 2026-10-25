# Nerf-pijltjes afvuren

Voorstel voor het afvuurmechanisme op de pan/tilt-houder, met zo weinig mogelijk
3D-prints en zoveel mogelijk kant-en-klare onderdelen.

## Keuze: flywheel (twee draaiende wieltjes)

| | Flywheel | Veer (plunjer) | Perslucht |
|---|---|---|---|
| Hoe | 2 motortjes met wieltjes knijpen het pijltje weg, een servo duwt het pijltje erin | Veer spannen, pal loslaten | Tank + magneetklep blaast het pijltje weg |
| Kant-en-klaar te koop | Ja, complete "Stryfe flywheel cage" met motoren | Alleen als heel blaster-binnenwerk | Klep, tank en pomp los kopen |
| Aansturen vanuit ESP32 | 1 MOSFET + 1 servo | Servo moet de veer spannen: MG995/SG90 is te zwak, veel printwerk | MOSFET + 12 V klep, plus oppompen |
| Snel na elkaar schieten | Ja, zolang er pijltjes in het magazijn zitten | 1 schot per spanbeweging (traag) | Afhankelijk van de tank |
| Gewicht op de tilt-arm | ±150-250 g | Zwaar en groot | Tank is zwaar |

**Advies: flywheel.** Het is volledig elektrisch, er zijn kooien met motoren los
te koop (of uit een goedkope tweedehands Nerf Stryfe te halen), en het past bij
een ESP32 met één MOSFET en de SG90 die je al hebt.

## Onderdelenlijst

| # | Onderdeel | Opmerking |
|---|---|---|
| 1 | Flywheelkooi voor Nerf Stryfe, **met** 2 motoren (130- of 180-formaat) | Bijv. Worker of vergelijkbaar op AliExpress, of uit een tweedehands Stryfe (Marktplaats). Een kooi met magazijnschacht is het handigst |
| 1 | Nerf Elite-magazijn (6 of 12 pijltjes) | Past in de Stryfe-schacht |
| 1 | Nerf Elite-pijltjes (Ø12,7 mm, 72 mm lang) | |
| 1 | SG90-servo (heb je al) | Duwstang: duwt het bovenste pijltje van het magazijn tussen de wieltjes |
| 1 | MOSFET-schakelmodule D4184 of AOD4184 (logic level, werkt op 3,3 V) | Of los: IRLZ44N + 100 Ω gate-weerstand + 10 kΩ pull-down |
| 2 | Schottky-diode 1N5819 of SS34 | Over elke motor (vrijloopdiode) |
| 2 | Condensator 100 nF keramisch | Over de motorpolen, scheelt storing op camera en wifi |
| 1 | 2S LiPo 7,4 V (bijv. 1000-1500 mAh) met XT30/XT60 | Voor motoren en, via de BEC, voor de servo's |
| 1 | 5 V BEC/step-down, min. 3 A | Voor MG995's, SG90 en ESP32-CAM |
| 1 | Zekering 10 A (in-line) | Direct na de accu |
| 1 | **Armeerschakelaar**: tuimelschakelaar 2-polig (DPDT), bij voorkeur met klepje of sleutel | Zie veiligheid |
| 1 | Elco 1000 µF / 10 V | Op de 5 V servolijn |

Printwerk blijft beperkt tot een vlak montageplaatje voor de kooi op de wieg
en een klein steuntje voor de SG90 (kan ook met tiewraps of dubbelzijdig tape).

## Bedrading (ESP32-CAM, AI-Thinker, zonder SD-kaart)

```
2S LiPo + ── zekering 10A ──┬── armeerschakelaar pool A ── MOSFET-module VIN+ ── motoren (+)
                            │                               MOSFET-module OUT- ── motoren (-)
                            └── BEC 5V ──┬── MG995 pan, MG995 tilt, SG90 duwer (+)
                                         └── ESP32-CAM 5V
LiPo - ── GND gemeenschappelijk (BEC, MOSFET-module, ESP32-CAM, servo's)

ESP32-CAM GPIO14 ── pan-servo signaal
ESP32-CAM GPIO15 ── tilt-servo signaal
ESP32-CAM GPIO13 ── SG90 duwer signaal
ESP32-CAM GPIO12 ── MOSFET-module TRIG/PWM (+ 10 kΩ naar GND)
ESP32-CAM GPIO2  ── armeerschakelaar pool B ── GND  (interne pull-up, laag = gewapend)
```

- **GPIO12** moet laag zijn bij het opstarten (anders kiest de ESP32 de verkeerde
  flashspanning). De 10 kΩ pull-down zorgt daarvoor en houdt de motoren ook uit
  tijdens het opstarten.
- Elke motor krijgt een Schottky-diode (streepje naar +) en een 100 nF condensator
  over de polen. Zonder deze kan de ESP32-CAM resetten of de wifi wegvallen.
- De pan/tilt-pinnen zijn een voorstel; de CAM-firmware bestaat nog niet. Pas
  ze aan als die andere pinnen gebruikt.

## Hoe het op de pan/tilt-houder past

- De kooi vervangt de Ø25 mm-buis. De wieg krijgt een variant met een vlakke
  plaat (M3-gaten op het patroon van de kooi) in plaats van de buisklem.
- Typische maten van een Stryfe-kooi: ±60 × 50 × 45 mm (L × B × H) zonder
  magazijn; meet je eigen kooi na. Het magazijn steekt er ±80-150 mm onder uit,
  dus leg de tilt-as hoog genoeg of laat het magazijn schuin naar achteren
  wijzen.
- Zwaartepunt zo dicht mogelijk bij de tilt-as, anders moet de MG995 constant
  tegen het gewicht in houden.
- De ESP32-CAM komt bovenop de kooi, lens evenwijdig aan de schietrichting.
- Kantelbereik met magazijn eronder wordt kleiner; begrens het in de firmware.

## Afvuren in de firmware (voorstel)

1. Alleen als GPIO2 laag is (schakelaar gewapend) **en** de vuurknop in de app
   ingedrukt wordt gehouden.
2. Motoren aan (GPIO12 hoog), 300 ms wachten tot ze op toeren zijn.
3. SG90 naar voren (±150 ms) en terug (±150 ms) per pijltje.
4. Motoren uit na 2 s zonder schot, bij loslaten van de knop, bij wegvallen van
   de verbinding of als de schakelaar uit gaat.

## Veiligheid

- **Claude en de spraakbesturing kunnen nooit afvuren.** De spraakbrug heeft
  alleen `/aim` en `/status`; er komt geen vuur-endpoint in de brug.
- De armeerschakelaar onderbreekt **fysiek** de stroom naar de motoren (pool A).
  Staat hij uit, dan kan geen enkele software een pijltje wegschieten, hooguit
  duwt de SG90 het tegen stilstaande wieltjes.
- Niet op gezichten of dieren richten; draag een bril bij het testen.
