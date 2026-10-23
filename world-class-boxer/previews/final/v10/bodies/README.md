# Body frames (v12 bodies)

The five `Config.BodyTypes` frames side by side as the game builds them (`Builder.Cosmetics` on the fake R15 rig:
the frame's own tier meshes, the classic head, the mesh trunks / gloves / boots), at rest, at the lowest and the
highest muscle tier. Left to right in the front / 3-4 views: Lean, Athletic, Muscular, Power Build, Heavyweight Build
(the back view mirrors the order; the side view has Heavyweight nearest the camera).

| | front | back | side | 3/4 |
|---|---|---|---|---|
| tier 1 (untrained) | `bodies_t1_front.jpg` | `bodies_t1_back.jpg` | `bodies_t1_side.jpg` | `bodies_t1_34.jpg` |
| tier 5 (elite) | `bodies_t5_front.jpg` | `bodies_t5_back.jpg` | `bodies_t5_side.jpg` | `bodies_t5_34.jpg` |

Bare-body sheets (no gear, build_body.py's own stage, tiers 1 and 5, front / back / side / 3-4): `bare_t<N>_<view>.png`.

What differs per frame (tools/body/CONTRACT.md "Body frames"): the arm axis (where the upper arm rests against the
frame's ribcage: the shoulder pivots are 2.22 studs apart on an untrained Lean and 3.37 on an elite Power Build), the
ribcage's width and depth, the trapezius slope into the neck (a neck column under the head: Lean long and thin, Power
Build short and as thick as the jaw), the deltoid, trap, lat and forearm gains, the arm and calf girths, the
heavyweight's softer layer, and the description's Width / Depth. Under the trunks and at the wrists / ankles every
frame keeps the Athletic section, so the gear fitted on it still fits.

How these were made:

```
/opt/bpyenv/bin/python tools/body/build_body.py --no-render          # all frames x tiers -> tools/body/out
python3 tools/body/publish_body.py --local SCRATCH/BodyAssetData_local.lua
lune run tools/body/frames_anim.luau --out SCRATCH/framescene --tiers 1,5 --clips rest \
    --frames "Lean,Athletic,Muscular,Power Build,Heavyweight Build" --body SCRATCH/BodyAssetData_local.lua --nopen
/opt/bpyenv/bin/python tools/body/render_frames.py SCRATCH/framescene previews/final/v10/bodies --tiers 1,5
```
