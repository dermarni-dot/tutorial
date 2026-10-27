#!/usr/bin/env python3
"""Build BecomeAWorldClassBoxer.rbxlx with rojo and pin the place settings rojo's reflection database cannot write.

    python3 tools/build_place.py [OUT.rbxlx]

* StarterPlayer.AvatarJointUpgrade = Disabled. With the Avatar Joint Upgrade on (Roblox's default for new places),
  R15 characters and every rig built from a HumanoidDescription get an AnimationConstraint per joint instead of a
  Motor6D, and the procedural Animator's joint writes did not move the limbs in Studio (the player walked in the
  bind pose). The property lives on StarterPlayer, NOT Workspace (an earlier version of this script pinned
  "Workspace.AvatarJointUpgrade", which does not exist, so it did nothing). Its scripting security is
  RobloxScriptSecurity: no game script can read or set it at runtime. It is saved in the place file as
  StarterPlayer's AvatarJointUpgrade_SerializedRollout (Enum.RolloutState: 0 Default, 1 Disabled, 2 Enabled), so
  that is the token this script writes.
  The game also copes without it: the server rebuilds every upgraded rig's joints as Motor6Ds
  (Shared/RigJoints.EnsureMotors) and the client Animator checks its writes take effect and falls back to Roblox's
  own animation when they do not. But in a place of your own that you sync / paste this code into, set it by hand:
  Explorer > StarterPlayer > Properties > AvatarJointUpgrade = Disabled (README: "Using your own place").
"""
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "BecomeAWorldClassBoxer.rbxlx")
subprocess.check_call(["rojo", "build", "-o", out], cwd=ROOT)
with open(out, encoding="utf-8") as f:
    s = f.read()
changed = False

# the old, wrong pin (a Workspace property that does not exist) out of the file if an older build left it there
s2 = re.sub(r'\n\s*<token name="AvatarJointUpgrade">\d+</token>', "", s)
if s2 != s:
    s, changed = s2, True
    print("build_place: removed the stale Workspace AvatarJointUpgrade token")


def pin(cls, prop, value):
    """<token name=prop>value</token> in the first <Item class=cls>'s Properties (replaced when present)."""
    global s, changed
    m = re.search(r'(<Item class="%s"[^>]*>\s*<Properties>)' % cls, s)
    if not m:
        sys.exit("build_place: no %s item in %s" % (cls, out))
    end = s.find("</Properties>", m.end())
    block = s[m.end():end]
    tok = '<token name="%s">%d</token>' % (prop, value)
    if ('<token name="%s">' % prop) in block:
        nb = re.sub(r'<token name="%s">\d+</token>' % prop, tok, block)
        if nb != block:
            s = s[:m.end()] + nb + s[end:]
            changed = True
        print("build_place: %s.%s = %d (already present)" % (cls, prop, value))
    else:
        s = s[:m.end()] + "\n\t\t\t" + tok + s[m.end():]
        changed = True
        print("build_place: pinned %s.%s = %d" % (cls, prop, value))


pin("StarterPlayer", "AvatarJointUpgrade_SerializedRollout", 1)  # Enum.RolloutState.Disabled

if changed:
    with open(out, "w", encoding="utf-8") as f:
        f.write(s)
