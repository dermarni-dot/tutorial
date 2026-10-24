# Muscle definition pass (v14)

Geometry only (no texture on the body parts); see tools/body/CONTRACT.md "Muscle definition (v14)".

| sheet | what |
|---|---|
| `compare_chest_t5.png` | chest + delts front, Lean / Muscular / Power Build tier 5, before (top) over after |
| `compare_back_t5.png` | back, before / after |
| `compare_arms_t5.png` | right arm, outer side (before / after) then back (before / after) |
| `compare_legs_t5.png` | legs front (before / after) then back (before / after) |
| `tiers_<chest,back,arms,legs>.png` | the after set at tiers 1 / 3 / 5: definition grows with the tier |
| `bodies_t<1,3,5>_<front,back,34>.jpg` | the five frames as the game builds them (gear on), game distance |
| `bare_t<1,5>_<front,back,34>.png` | the five frames bare (build_body.py's stage) |

Made with `build_body.py --sheets muscles --tiers 1,3,5 --frames lean,muscular,power --muscle-tag before|after`
(before = the v13 code), `compose_muscles()`, `frames_anim.luau --tiers 1,3,5` + `render_frames.py`.
