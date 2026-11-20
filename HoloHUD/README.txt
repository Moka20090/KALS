# Holo HUD 1.0.0

A head-up display for any aircraft in Kerbal Space Program, drawn in the flight view by a kOS script.
It shows the boresight, the velocity vector, the horizon and pitch ladder, the airspeed (KEAS) and
altitude tapes, the throttle and SAS. Below 5000 ft the altitude tape shows the height of the wheels
above the ground. Holo HUD only draws: it never flies the craft or touches its controls.
It works on any craft with a kOS processor part.

## Requirements

- KSP 1.12 (tested on 1.12.5)
- kOS 1.6.0.1
- kOS StockCamera 0.3.1 (included; the HUD CAM button needs it)
- Python 3, for the installer only

## Install

Close KSP, unzip, and double-click INSTALL.bat. INSTALL.txt has the steps and the install by hand.

## Uninstall

Double-click UNINSTALL.bat. It removes only what the installer added and puts back any file it replaced.

## Use

In the flight view, open the craft's kOS terminal and type `SWITCH TO 0.` then `RUN hud.ks.`
A small window at the top left has the buttons:

- HUD ON / OFF: shows or hides the HUD.
- HUD CAM: puts the camera at the cockpit's eye. Only in this view do the HUD's lines sit on the world behind them.
- The eye buttons and RESET: move the HUD CAM's eye. Each craft keeps its own eye position.
- QUIT: closes the HUD and gives you the normal camera back.

## The plugin

GameData/HoloHUD/Plugins/HoloHud.dll does the HUD's maths, which keeps it fast. Without it, kOS does the
maths itself: the HUD is slower and the eye buttons are missing. The kOS terminal says which one runs when
the HUD starts.

## Files

- README.txt, INSTALL.txt: this file and the install steps.
- INSTALL.bat, UNINSTALL.bat, install_holohud.py: the installer.
- kOS-StockCamera-0.3.1-source.zip: the source code of kOS StockCamera.

The Install folder holds what goes into your KSP folder:

- GameData/HoloHUD/Plugins/HoloHud.dll: the plugin.
- GameData/HoloHUD/HoloHUD.version: the version file for KSP-AVC.
- GameData/HoloHUD/CHANGELOG.txt, LICENSE: the changes and the licence (MIT).
- GameData/kOS-Addons/StockCamera: kOS StockCamera 0.3.1, a separate program (see Licence).
- Ships/Script/hud.ks: the program you run.
- Ships/Script/lib: the HUD's libraries.
- Ships/Script/hud: the HUD's images for a 3840x2160 screen. The installer builds the set for your screen.
- Ships/Script/hud_build.py: builds the HUD's images for a screen size and field of view.

## Known limits

- No runway outline and no guidance symbols.
- The HUD's text is Arial.
- Outside HUD CAM, the HUD is a flat overlay that does not line up with the world.
- One HUD per kOS processor, and that processor can run nothing else at the same time.

## Credits

- Holo HUD by Moka20090.
- kOS, by the kOS team and contributors.
- kOS StockCamera, by the kOS StockCamera contributors.

## Licence

Holo HUD: MIT (GameData/HoloHUD/LICENSE), copyright 2026 Moka20090. kOS StockCamera is a separate program under the GPL-3
(GameData/kOS-Addons/StockCamera/LICENSE.md). Its source is in kOS-StockCamera-0.3.1-source.zip.
