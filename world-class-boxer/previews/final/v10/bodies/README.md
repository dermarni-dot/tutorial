# Body frames (v13 bodies: same height per frame, the neck and shoulder roll)

The five `Config.BodyTypes` frames side by side as the game builds them (`Builder.Cosmetics` on the fake R15 rig:
the frame's own tier meshes, the classic head, the mesh trunks / gloves / boots), at rest, at the lowest and the
highest muscle tier. Left to right in the front / 3-4 views: Lean, Athletic, Muscular, Power Build, Heavyweight Build
(the back view mirrors the order; the side view has Heavyweight nearest the camera).

| | front | back | side | 3/4 |
|---|---|---|---|---|
| tier 1 (untrained) | `bodies_t1_front.jpg` | `bodies_t1_back.jpg` | `bodies_t1_side.jpg` | `bodies_t1_34.jpg` |
| tier 5 (elite) | `bodies_t5_front.jpg` | `bodies_t5_back.jpg` | `bodies_t5_side.jpg` | `bodies_t5_34.jpg` |

Silhouettes (black fills on white, front and side per frame, in the game's gear): `silhouettes_t1.png`, `silhouettes_t5.png`;
bare-body silhouettes: `bare_t<N>_silhouette.png`.

Bare-body sheets (no gear, build_body.py's own stage, tiers 1 and 5, front / back / side / 3-4): `bare_t<N>_<view>.png`.
Right-arm close-ups, every frame on its UpperTorso: `arms_t1.png`, `arms_t5.png`, two strips each: straight in a front 3/4
turned so the right arm faces the camera (the shoulder into the deltoid, the forearm's taper, the hand) and bent 110 deg
at the elbow seen from the side (the biceps / triceps profile, the elbow seam, the curled hand).

What differs per frame (tools/body/CONTRACT.md "Body frames"): the skeleton (Lean: longer shins and forearms on a
longer trunk, a narrow pelvis, slim hands; Power Build: shorter forearms and shins on thick limbs, a wide deep pelvis,
big hands; Heavyweight: the widest pelvis and feet; the pivots are the frame's own, `frames[id].unit`), the arm axis
(where the upper arm rests against the frame's ribcage: the shoulder pivots are 2.22 studs apart on an untrained Lean
and 3.37 on an elite Power Build), the ribcage's width and depth, the trapezius slope into the neck (a neck column
under the head: Lean long and thin, Power Build short and thick, every one ending inside the head), the head (0.89
studs on the Lean .. 0.98 on the Heavyweight), the deltoid, trap, lat and forearm gains, the arm and calf girths, the
heavyweight's softer layer, and half of the description's Width / Depth. Under the trunks and at the wrists / ankles
every frame keeps the Athletic section, so the gear fitted on it still fits.

What does NOT differ (v13): the height. Every frame built at the same inches stands the same height, with the same
eye line and HipHeight (`Builder.Scales` normalises the HeightScale from the frame's own neck height and head;
`tools/sim/test_frameheight.luau`): `height_lineup_6ft.png` is the five frames at 72 in with a line through the crowns.
`heads_necks.png`: close-up strips of every frame's head on its neck column (height-normalised as the game builds it),
tier 1 front / side, tier 5 front / side: the neck's top inside the head's rounded base, the shoulder-to-trap roll, the
diagonal collarbones and SCM cords, Lean's long thin neck against Power / Heavyweight's short thick one into the traps.

How these were made:

```
/opt/bpyenv/bin/python tools/body/build_body.py --no-render          # all frames x tiers -> tools/body/out
/opt/bpyenv/bin/python tools/body/build_body.py --no-export --sheets frames --tiers 1,5   # bare_*, arms_*, heads_necks
                                                                     # (in the scratch body/ dir; copied here)
python3 tools/body/publish_body.py --local SCRATCH/BodyAssetData_local.lua
lune run tools/body/frames_anim.luau --out SCRATCH/framescene --tiers 1,5 --clips rest \
    --frames "Lean,Athletic,Muscular,Power Build,Heavyweight Build" --body SCRATCH/BodyAssetData_local.lua --nopen
/opt/bpyenv/bin/python tools/body/render_frames.py SCRATCH/framescene previews/final/v10/bodies --tiers 1,5 \
    --views front,back,side,34,silhouette
lune run tools/body/frames_anim.luau --out SCRATCH/framescene72 --tiers 3 --clips rest --height 72 --frames "..." --nopen
/opt/bpyenv/bin/python tools/body/render_frames.py SCRATCH/framescene72 previews/final/v10/bodies --tiers 3 \
    --headline height_lineup_6ft.png
```
