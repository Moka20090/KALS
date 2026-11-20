#!/bin/bash
# Builds GameData/KALS_Coproc/Plugins/KalsCoproc.dll (the KAL/S coprocessor, a kOS addon: ADDONS:KALS) with the C#
# compiler that ships with Windows (.NET Framework 4, C# 5), against KSP's and kOS's own DLLs. Run from Git Bash:
#     ./build.sh "<your KSP folder>"
# The FAR parts (SockFarTrim.cs, KalsAddon.Far.cs) reach FAR by reflection only, so one DLL serves both installs.
# PadFrame.cs patches KSP through Harmony (GameData/000_Harmony); without it in the game that one patch is skipped.
# UnityEngine.InputLegacyModule: Unity's Input (KalsKeys.cs reads the keys for ops2q).
# KalsAddon.HoHud.cs asks Holo HUD for its host: run ../holo/build.sh FIRST (it makes ../holo/HoloHud.dll, the reference here).
# kals_elbow.cfg (a ModuleManager patch) puts KalsElbow.cs's module on the KerboArm elbow; it goes in beside the DLL.
# The checks against kOS (the fast-time flights in kOS's VM, the PEG replay) live with the team's tools, outside the repo.
set -e
# T997 D843 (the owner's choice B): ./build.sh <the KSP folder> --release <out.dll> builds the RELEASE DLL (-define:KALS_RELEASE: no
# test harness, SAIL's files and suffixes left out) to <out.dll> and stops there (nothing into GameData; the dev tools/
# run_release.py packs it). Without --release: the dev DLL (with SAIL), built and installed as before.
DEF=""; ROUT=""
if [ "${2:-}" = "--release" ]; then
  DEF="-define:KALS_RELEASE"; ROUT="${3:?usage: ./build.sh <the KSP folder> --release <out.dll>}"
  mkdir -p "$(dirname "$ROUT")"; ROUT="$(cd "$(dirname "$ROUT")" && pwd)/$(basename "$ROUT")"
fi
set -e
K="${1:?usage: ./build.sh <the KSP folder>}"; M="$K/KSP_x64_Data/Managed"; cd "$(dirname "$0")"
# T997 D867: the release package ships the source without the test harness (Sail.cs and its two partners): build it as KALS_RELEASE
if [ ! -f Sail.cs ]; then DEF="-define:KALS_RELEASE"; fi
/c/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe -nologo -noconfig -optimize+ -target:library -nostdlib+ $DEF \
  -r:"$M/mscorlib.dll" -r:"$M/System.dll" -r:"$M/System.Core.dll" -r:"$K/GameData/kOS/Plugins/kOS.dll" \
  -r:"$K/GameData/kOS/Plugins/kOS.Safe.dll" -r:"$M/Assembly-CSharp.dll" -r:"$M/UnityEngine.dll" \
  -r:"$M/UnityEngine.CoreModule.dll" -r:"$M/UnityEngine.PhysicsModule.dll" \
  -r:"$M/UnityEngine.UI.dll" -r:"$M/UnityEngine.UIModule.dll" -r:"$M/UnityEngine.IMGUIModule.dll" \
  -r:"$M/UnityEngine.TextRenderingModule.dll" -r:"$M/UnityEngine.InputLegacyModule.dll" \
  -r:"$M/UnityEngine.AudioModule.dll" -r:"$M/UnityEngine.ScreenCaptureModule.dll" -r:"$M/UnityEngine.ImageConversionModule.dll" \
  -r:"$K/GameData/000_Harmony/0Harmony.dll" -r:"../holo/HoloHud.dll" -out:KalsCoproc.dll *.cs
if [ -n "$ROUT" ]; then cp KalsCoproc.dll "$ROUT"; md5sum "$ROUT"; exit 0; fi
# An old GameData/SockCoproc (the folder's former name) beside KALS_Coproc would load the addon twice
if [ -d "$K/GameData/SockCoproc" ]; then echo "GameData/SockCoproc is there: rename it to KALS_Coproc first" >&2; exit 1; fi
# the DLL was SockCoproc.dll until the rename; both beside each other would load the addon twice
if [ -f "$K/GameData/KALS_Coproc/Plugins/SockCoproc.dll" ]; then echo "GameData/KALS_Coproc/Plugins/SockCoproc.dll is there: delete it first (T586: the DLL is KalsCoproc.dll now)" >&2; exit 1; fi
mkdir -p "$K/GameData/KALS_Coproc/Plugins"; cp KalsCoproc.dll "$K/GameData/KALS_Coproc/Plugins/"
cp kals_elbow.cfg "$K/GameData/KALS_Coproc/"
