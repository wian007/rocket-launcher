// Lanceerinstallatie met minimale 3D-prints.
// Alles is standaard (metalen pan/tilt-beugelset, PVC-installatiebuis met
// buisklemmen, projectdoos) behalve één klein geprint deel: de ESP32-CAM-clip.
//   openscad -D 'part="camclip"' -o camclip.stl minimal.scad
// part: "camclip" (printen) of "assembly" (alleen bekijken).

part = "assembly";

tube_d    = 20;     // PVC-installatiebuis 20 mm (16 en 25 mm kan ook)
tube_len  = 300;
elevation = 40;     // alleen weergave
pan_angle = 25;     // alleen weergave

clr = 0.3;
$fn = 64;

// ESP32-CAM (AI-Thinker)
cam_w = 27; cam_l = 40.5; cam_pcb_t = 1.6;

// Projectdoos (bijv. ABS-aansluitdoos ±150 x 110 x 70 mm)
box = [150, 110, 70];

module rcube(size, r=2) {
    hull() for (x=[r, size[0]-r], y=[r, size[1]-r])
        translate([x, y, 0]) cylinder(r=r, h=size[2], $fn=24);
}

// ---------------------------------------------------------------- het enige printdeel
// Rails waar de ESP32-CAM van boven in schuift. Voor 1.2 mm lip over de rand,
// achter 0.6 mm zodat de pinheaders vrij blijven. De voet heeft sleufgaten
// (M3) zodat hij op elk gatenpatroon van de U-beugel past, en twee sleuven
// voor tie-wraps als je liever niet boort.
module camclip() {
    base_l = 34; base_w = cam_w + 12; base_t = 3;
    lip_f = 1.2; lip_b = 0.6; rail_t = 2.5; rail_h = cam_l * 0.6;
    x0 = 0;
    gx0 = x0 - clr; gx1 = x0 + cam_pcb_t + clr;
    difference() {
        union() {
            translate([-base_l/2, -base_w/2, 0]) rcube([base_l, base_w, base_t], 2);
            for (m=[0,1]) mirror([0,m,0])
                translate([gx0 - 1.5, cam_w/2 - lip_f, 0])
                    cube([gx1 - gx0 + 3, lip_f + clr + rail_t, base_t + rail_h]);
            // aanslag onder de print
            translate([gx0 - 1.5, -cam_w/2, 0]) cube([gx1 - gx0 + 3, cam_w, base_t + 1]);
        }
        for (m=[0,1]) mirror([0,m,0]) {
            translate([gx0, cam_w/2 - lip_f - 1, base_t + 1]) cube([gx1 - gx0, lip_f + 1 + clr, rail_h + 1]);
            translate([gx0 - 2, cam_w/2 - lip_f - 1, base_t + 1]) cube([2.01, lip_f + 1 - lip_b, rail_h + 1]);
        }
        // sleufgaten M3 (voor en achter de print)
        for (x=[-12, 12]) hull() for (y=[-6, 6]) translate([x, y, -1]) cylinder(d=3.4, h=base_t + 2, $fn=16);
        // tie-wrap-sleuven
        for (y=[-1,1]) translate([-8, y*(base_w/2 - 2.5) - 1.5, -1]) cube([16, 3, base_t + 2]);
    }
}

// ---------------------------------------------------------------- weergave van de standaarddelen
module servo_block() {   // MG995 met de as op de oorsprong, as langs +z
    color("DimGray") translate([-10, -9.85, -37]) cube([40.7, 19.7, 37]);
    color("DimGray") translate([-16.7, -9.85, -10]) cube([54, 19.7, 2.5]);
    color("White") cylinder(d=24, h=6);
}

module bracket_color() { color("Silver") children(); }

module assembly() {
    // projectdoos met gezicht in de voorkant
    color("WhiteSmoke") translate([-box[0]/2, -box[1]/2, -box[2]]) cube(box);
    color("Black") translate([box[0]/2, -12, -box[2]/2]) cube([0.5, 24, 13]);       // OLED
    color("Red") translate([box[0]/2, 30, -box[2]/2 + 6]) rotate([0,90,0]) cylinder(d=12, h=4);  // knop
    color("DimGray") for (i=[-3:3], j=[-3:3]) if (i*i + j*j < 10)
        translate([-30 + i*4, box[1]/2, -box[2]/2 + j*4]) rotate([-90,0,0]) cylinder(d=2, h=0.6);  // rooster
    // pan: servo staand in de multifunctionele beugel op het deksel
    bracket_color() translate([-17, -14, 0]) difference() {
        cube([55, 28, 30]); translate([2, 2, 2]) cube([51, 24, 30]);
    }
    translate([0,0,42]) servo_block();
    // draaiend deel
    translate([0,0,48]) rotate(pan_angle) {
        // multifunctionele beugel met de tilt-servo liggend
        bracket_color() translate([-28, -14, 0]) difference() {
            cube([56, 28, 2]);
        }
        bracket_color() for (y=[-1,1]) translate([-10, y*24 - 1, 0]) cube([20, 2, 45]);
        translate([0, 26, 40]) rotate([-90,0,0]) servo_block();
        // lange U-beugel aan de tilt-horn, kantelt om de y-as
        translate([0, 0, 40]) rotate([0, -elevation, 0]) {
            bracket_color() {
                for (y=[-1,1]) translate([-8, y*22 - 1, -35]) cube([16, 2, 37]);
                translate([-8, -23, -37]) cube([16, 46, 2]);
            }
            // buis met twee buisklemmen op de bodem van de U-beugel
            translate([0, 0, -37 - tube_d/2 - 4]) {
                color("LightGray") translate([-tube_len*0.35, 0, 0]) rotate([0,90,0]) difference() {
                    cylinder(d=tube_d, h=tube_len); translate([0,0,-1]) cylinder(d=tube_d - 3, h=tube_len + 2);
                }
                color("DarkGray") for (x=[-5, 5]) translate([x, 0, 0]) rotate([0,90,0])
                    difference() { cylinder(d=tube_d + 4, h=6, center=true); cylinder(d=tube_d, h=8, center=true); }
            }
            // camclip op de zijkant van de U-beugel, camera kijkt langs de buis
            translate([0, -23, -18]) rotate([90,0,0]) {
                color("MediumPurple") camclip();
                color("DarkGreen") translate([0, -cam_w/2, 4]) cube([cam_pcb_t, cam_w, cam_l]);
            }
        }
    }
}

if (part == "camclip") camclip();
else assembly();
