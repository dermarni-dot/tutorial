# Skin surface maps (v16)

The body parts with their SurfaceAppearance maps (normal, AO / cavity ColorMap tinted to the skin, roughness), rendered
in Cycles the way Roblox applies them, against the current build without maps (tools/body/bake_skin.py; CONTRACT.md
"Skin surface maps (v16)").

| file | what |
|---|---|
| `<chest_front, back_back, arms_side, arms_back, legs_front, legs_back>_t5_<before, after>.png` | Lean / Muscular / Power Build tier 5 close-ups, no maps / maps |
| `lineup_t<1,3,5>_<front, back>_<before, after>.png` | the five frames whole at game distance |

Not shown here and to check in Studio: the engine's own lighting response (Future lighting, the arena lights), the
tint on dark and light skin tones, mip-mapped distance views, the left limbs (mirrored, tangent sign).
