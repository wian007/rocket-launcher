// Pan/tilt-lanceerhouder voor een raketlanceerbuis met ESP32-CAM
// Parametrisch OpenSCAD-ontwerp. Kies een onderdeel met `part` en exporteer als STL:
//   openscad -D 'part="base"' -o base.stl launcher.scad
// Onderdelen: "base", "pan", "cradle", "camholder", "head", "head_lid",
// "assembly" (alleen bekijken).

part = "assembly";

// ---------------------------------------------------------------- instellingen
pan_servo  = "MG995";   // "MG995" (= MG996R maat) of "SG90"
tilt_servo = "MG995";

tube_d        = 25;     // buitendiameter lanceerbuis (mm)
tube_len      = 160;    // alleen voor de weergave in "assembly"
tube_back     = 8;      // hoeveel de buis achter de wieg uitsteekt (weergave)
cradle_len    = 60;     // lengte van de wieg langs de buis
tilt_z        = 50;     // hoogte tilt-as boven het pan-plateau
elevation     = 35;     // alleen weergave: hoek van de buis in "assembly"
pan_angle     = 20;     // alleen weergave

clr     = 0.3;          // printspeling
wall    = 3;
$fn     = 72;

// ESP32-CAM (AI-Thinker)
cam_w     = 27;
cam_l     = 40.5;
cam_pcb_t = 1.6;

// ---------------------------------------------------------------- servo-maten
// [body_l, body_w, body_h, tab_z, tab_t, tab_l, shaft_off, hole_sp, hole_d,
//  horn_gap, horn_d, horn_t, horn_hole_r]
//  body_h   : hoogte behuizing (zonder as)
//  tab_z    : onderkant montage-oren gemeten vanaf de bodem
//  shaft_off: afstand hart as tot dichtstbijzijnde kopse kant
//  horn_gap : afstand bovenkant behuizing tot het vlak waar de ronde horn op ligt
function servo_dims(s) =
    s == "SG90"
      ? [22.8, 12.2, 22.7, 15.9, 2.5, 32.3, 6.0, 27.5, 2.0, 4.5, 20.5, 1.8, 6.0]
      : [40.7, 19.7, 37.0, 26.7, 2.6, 54.0, 10.0, 49.5, 2.8, 6.0, 24.5, 2.6, 7.5];

function sv(s, i) = servo_dims(s)[i];

// ---------------------------------------------------------------- afgeleid
ps = pan_servo;
ts = tilt_servo;

floor_t   = 4;
ring_in   = sqrt(pow(sv(ps,0) - sv(ps,6) + (sv(ps,5) - sv(ps,0))/2, 2)
               + pow(sv(ps,1)/2, 2)) + 2;          // servo + oren passen erin
ring_out  = ring_in + wall;
base_r    = ring_out + 18;
cable_x   = sv(ps,0)/2 - sv(ps,6);               // hart kabelgoot in de voet
mount_angles = [90, 210, 330];
plat_bot  = floor_t + sv(ps,2) + sv(ps,9);         // onderkant pan-plateau
plat_t    = 5;
plat_r    = ring_out + 2;

ring_wall = 4;
R_ring    = tube_d/2 + ring_wall;                  // klemring buitenstraal
cw        = 2*R_ring;                              // binnenbreedte wieg
st        = 5;                                     // dikte zijplaten wieg
y_r       = cw/2 + st;                             // buitenkant zijplaat
bridge_t  = 5;
bridge_z  = R_ring + bridge_t;                     // bovenkant brug (camera)

up_t      = 6;                                     // dikte staanders
servo_plate_y = y_r + sv(ts,9) + sv(ts,2) - sv(ts,3);
pivot_y   = -(y_r + 1);                            // binnenkant pivot-staander
up_w      = sv(ts,1) + 14;
up_h      = tilt_z + sv(ts,6) + (sv(ts,5) - sv(ts,0))/2 + 5;

// ---------------------------------------------------------------- helpers
module rcube(size, r=2) {
    hull() for (x=[r, size[0]-r], y=[r, size[1]-r])
        translate([x, y, 0]) cylinder(r=r, h=size[2], $fn=24);
}

module hexnut(af, h) { cylinder(d=af/cos(30), h=h, $fn=6); }

// Servo in lokaal assenstelsel: hart as in de oorsprong, bovenkant behuizing
// op z=0, behuizing loopt naar -z, lengterichting langs +x.
module servo_dummy(s) {
    bl=sv(s,0); bw=sv(s,1); bh=sv(s,2); tz=sv(s,3); tt=sv(s,4); tl=sv(s,5);
    so=sv(s,6); xc = bl/2 - so;
    color("DimGray") {
        translate([-so, -bw/2, -bh]) cube([bl, bw, bh]);
        translate([xc - tl/2, -bw/2, -bh + tz]) cube([tl, bw, tt]);
    }
    color("White") {
        cylinder(d=6, h=sv(s,9));
        translate([0,0,sv(s,9)]) cylinder(d=sv(s,10), h=sv(s,11));
    }
}

// Uitsparing voor de behuizing (zonder oren) plus schroefgaten voor de oren.
module servo_body_cut(s, depth=100) {
    bl=sv(s,0); bw=sv(s,1); so=sv(s,6);
    translate([-so - clr, -bw/2 - clr, -depth]) cube([bl + 2*clr, bw + 2*clr, depth + 0.01]);
}
module servo_screw_holes(s, z0, h) {
    xc = sv(s,0)/2 - sv(s,6);
    for (dx=[-1,1]) translate([xc + dx*sv(s,7)/2, 0, z0]) cylinder(d=sv(s,8), h=h, $fn=16);
}

// Ronde horn: verdieping + schroefgaten + centraal gat voor de hornschroef.
module horn_cut(s, through=20) {
    translate([0,0,-0.01]) cylinder(d=sv(s,10) + 0.6, h=sv(s,11) + 0.01);
    cylinder(d=7, h=through, center=true);
    for (a=[0:90:270]) rotate(a) translate([sv(s,12), 0, 0])
        cylinder(d=1.8, h=through, center=true, $fn=12);
}

// ---------------------------------------------------------------- 1. voet
module base() {
    bh = sv(ps,2); tz = sv(ps,3);
    rim_top = plat_bot - 0.5;
    difference() {
        union() {
            cylinder(r=base_r, h=floor_t);
            cylinder(r=ring_out, h=rim_top);
            // stevig blok tot onder de servo-oren
            cylinder(r=ring_in + 0.01, h=floor_t + tz);
        }
        // binnenruimte boven de oren
        translate([0,0,floor_t + tz]) cylinder(r=ring_in, h=100);
        // behuizing servo
        translate([0,0,floor_t + bh]) servo_body_cut(ps, bh + 0.01);
        // schroefgaten oren
        servo_screw_holes(ps, floor_t + 2, tz + 1);
        // kabelgoot naar buiten
        translate([cable_x - 6, -base_r, floor_t]) cube([12, base_r, 8]);
        // doorvoer naar de sokkel aan het eind van de kabelgoot
        translate([cable_x - 6, -ring_out - 14, -1]) cube([12, 12, floor_t + 2]);
        // montagegaten (M4) voor sokkel, plank of statief
        for (a=mount_angles) rotate(a) translate([base_r - 8, 0, -1]) {
            cylinder(d=4.4, h=floor_t + 2);
            translate([0,0,floor_t - 1.5]) cylinder(d=8, h=5);
        }
    }
}

// ---------------------------------------------------------------- 2. pan-plateau + juk
gus_l = 10;

// staander vanaf y0 naar +y, met twee schoren aan de buitenkant
module upright(y0) {
    translate([-up_w/2, y0, 0]) rcube([up_w, up_t, up_h], 2);
    for (dx=[-1,1]) translate([dx*(up_w/2 - 2) - 2, y0 + up_t - 0.01, 0])
        rotate([90,0,90]) linear_extrude(4) polygon([[0,0], [gus_l,0], [0, up_h*0.55]]);
}

module pan() {
    difference() {
        union() {
            hull() {
                cylinder(r=plat_r, h=plat_t);
                translate([-up_w/2, servo_plate_y, 0]) rcube([up_w, up_t + gus_l, plat_t], 2);
                translate([-up_w/2, pivot_y - up_t - gus_l, 0]) rcube([up_w, up_t + gus_l, plat_t], 2);
            }
            translate([0,0,plat_t]) {
                upright(servo_plate_y);
                mirror([0,1,0]) upright(-pivot_y);
            }
        }
        // horn van pan-servo aan de onderkant
        horn_cut(ps, 40);
        // tilt-servo: behuizing door de staander, oren tegen de binnenkant
        translate([0,0,plat_t]) tilt_frame() {
            servo_body_cut(ts, 100);
            servo_screw_holes(ts, -sv(ts,2) + sv(ts,3) - 20, 20 + sv(ts,4) + 1);
        }
        // pivot (M4)
        translate([0, pivot_y + 1, plat_t + tilt_z]) rotate([90,0,0]) cylinder(d=4.4, h=up_t + 20);
        // kabeldoorvoer tilt-servo
        translate([up_w/2 + 2, servo_plate_y - 12, -1]) cube([8, 10, plat_t + 2]);
    }
}

// Transformeer van servo-lokaal naar juk-coordinaten (as horizontaal langs -y,
// behuizing hangt naar beneden).
module tilt_frame() {
    multmatrix([[0, 1, 0, 0],
                [0, 0,-1, y_r + sv(ts,9)],
                [-1,0, 0, tilt_z],
                [0, 0, 0, 1]]) children();
}

// ---------------------------------------------------------------- 3. wieg (tilt)
module cradle() {
    ring_len = 10;
    difference() {
        union() {
            // zijplaten (1 mm overlap met de ringen, anders raken ze alleen in een lijn)
            for (s=[-1,1]) translate([-cradle_len/2, s > 0 ? cw/2 - 1 : -cw/2 - st, -R_ring])
                cube([cradle_len, st + 1, R_ring + bridge_z]);
            for (x=[-1,1]) translate([x*(cradle_len/2 - ring_len/2), 0, 0])
                rotate([0,90,0]) cylinder(r=R_ring, h=ring_len, center=true);
            translate([-cradle_len/2, -y_r, R_ring - 1]) cube([cradle_len, 2*y_r, bridge_t + 1]);
            // bossen voor de borgschroeven onder de ringen
            for (x=[-1,1]) translate([x*(cradle_len/2 - ring_len/2), 0, -R_ring - 2])
                cube([ring_len, 10, 12], center=true);
        }
        rotate([0,90,0]) cylinder(d=tube_d + 2*clr, h=cradle_len + 2, center=true);
        // M3 borgschroef + moer per ring
        for (x=[-1,1]) translate([x*(cradle_len/2 - ring_len/2), 0, 0]) {
            translate([0,0,-R_ring - 10]) cylinder(d=3.3, h=14, $fn=16);
            translate([0,0,-R_ring - 4.5]) hull() {
                hexnut(5.7, 2.6);
                translate([x*10, 0, 0]) hexnut(5.7, 2.6);
            }
        }
        // horn tilt-servo in de rechter zijplaat
        translate([0, y_r, 0]) rotate([90,0,0]) horn_cut(ts, 2*st + 2);
        // pivot: M4 met moer aan de binnenkant van de linker zijplaat
        translate([0, -y_r - 1, 0]) rotate([-90,0,0]) cylinder(d=4.4, h=st + 2);
        translate([0, -cw/2 + 1.01, 0]) rotate([90,0,0]) hexnut(7.2, 4.4);
        // M3 gaten + moeren voor de camerahouder
        for (x=[-12, 12]) translate([x, 0, R_ring - 1]) {
            cylinder(d=3.3, h=bridge_t + 2, $fn=16);
            translate([0,0,-0.01]) hexnut(5.7, 3.1);
        }
    }
}

// ---------------------------------------------------------------- 4. camerahouder
// De print schuift van boven in twee rails. Voor grijpt een lip 1.2 mm over de
// rand, achter maar 0.6 mm omdat daar de pinheaders vlak langs de rand lopen.
cam_x0 = 2;    // achterkant PCB t.o.v. hart houder

module camholder() {
    base_l = 32; base_w = cam_w + 2*4 + 2; base_t = 4;
    lip_f = 1.2; lip_b = 0.6; rail_t = 2.5; rail_h = cam_l + 1;
    gx0 = cam_x0 - clr; gx1 = cam_x0 + cam_pcb_t + clr;     // sleuf in x
    difference() {
        union() {
            translate([-base_l/2, -base_w/2, 0]) rcube([base_l, base_w, base_t], 2);
            for (m=[0,1]) mirror([0,m,0])
                translate([gx0 - 1.5, cam_w/2 - lip_f, 0])
                    cube([gx1 - gx0 + 3, lip_f + clr + rail_t, base_t + rail_h]);
        }
        for (m=[0,1]) mirror([0,m,0]) {
            translate([gx0, cam_w/2 - lip_f - 1, base_t]) cube([gx1 - gx0, lip_f + 1 + clr, rail_h + 1]);
            translate([gx0 - 2, cam_w/2 - lip_f - 1, base_t]) cube([2.01, lip_f + 1 - lip_b, rail_h + 1]);
        }
        for (x=[-12, 12]) translate([x, 0, -1]) {
            cylinder(d=3.3, h=base_t + 2, $fn=16);
            translate([0,0,base_t - 1.2]) cylinder(d=6, h=5, $fn=24);
        }
    }
}

// ---------------------------------------------------------------- 5. sokkel met gezicht
// Vaste "kop" onder de voet: OLED-gezicht en praatknop aan de voorkant (+x),
// luidspreker links (+y), microfoon rechts (-y, ver van de luidspreker),
// USB-C van de ESP32-S3 aan de achterkant. Print ondersteboven (bovenkant op het bed).
head_h   = 55;
head_s   = 2*base_r + 4;      // vierkant, past onder de voet
head_w   = 2.4;               // wand (drukknop: max ~5 mm)
head_top = 5;
lid_t    = 3;
boss_xy  = head_s/2 - head_w - 4;

oled_pcb   = [27, 27];        // 0.96" SSD1306; 1.3" SH1106: [35.5, 33.5]
oled_holes = [23, 23];        //                             [30.5, 28]
oled_hole_d = 2.2;            //                             3.2
oled_view  = [23, 12.5];      // zichtbaar 21.7 x 10.9 + marge
oled_view_dz = -1.5;          // glas zit iets onder het hart (header bovenaan)
oled_z     = -head_h/2 + 4;
button_d   = 12;
spk_d      = 40;
mic_d      = 14;

module head() {
    difference() {
        union() {
            difference() {
                translate([-head_s/2, -head_s/2, -head_h]) rcube([head_s, head_s, head_h], 6);
                translate([-head_s/2 + head_w, -head_s/2 + head_w, -head_h - 1])
                    rcube([head_s - 2*head_w, head_s - 2*head_w, head_h + 1 - head_top], 4);
            }
            // schroefbussen voor de bodemplaat
            for (x=[-1,1], y=[-1,1]) translate([x*boss_xy, y*boss_xy, -head_h])
                cylinder(d=8, h=head_h - 0.01);
            // ring voor de luidspreker tegen de linkerwand
            translate([-15, head_s/2 - head_w + 0.01, -head_h/2]) rotate([90,0,0])
                difference() { cylinder(d=spk_d + 6, h=4); translate([0,0,-1]) cylinder(d=spk_d + 0.6, h=6); }
            // kraag voor de microfoon tegen de rechterwand
            translate([-30, -head_s/2 + head_w - 0.01, -head_h/2]) rotate([-90,0,0])
                difference() { cylinder(d=mic_d + 4, h=3); translate([0,0,-1]) cylinder(d=mic_d + 0.6, h=5); }
            // bussen voor de OLED-schroeven
            translate([head_s/2 - head_w + 0.01, 0, oled_z]) for (y=[-1,1], z=[-1,1])
                translate([0, y*oled_holes[0]/2, z*oled_holes[1]/2]) rotate([0,-90,0]) cylinder(d=5, h=2);
        }
        // M4 naar de voet, moer aan de binnenkant
        for (a=mount_angles) rotate(a) translate([base_r - 8, 0, -head_top - 1]) {
            cylinder(d=4.4, h=head_top + 2);
            hexnut(7.2, 3.4);
        }
        // kabeldoorvoer onder de kabelgoot van de voet
        translate([cable_x - 6, -ring_out - 14, -head_top - 1]) cube([12, 12, head_top + 2]);
        // OLED-venster + schroefgaten
        translate([head_s/2 - head_w - 3, -oled_view[0]/2, oled_z + oled_view_dz - oled_view[1]/2])
            cube([head_w + 4, oled_view[0], oled_view[1]]);
        translate([head_s/2 + 1, 0, oled_z]) for (y=[-1,1], z=[-1,1])
            translate([0, y*oled_holes[0]/2, z*oled_holes[1]/2]) rotate([0,-90,0]) cylinder(d=oled_hole_d, h=head_w + 4, $fn=16);
        // praatknop
        translate([head_s/2 - head_w - 1, 34, oled_z]) rotate([0,90,0]) cylinder(d=button_d + 0.4, h=head_w + 2);
        // luidsprekerrooster (gaatjes 2 mm)
        translate([-15, head_s/2 + 1, -head_h/2]) rotate([90,0,0])
            for (i=[-6:6], j=[-6:6]) let(p=[i*3.2 + (j%2)*1.6, j*2.8])
                if (norm(p) < spk_d/2 - 4) translate(p) cylinder(d=2, h=head_w + 2, $fn=12);
        // microfoongaatje
        translate([-30, -head_s/2 - 1, -head_h/2]) rotate([-90,0,0]) cylinder(d=2.5, h=head_w + 2, $fn=16);
        // USB-C van de ESP32-S3 aan de achterkant
        translate([-head_s/2 - 1, -7, -head_h + lid_t + 11 + 1.6 - 1]) cube([head_w + 2, 14, 8]);
        // schroefgaten bussen
        for (x=[-1,1], y=[-1,1]) translate([x*boss_xy, y*boss_xy, -head_h - 1])
            cylinder(d=2.8, h=20, $fn=16);
    }
}

// Bodemplaat met twee steunbalkjes voor de ESP32-S3-DevKitC-1 (tussen de pinrijen,
// vastzetten met dubbelzijdig tape) en twee voor de MAX98357A.
module head_lid() {
    esp_l = 63; esp_w = 25.5;
    ex0 = -head_s/2 + head_w + 1;             // USB-kant tegen de achterwand
    difference() {
        union() {
            translate([-head_s/2 + head_w + 0.3, -head_s/2 + head_w + 0.3, 0])
                rcube([head_s - 2*head_w - 0.6, head_s - 2*head_w - 0.6, lid_t], 4);
            for (x=[12, esp_l - 14]) translate([ex0 + x, -8, 0]) cube([4, 16, lid_t + 11]);
            // aanslagen aan het eind van de print
            translate([ex0 + esp_l + 0.5, -esp_w/2, 0]) cube([2, esp_w, lid_t + 14]);
            for (x=[0, 12]) translate([10 + x, 20, 0]) cube([4, 14, lid_t + 4]);
        }
        for (x=[-1,1], y=[-1,1]) translate([x*boss_xy, y*boss_xy, -1]) {
            cylinder(d=3.3, h=lid_t + 2, $fn=16);
            cylinder(d=6.2, h=2.2, $fn=24);
        }
    }
}

// ---------------------------------------------------------------- weergave
module esp32cam_dummy() {
    color("DarkGreen") cube([cam_pcb_t, cam_w, cam_l]);
    color("Black") translate([cam_pcb_t, cam_w/2 - 4, cam_l - 17]) cube([4, 8, 8]);
    color("Silver") translate([cam_pcb_t + 4, cam_w/2, cam_l - 13]) rotate([0,90,0]) cylinder(d=6, h=3);
}

module assembly() {
    color("SeaGreen") head();
    color("DarkSeaGreen") translate([0,0,-head_h]) head_lid();
    color("SteelBlue") base();
    translate([0,0,floor_t + sv(ps,2)]) servo_dummy(ps);
    translate([0,0,plat_bot]) rotate(pan_angle) {
        color("Orange") pan();
        translate([0,0,plat_t]) tilt_frame() servo_dummy(ts);
        translate([0,0,plat_t + tilt_z]) rotate([0,-elevation,0]) {
            color("Gold") cradle();
            color("LightGray", 0.6) translate([-cradle_len/2 - tube_back, 0, 0])
                rotate([0,90,0]) difference() {
                    cylinder(d=tube_d, h=tube_len);
                    translate([0,0,-1]) cylinder(d=tube_d - 3, h=tube_len + 2);
                }
            translate([0,0,bridge_z]) {
                color("MediumPurple") camholder();
                translate([cam_x0, -cam_w/2, 4]) esp32cam_dummy();
            }
        }
    }
}

// ---------------------------------------------------------------- printoriëntatie
if (part == "base") base();
else if (part == "pan") pan();
else if (part == "cradle") translate([0,0,cradle_len/2]) rotate([0,90,0]) cradle();
else if (part == "camholder") camholder();
else if (part == "head") rotate([180,0,0]) head();
else if (part == "head_lid") head_lid();
else assembly();
