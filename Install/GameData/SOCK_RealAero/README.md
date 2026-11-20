# SOCK RealAero 1.3

ModuleManager patches and a plugin that bring the Benjee10 Shuttle Orbiter Construction Kit (SOCK)
orbiter's aerodynamics, heat shielding and landing gear closer to the real Space Shuttle Orbiter.
Optional parts: a patch set for Ferram Aerospace Research (FAR), one continuous re-entry envelope for
Firefly, and a hypersonic pitch correction for the stock aerodynamics.

## Requirements

- ModuleManager
- SOCK
- SPOCK (optional: only for its drag chute)
- Ferram Aerospace Research (optional: see With FAR)
- Firefly (optional: see With Firefly)

## Install

Drop the folder into Kerbal Space Program/GameData.

## Upgrade

Delete the old GameData/SOCK_RealAero folder first, then install. 1.3 keeps SockFarTrim's tables in
Patches/far_trim.cfg; an older install has them as a loose far_trim.cfg beside the README, and with both
present the plugin reads only the first (the log says so).

## Uninstall

Delete the folder and restart. Nothing is modified in place: every patch is additive or an edit applied at
load time, so removing it restores stock SOCK exactly.

**Craft files are unchanged.** No part names, nodes or attachment rules change, so existing `.craft` files
load unchanged and vessels already in flight keep flying. A vessel in orbit at install time will enter on
the new aero.

**Landing gear sliders.** The gear's Spring Strength, Damper Strength and Auto Spring/Damper settings are
saved in each craft and each vessel, so set them on existing craft and vessels already in flight: Spring
Strength 1, Damper Strength 2, Auto Spring/Damper off, on all three gear. New gear gets these by default.
Keep Auto Friction on.

## With FAR

With FAR installed, 1_aero.cfg switches itself off (FAR replaces the stock aerodynamics it tunes) and
6_far.cfg gives FAR the orbiter's wing, elevon, body flap and fin geometry instead. Plugins/SockRealAero.dll
then adds the SockFarTrim module (7_far_trim.cfg) to the orbiter's mid fuselage. It makes the orbiter fly
like the stock-aero orbiter that guidance and autopilots written for the stock aerodynamics (KAL/S, for one)
are fitted to:

- the control surfaces move at stock's 40 deg/s;
- the difference between the stock orbiter's aerodynamics and FAR's (lift, drag, pitch moment, the elevons'
  power, the speedbrake) is added from Patches/far_trim.cfg;
- the speedbrake, the split rudder, FAR's stall on the elevons, the subsonic elevator, the gear's drag and
  lift, and the launch stack's drag are corrected to stock's;
- on the main gear the pitch moment is corrected to stock's, so the nose comes down at the derotation's rate;
- the Brakes action group opens the speedbrake when no script flies it.

Each correction can be switched off in 7_far_trim.cfg (or by removing its node from far_trim.cfg). Without
FAR, 6_far.cfg, 7_far_trim.cfg and far_trim.cfg do nothing.

## With Firefly

With Firefly installed, Plugins/SockRealAero.dll gives the orbiter one continuous re-entry envelope: the
fuselage, wing and gear doors are merged into one skin, and the elevons, body flap and rudder each get their
own envelope that deflects with them. Firefly otherwise builds a separate envelope for each part, which shows
as dark seams and bright gaps at the joints. Patches/8_firefly.cfg holds its settings (enabled = false leaves
Firefly exactly as it ships). Without Firefly this patch does nothing.

## Hypersonic pitch correction (stock aerodynamics)

Without FAR, the stock orbiter needs its body flap on the nose-up stop and the elevons trailing edge up for
the whole hypersonic entry. SockPitchFix (Patches/9_pitch_fix.cfg) adds the missing nose-up torque from
Mach 2.5 up. It is on by default; the switch is the module's pitchFix field in Patches/9_pitch_fix.cfg (true = on, false = off),
and its scale field sets the share of the correction (1.0 = all).

## Files

- Patches/1_aero.cfg: Aerodynamics: the lift and drag curves, the drag cubes, the engines' and control surfaces' drag, the rudder's lift curve and the zero-lift key. Off under FAR.
- Patches/2_thermal.cfg: Heat shielding: the TPS thermal properties of the wing, elevons, body flap and fuselage.
- Patches/3_landing.cfg: Landing: the gear's brakes, suspension and tyres.
- Patches/4_vehicle.cfg: The vehicle: the centre-of-gravity ballast.
- Patches/5_dragchute.cfg: SPOCK's drag chute. Delete it if you don't have SPOCK.
- Patches/6_far.cfg: FAR only: the wing, elevon, body flap and fin geometry for FAR's wing model, and the drag chute's size.
- Patches/7_far_trim.cfg: FAR only: adds the SockFarTrim module to the orbiter's mid fuselage.
- Patches/far_trim.cfg: FAR only: SockFarTrim's tables.
- Patches/8_firefly.cfg: Firefly only: the settings of the orbiter's re-entry envelope.
- Patches/9_pitch_fix.cfg: Stock aerodynamics only: the SockPitchFix module and its table.
- Patches/10_elevon_curve.cfg: Stock aerodynamics only: the elevons' lift and drag curves continued past 50 deg of local AoA (the sin^2 law), so the aileron and the elevator keep their power with the elevons trimmed nose-down at high alpha.
- Patches/11_lift_curve.cfg: Stock aerodynamics only: the body flap's lift and drag curves and the wing's and the fuselage's lift curves continued past 50 deg of local AoA (the same law), so the body flap keeps its pitch-trim power when it is trimmed far down at high alpha.
- Plugins/SockRealAero.dll: SOCK RealAero's plugin: SockFarTrim, SockFirefly, SockPitchFix and SockFarChute. It needs neither kOS nor KAL/S.
- SOCK_RealAero.version: the version file for KSP-AVC.
- LICENSE.txt: the licence (MIT).

## Changes

- Changes lift and drag coefficients on most SOCK parts to get within 5-10% of the real orbiter's values.
- Lift falls to zero at zero incidence, like the real orbiter's.
- Changes the fuselage's thermal properties to match a TPS-covered fuselage, needed in Quarter or Real scale.
- Gives the main and nose gear a realistic suspension: no bottoming out, bouncing or riding high after landing; the nose wheel stays against its strut.
- Gives the gear tyres realistic grip: the orbiter doesn't rock from wheel to wheel on the runway and the brakes don't lock up.
- Moves 0.6 t from the forward to the aft fuselage, so the orbiter enters with its CoM on the trim point.
- Gives the wing, elevons and body flap the fuselage's thermal properties, so they don't overheat during entry in Quarter or Real scale.
- Doubles the gear's brake torque, so the orbiter brakes firmly while the brake slider stays below 100 %, where KSP switches to a parking brake that locks the wheels.
- Removes the elevons' and body flap's drag below Mach 0.485 and halves it from Mach 0.51 to 0.6, so the orbiter flares with its speedbrake partly open after the 3000 ft retract and still touches down at the real orbiter's speeds.
- Gives the split rudder a lift curve without the 30 deg stall that holds its side force to 55 deg, and a larger fin, stronger above Mach 1, so the rudder steers at every speedbrake setting without closing the speedbrake; the speedbrake's drag is kept.
- Gives SPOCK's drag chute the real orbiter's stopping power for the orbiter's mass, and keeps its deployed drag shape when the part switches style.
- Raises the lift and lowers the wing's, fuselage's and control surfaces' own drag above Mach 2.5, so the orbiter enters with the real orbiter's lift-to-drag ratio (1.08 at 40 degrees angle of attack, up from 0.89).
- With Firefly installed, gives the orbiter one continuous re-entry plasma envelope instead of one per part.
- With FAR installed, switches the stock aerodynamics patches off, gives FAR the orbiter's surface geometry and makes the orbiter fly like the stock-aero orbiter (SockFarTrim).
- With FAR installed, the drag chute opens to stock's size (19.2 m2; SockFarChute keeps 6_far.cfg's diameters, which FAR's own chute code would replace with 1.7 / 0.5 m).
- Optionally corrects the stock orbiter's hypersonic pitch trim (SockPitchFix).

## Credits

- Benjee10, for the Shuttle Orbiter Construction Kit (SOCK) this patches.
- SPOCK, for the drag chute.
- Ferram Aerospace Research, Firefly and ModuleManager, which the optional parts and the plugin work with.
- SOCK RealAero by Moka20090.

## Licence

MIT (LICENSE.txt), copyright Moka20090 only, as SOCK RealAero 1.1 on SpaceDock. SOCK, SPOCK, FAR, Firefly and ModuleManager keep their own licences.
