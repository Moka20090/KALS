# KAL/S RealAscent

ModuleManager patches that give the Space Shuttle launch stack built from the Benjee10 Shuttle Orbiter Construction Kit
(SOCK) orbiter, the Photon Corp SRBs and the ORANGES external tank the real Space Shuttle's ascent at Quarter scale: a
quarter of the real masses and thrusts, the real thrust-to-weight at liftoff and after SRB separation, and the real
Shuttle's delta-v scaled to a Quarter-scale Earth.

## Requirements

-ModuleManager
-B9PartSwitch
-SOCK
-Photon Corp (the SRBs)
-ORANGES (the external tank)
-Rocket Motor Menagerie (the SSMEs)

## Install

Drop the folder into Kerbal Space Program/GameData

## Uninstall

Delete the folder and restart. Nothing is modified in place — every patch is additive or an
edit applied at load time, so removing it restores the parts exactly.

**Existing craft keep their old loads** KSP saves each part's propellant and the SRB settings in
the craft, so on existing craft: set both SRBs' thrust curve to RSRM and their thrust limiter to
100 %, fill the SRBs, their nose cones and the external tank, and add the payload. New parts get
all of this by default.

**The payload** The SOCK RealAscent Payload (2.94 t, in the Payload category) brings the orbiter
to the real orbiter's liftoff mass at Quarter scale. Attach it by its bottom node, e.g. to a
payload bay node. It is not staged: right-click Decouple in orbit to deploy it.

**Every craft with these parts changes** The patches apply to all Cotopaxi engines, RSRB-4 SRBs,
their nose cones and radial decouplers, and the STS external tank, in any craft.

## Changes

-Gives the SSMEs 53% of their Isp (240 s vacuum, 194 s at sea level) at the same thrust, so the stack has the real Shuttle's delta-v scaled to Quarter scale.
-Makes the SRBs quarter-scale RSRMs: a quarter of the real casing mass (21.75 t with the nose cone and decoupler) and propellant (125 t), a quarter of the real liftoff thrust plus 2.4% (3.19 MN at sea level), and two thirds of the Isp (179 s vacuum, 161 s at sea level), so they burn for 80 s.
-Adds the RSRM thrust curve, the real RSRM's thrust profile for a full load: a peak early in the burn, the max-q bucket near two thirds of the thrust, a recovery and the tail-off, in 80 s instead of the real 123 s.
-Gives the external tank a quarter of the real tank's dry mass (5.74 t Super Lightweight, 6.61 t Lightweight, 7.86 t Standard, without its decoupler) and a quarter of the real propellant plus 5.6% (194.3 t), so the stack keeps the real thrust-to-weight after SRB separation with the longer SRB burn.
-Adds a 2.94 t payload.
-Scales the SRBs' separation motors and decouplers with the heavier casings, so the SRBs separate as before.
-Together, with the SOCK orbiter and the payload: 523 t at liftoff, a thrust-to-weight of 1.50 at liftoff and 0.96 after SRB separation at 80 s, and 5,250 m/s of delta-v without the OMS (56% of the real Shuttle's), with main engine cutoff at about 4 min 41 s at the 3 g limit.
-Adds a filament-wound case (FWC) option to the SRBs in the VAB, 3.25 t lighter each, as built for the polar launches from Vandenberg. The steel case stays the default, and the totals above are for it.

## Reference source

-NSTS 1988 News Reference Manual
-NASA Space Shuttle SRB, external tank and SSME fact sheets
