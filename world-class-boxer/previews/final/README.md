# Final character renders (visual judge, round 2)

These are offline renders of complete characters, as the game shows them when the mesh APIs are on. Each one combines the AnatomyBody, AnatomyHead and AnatomyHair meshes, including the gloves, boots, wraps and trunks pieces, on the athletic rig from Integration A. Everything came from the current working tree. Nothing in the repo was changed to make them.

## How they were made

- **Rig and meshes.** Every boxer was built with the real `Builder.CreateNPC` in a copy of the simulator, which builds the scaled R15 rig. The generators were run on the boxer's `LookData`, and the renderer is a copy of `render2` (three.js, studio lighting that approximates Roblox Future).
- **Poses.** All poses except "relaxed" come from the real client Animator. A lab copy that loads the current working tree ran each boxer through the steps below and recorded every R15 Motor6D `Transform` and the root offset at key moments:
  - fight stance with its style idle
  - the shell guard
  - jab, cross, lead hook and uppercut, each at contact
  - a knockdown or KO with the published `DownPose`
  - the `flex_biceps` and `flex_most` poses
- **Applying the poses.** The renderer replays those transforms on the same rig, so the poses match the game exactly.
- **Detail level.** Full detail, except `20_medium_detail.jpg`.
- **Cast.** There are 15 boxers covering:
  - every physique: BeginnerLean, LeanTechnical, Balanced, PowerPuncher, Heavyweight and EliteChampion
  - all five frames, skin tones 1 to 12, and 4 women
  - hair: taper, low, mid and high fades, afro, dreadlocks, cornrows, box braids, twists, ponytail, long straight hair, long curly hair, wolf cut, short curly and 360 waves
  - beards: stubble, goatee, chin strap, short boxed, full, moustache and Van Dyke

## Files

| File | What it shows |
|---|---|
| `01_cast_idle_stance.jpg` | All 15 boxers in their style's fight-stance idle (3/4 view) |
| `02_cast_cross.jpg` | All 15 at the moment the cross lands (side view) |
| `03_faces_front.jpg` | 15 faces, front |
| `04_faces_three_quarter.jpg` | 15 faces, 3/4 |
| `05_faces_profile.jpg` | 15 faces in profile (lip and nose projection, neck length) |
| `06_hair_back.jpg` | 15 heads from behind (fades, locs, braids, napes) |
| `07_macro_eyes_gloves_boots_mouths.jpg` | Close-ups of eyes, gloves, boots, and mouths/beards |
| `08_wraps_and_flex.jpg` | Wrapped hands (no gloves), and the double-biceps flex with wraps |
| `09_round1_fallback_cast.jpg` | The same 15 boxers in the round-1 part-built fallback (mesh APIs off) |
| `10_poses_balanced_highfade.jpg` | Idle, guard, jab, cross, hook, uppercut, KO face-first, two flexes and the fallback |
| `11_poses_power_afro.jpg` | Same pose sheet: Power Puncher, afro, short boxed beard (forward knockdown) |
| `12_poses_female_boxbraids.jpg` | Same pose sheet: female Elite Champion, box braids (backward knockdown) |
| `13_poses_heavyweight_dreads.jpg` | Same pose sheet: Heavyweight, dreadlocks, full beard (backward knockdown) |
| `14_closeups_elite_cornrows.jpg` | Face, 3/4, profile, back of head, torso front and back, gloves, boots |
| `15_closeups_long_curly.jpg` | Same close-up set: long curly hair and beard |
| `16_closeups_power_afro.jpg` | Same close-up set: afro and beard |
| `17_closeups_female_longhair.jpg` | Same close-up set: long straight hair, palest skin tone |
| `18_neck_interface_clay.jpg` | Untextured (clay) head mesh alone, then with the UpperTorso: the trapezius rises to the jaw, so almost no neck shows |
| `19_faces_clay.jpg` | 10 heads untextured (clay) at 3/4: geometry without paint |
| `20_medium_detail.jpg` | Four boxers at medium detail (what distant NPCs get) |

The judge's full defect list, with generator file and function and a fix for each, went back to the orchestrator. The main defects these images show:

- **Neck and boots:** the neck barely shows (the chin is only 0.1–0.26 studs above the deltoids), and the boots are about 22 % of body height (a real foot is about 15 %).
- **Gloves and trunks:** the gloves look like mittens or tubes, and the trunk legs look like inflated tubes.
- **Lips and eyes:** in profile the lips stick out past the nose. The eyeballs show as white triangles in profile.
- **Hair and beards:**
  - the afro is shaped like a mushroom or helmet
  - some locs stick out sideways at the shoulders
  - cornrows and 360 waves are painted stripes
  - beards look like solid slabs
- **Animation:** out-boxers stand on tiptoe at 40–58°, and the cross lands with the elbow still bent about 70° and the forearm angled upward.

Working files, which are not part of the repo, are in `/tmp/claude-0/vj/`:
- `cast.lua`: the cast
- `lab/scen_vj.lua`: the pose capture
- `render/specs/vj.lua` and `mk_layout.py`, `mk_show.py`: the sheet layouts
- `png/`: every full-size sheet
