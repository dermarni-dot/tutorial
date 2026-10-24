#!/usr/bin/env python3
"""Build BecomeAWorldClassBoxer.rbxlx with rojo and pin the Workspace settings rojo's reflection database does
not know yet.

    python3 tools/build_place.py [OUT.rbxlx]

* Workspace.AvatarJointUpgrade = Disabled (Enum.RolloutState 1): with the upgrade on, R15 characters are rigged
  with AnimationConstraints instead of Motor6Ds; the procedural Animator, the head/headgear welds and the
  diagnostics all expect Motor6Ds (the user's /wcbdiag showed every joint "missing" and the character dead).
  Main.server.lua also sets it at runtime as a fallback.
"""
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "BecomeAWorldClassBoxer.rbxlx")
subprocess.check_call(["rojo", "build", "-o", out], cwd=ROOT)
with open(out, encoding="utf-8") as f:
    s = f.read()
m = re.search(r'(<Item class="Workspace"[^>]*>\s*<Properties>)', s)
if not m:
    sys.exit("build_place: no Workspace item in " + out)
if "AvatarJointUpgrade" not in s[m.end():m.end() + 4000]:
    s = s[:m.end()] + '\n\t\t\t<token name="AvatarJointUpgrade">1</token>' + s[m.end():]
    with open(out, "w", encoding="utf-8") as f:
        f.write(s)
    print("build_place: pinned Workspace.AvatarJointUpgrade = Disabled")
else:
    print("build_place: AvatarJointUpgrade already present")
