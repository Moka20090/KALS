# KALS_BayModels (T600)

Our own payload bay models for SOCK's OV-100 mid fuselage (`benjee10_shuttle_midFuselage`): sills, MPM pedestals,
latch rails + latches, handrails, blankets, floodlights + CCTV, wire trays, bulkhead detail, bridge fittings,
EVA slidewires + foot restraints, the PSA tool box.  `Models/*.mu` are written by script (a KSP .mu writer,
`the dev tools`); `Patches/KALS_BayModels.cfg` adds them to the part (MODEL nodes, the arm's shoulder
NODE `kalsArmShoulder`, ModuleLight for the six floodlights = the Lights action group).  Remove this folder and the
mid fuselage is stock SOCK again.
