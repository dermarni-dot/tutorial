# Final character renders (visual judge, round 2)

These are offline renders of complete characters, as the game shows them when the mesh APIs are on. Each one combines the AnatomyBody, AnatomyHead and AnatomyHair meshes, including the gloves, boots, wraps and trunks pieces, on the athletic rig from Integration A. Everything came from the current working tree. Nothing in the repo was changed to make them.

Every sheet was re-rendered after the neck lift (see [Neck lift](#neck-lift) at the end), so all of them show the current neck and punches. The sections in between record what each earlier pass changed.

The folder also holds every other pass's previews: animation filmstrips, the review renders of bodies, hair, the interface and the world, the character creator, the training screens, lighting, and the Graphics level comparisons of the optimization pass. [Every image in this folder](#every-image-in-this-folder) at the end lists all of them, one row per file.

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
| `18_neck_interface_clay.jpg` | Untextured (clay) head mesh alone, then with the UpperTorso: the head's own neck runs down to the Neck pivot, and with the torso a neck shows between the jaw and the trapezius |
| `19_faces_clay.jpg` | 10 heads untextured (clay) at 3/4: geometry without paint |
| `20_medium_detail.jpg` | Four boxers at medium detail (what distant NPCs get) |
| `21_neck_lift.jpg` | The neck before (HEAD `acbf9b9`) and after the lift, front and profile, for four men and two women. Then, after the lift only: the shell guard from the side, clay without hair, and the part-built fallback before and after |
| `22_mouths_beards_eyes.jpg` | Polish pass on the head: mouths and beards at 3/4, and eye macros |
| `23_cast_lead_hook.jpg` | All 15 at the moment the lead hook lands, seen from above: the fist swings round the body into the side of the jaw with the elbow bent (game polish pass) |

The judge's full defect list, with generator file and function and a fix for each, went back to the orchestrator. The main defects in the judge's first set of these images were the following. Later passes worked on each of them; the sections below describe how.

- **Neck and boots:** the neck barely showed (the chin was only 0.1–0.26 studs above the deltoids), and the boots were about 22 % of body height (a real foot is about 15 %).
- **Gloves and trunks:** the gloves looked like mittens or tubes, and the trunk legs looked like inflated tubes.
- **Lips and eyes:** in profile the lips stuck out past the nose. The eyeballs showed as white triangles in profile.
- **Hair and beards:**
  - the afro was shaped like a mushroom or helmet
  - some locs stuck out sideways at the shoulders
  - cornrows and 360 waves were painted stripes
  - beards looked like solid slabs
- **Animation:** out-boxers stood on tiptoe at 40–58°, and the cross landed with the elbow still bent about 70° and the forearm angled upward. The game polish pass fixed both, and the lead hook now swings round instead of pushing forward. `01`, `02`, `10`–`13` and `23` were re-rendered after that pass, with poses from the current Animator: stance feet at about 15–30°, jab and cross with the elbow 157–168° open at contact, and the forearm level within 15° unless a much shorter boxer is punching up at a taller one's chin.

Working files, which are not part of the repo, are in `/tmp/claude-0/vj/`:
- `cast.lua`: the cast
- `lab/scen_vj.lua`: the pose capture
- `render/specs/vj.lua` and `mk_layout.py`, `mk_show.py`: the sheet layouts
- `png/`: every full-size sheet

## Body polish re-render

`01`, `07`, `08`, `14`–`17` and `20` were re-rendered from the working tree after the body polish pass, with the same layouts and the same renderer. They now show:

- **Boots and trainers:** about 15.5 % of standing height, with rounded toe boxes and a thicker sole that has a darker side wall. Criss-cross laces run between eyelet rows on a raised tongue, from the boot shaft down onto the instep.
- **Gloves:** a padded fist that is widest at two thirds of its length, curls into a domed knuckle pad and has a thick attached thumb. Lace-up cuffs have the same criss-cross lacing as the boots.
- **Trunks:** slimmer A-line legs, and a seat that runs straight into them with no shelf.
- **Sports top:** a scoop neckline, a racer back and knit ribbing.
- **Hand wraps:** layered turns over the knuckles, between the fingers and round the thumb.
- **Medium detail:** trim bands have crisp edges.

At that point the other sheets were unchanged from the judge's set.

## Head polish pass

`03`, `04`, `05`, `19` and `22` were re-rendered after the head polish pass, in the relaxed pose, at full detail, from the working tree.

| Area | Change |
|---|---|
| Lips | They sit behind the line from nose tip to chin, have a rounded vermilion, turn back into the corners, and the mouth is narrower |
| Face shapes | Women: V-shaped faces over a slimmer neck. Men: stronger jaw and face-length variation, with a crisper jaw-to-neck angle |
| Eyes | Set deeper, with a tighter lateral canthus; the whites are shaded toward the outer corner and on dark skin |
| Beards | They stop under the jaw, the cheek line is feathered, the hair is clumped with lighter tips, and the chin strap is a band rather than a line |
| Pale skin | Warmer, with more flush |
| Nape | The tone runs as a gradient down the nape |

The longer neck needed the Builder and Body requests in `PF-head.md`. The final regression pass held them back because the animation lab's punch gates failed with them. They are now applied, with the punch retune; see [Neck lift](#neck-lift).

## Hair polish pass

`03`–`06`, `13`–`17` and `19` were re-rendered from the working tree after the hair polish pass, with the same layouts and renderer (relaxed pose for the face and hair sheets, the lab poses for `13`).

| Style | Change |
|---|---|
| Afro | An egg-shaped mass made of 8–12 broad cluster lobes plus a strong wobble. It rounds down into the scalp over the ears and at the nape, with no brim or shelf. The valleys and underside are darker, the surface is matte, and about 220 coil clusters sit mostly on the silhouette |
| Locs | Locs that land on the body slide down along it and drop behind (or in front of) the shoulder. They never stick out sideways. Each loc is lumpier, with a slow swell and pinch along its length and a matte frizz texture. HairFX uses the same rule at runtime |
| Cornrows | The rows run in parallel from the hairline to the nape and end in tapered ends tucked into the scalp, with no star at the back. Each braid has a raised plait: stitches that alternate sides, with grooves between them. Between the rows the scalp is the head's own skin tone with a fine stipple of new growth and thin, clean partings |
| Box braids | Each section is skin-toned with a soft stipple. There are no dark squares at the roots |
| Short cuts and fades | A parting is drawn only when the look has one, as a narrow, shadowed gap. Short tufts in the hair's own tone and some thickness noise give the top relief and a broken outline. Curly tops are dense, packed curl clusters |
| Long hair | Narrow locks in three length layers taper to fine tips. A shadowed inner layer sits behind the gaps, cheek strands are tucked behind the ears, and fine strands run over the front and top |
| Long curly | Fewer, fuller ringlets. The side sheet is split into crimped locks with a lighter inner face, and it rises out from under the cap, so there is no straight seam |
| Ponytail | A longer, fuller tail. The hair pulled back to it lies flush with softer streaks |
| 360 waves | Ripples spiral out from the crown, with S-curved crests broken into sections and a coily stipple. These replace the old concentric bands |
| Dyes | A light dye keeps the strand texture under it, with stretched contrast instead of a flat colour |

## Neck lift

The neck fix from `PF-head.md` (requests 1 and 2) is now in the tree, together with the punch retune it needed. All 23 sheets were re-rendered after it, with the same layouts and renderer. The poses were captured again with the current Animator, in a lab copy that loads the working tree. Only `21` has a new layout.

- **What changed.** The Builder lowers the Neck pivot below the head by 0.26 of the head's height for men and 0.22 for women. The head rides higher on the same torso, and its own mesh neck runs from the jaw down into the torso's neck column. The part-built fallback's neck cylinder and neck muscles grow by the same amount.
- **Measured on the 15 boxers (relaxed pose).** The chin is the lowest point of the jaw's front. A head height is measured from crown to chin.

| Measure | Men (11) | Women (4) |
|---|---|---|
| How much higher the head sits | 0.24–0.25 studs (0.26 of the Head part's height) | 0.20 studs (0.22) |
| Chin above the deltoid tops, before (HEAD `acbf9b9`) | 0.18–0.24 studs (0.20–0.27 head heights) | 0.23–0.27 studs (0.27–0.33) |
| Chin above the deltoid tops, after | 0.43–0.48 studs (0.47–0.54 head heights) | 0.43–0.48 studs (0.50–0.57) |

- **Punches in these captures.** The cross lands with the elbow 159–165° open (139–165° in the captures before the game polish pass). Every boxer punches at the same Balanced sparring partner, whose chin is now higher. At contact the forearm rises 6–39° for the men and 28–57° for the women (3–30° and 19–46° on HEAD `acbf9b9`). The lab's forearm-pitch gate only measures men attacking a Balanced man. Two extra lab sweeps cover women: a man attacking a woman, and women attacking a man. They are reported against HEAD rather than gated, because the smallest women cannot reach a Balanced man's chin with every punch from the AI's ranges. See [Review fixes](#review-fixes).
- **Still visible.** The neck is a plain column. The trapezius does not slope up into it, so from behind and at 3/4 it can look like a pipe standing on the shoulders (`06`, `16`). Women's necks can look a little long in profile (`05`).

Working files, which are not part of the repo, are in `/tmp/claude-0/-home-user-tutorial/bf954517-c876-52e6-b6c7-def672e29548/scratchpad/neck/`:
- `rb.sh`, `sheet.sh` and `render/specs/vjp.lua`: render batches for chosen poses
- `mk21.py` and `asm.py`: the layout and title bars of `21`
- `flab/lab/out/vj_*.joints.json`: the pose captures
- `chin.py`: the chin measurement

## Review fixes

The review of the neck lift found four problems in the game and one in this file. `02`, `10`–`13` and `23` were re-rendered after the fixes, with poses captured again from the current Animator and the same layouts and renderer. The other sheets do not show punches or knockdowns, so they are unchanged.

- **Knocked-out heads.** A boxer lying flat on his back or face now lets his head down onto the canvas. `AnimDown` bends the neck until the head rests on the canvas, but never down onto an arm lying under it. The bend is blended in as the chest settles, so it does not pop. In the pose captures, the head centre's height above the lowest body part in the five lying knockdowns went from 0.40–0.54 studs to 0.04–0.17 (0.33–0.39 on HEAD). In the face-first KO (`10`) it went from 0.54 to 0.17, and the face is on the canvas again.
- **Women attacking men.** Women attacking a man are now in the lab. The punches step in and rise only as far as the stance legs allow. Before, a planned rise or lunge the planted legs could not follow sank the pelvis and the fist landed short. The lead foot now steps in for a long lunge even when it is still landing from the last step. The rear foot shuffles in after a lunge it cannot stretch to. A straight to a chin out of reach steps in further, up to 0.85 studs. With women 5, 6, 7 and 14 attacking the Balanced man (200 punches), 31 punches fail a gate, against 30 on HEAD and 41 before these fixes. The remaining failures are reach: the smallest women's overhands and uppercuts at a chin up to 2.8 studs above the shoulder. One is a guard glove touching the face.
- **Men attacking women.** The lead hook's sweep is back to 0.9 (0.95 before the fix). That stops the shoulder spinning at 38 rad/s as the arm comes home after a hook to a shorter woman. A long straight's arm drive now starts from rest smoothly, with no fist pop. Against a woman, 5 punches fail a gate (6 on HEAD), and none is a joint-speed or pop failure that HEAD does not also have.
- **Headgear.** The chin strap used to run straight across under the head. With the longer neck it showed as a dark bar across the throat. It now runs from each cheek pad along the jaw to a cup under the chin.

Working files for the review fixes, which are not part of the repo, are in `/tmp/claude-0/-home-user-tutorial/bf954517-c876-52e6-b6c7-def672e29548/scratchpad/neck2/`:
- `lab/`: the animation lab with the female sweeps (`gates/pF_sweep.py`, `gates/pvj_sweep.py`) and the head-on-the-canvas gate
- `vlab/lab/out/vj_*.joints.json`: the pose captures
- `vrb.sh`, `vsheet.sh` and `vlay/`: render batches and layouts
- `hg.sh`: the headgear renders

## Graphics levels

The optimization pass made every client system follow one Graphics level (Settings > Graphics detail: Auto, High, Medium, Low; see Performance in the main README). The `perf_*` images compare the levels:

- **Characters** (`perf_characters_low_vs_high.jpg`, the character renderer): your boxer and your opponent keep full detail and every colour texture at every level. Gym NPCs on Low are low-detail meshes; before the pass they had no colour textures at all, which took the beard and brows off every face, so Low now paints the face texture on them.
- **Scenes** (`perf_gym_levels.jpg`, `perf_stadium_levels.jpg`, `perf_city_night_levels.jpg`, simulator scene renders): High after the pass looks like High before it; Low drops shadows, spot-ray rate, crowd density and window grids.
- **Interface** (`perf_fight_hud_low_vs_high.jpg`, `perf_fight_hud_phone_low_vs_high.jpg`, `perf_settings_graphics_note.jpg`, offline GUI renders): the HUD is the same at every level, and the Settings note says what each level does.

## Type switch (v9/type)

`v9/type/`: the face change, before / after. The game's type is `src/shared/Typography.lua`: Bangers (a poster
display face) for titles, buttons, call-outs and every sign in the world, Oswald Bold kept for the numbers that
line up in columns (stats, clocks, records, money), Montserrat Medium / Bold for body copy and labels, RobotoMono
for readouts. `ui_<screen>_<device>_before|after.jpg` are mock renders of the simulator's layout dumps
(`tools/ui/render_mock.py`, drawn with the real TTFs in `tools/ui/fonts`): the title menu, the Career Hub and its
tournaments page, the fight HUD mid-round, a result, the creator, the gym HUD with a store prompt, the debut offer,
at desktop and phone size. `world_<view>_before|after.jpg` are Cycles renders of the world dump
(`tools/sim/world_scene.luau` + `world_render.py`): the gym's front banner, Main Street's shop fronts by day, the
street by day and by night, and the Grand Arena. Fonts only render for real in Studio; these approximate them.

## Every image in this folder

### Graphics levels (optimization pass)

Offline GUI and scene renders from the simulator, plus the character renderer. GPU effects (shadows, bloom, depth of field) are approximated.

| File | Shows |
|---|---|
| `perf_characters_low_vs_high.jpg` | Mesh characters by Graphics level: High (full detail, every texture: your boxer and your opponent at every level), an NPC on Low before the optimization pass (low detail, no textures: no beard, no brows) and on Low now (low detail with the face texture) |
| `perf_city_night_levels.jpg` | Main Street at night: before (High), after at High, after at Low (thinner crowd, fewer window grids) |
| `perf_fight_hud_low_vs_high.jpg` | The fight HUD at Low and High on a desktop: identical (Low drops effects, never information) |
| `perf_fight_hud_phone_low_vs_high.jpg` | The same on a phone, with the touch pads |
| `perf_gym_levels.jpg` | The tier-4 gym floor: before the optimization pass (High), after at High, after at Low |
| `perf_settings_graphics_note.jpg` | The Settings Graphics note at Low, Medium, High, Auto and Auto on a frame-rate-capped device |
| `perf_stadium_levels.jpg` | The National Stadium in a round: before (High), after at High, after at Low (one key-light shadow, slower spot rays, printed impostor rows) |

### Animation

Filmstrips from the animation lab (the real client Animator on lab rigs or the mesh bodies).

| File | Shows |
|---|---|
| `anim_footwork_OutBoxer_after.jpg` | Ring footwork filmstrip, OutBoxer style, after the animation pass |
| `anim_footwork_OutBoxer_before.jpg` | Ring footwork filmstrip, OutBoxer style, before the animation pass |
| `anim_footwork_Slugger_after.jpg` | Ring footwork filmstrip, Slugger style, after the animation pass |
| `anim_footwork_Slugger_before.jpg` | Ring footwork filmstrip, Slugger style, before the animation pass |
| `anim_footwork_Swarmer_after.jpg` | Ring footwork filmstrip, Swarmer style, after the animation pass |
| `anim_footwork_Swarmer_before.jpg` | Ring footwork filmstrip, Swarmer style, before the animation pass |
| `anim_knockdowns_after.jpg` | Knockdown filmstrips: flash, forward, side, ropes, corner and their get-ups |
| `anim_knockouts_after.jpg` | Knockout filmstrips: timber fall, delayed KO, referee catch, face-first and backward collapses |
| `anim_punches_BoxerPuncher_after.jpg` | Punch filmstrips (BoxerPuncher), after the kinetic-chain punches |
| `anim_punches_BoxerPuncher_before.jpg` | Punch filmstrips (BoxerPuncher), before the kinetic-chain punches |
| `anim_reactions_after.jpg` | Hit reactions by tier (light, medium, heavy, critical), after the animation pass |
| `anim_reactions_before.jpg` | Hit reactions by tier (light, medium, heavy, critical), before the animation pass |
| `anim_specials_a_after.jpg` | Special moves, sheet A |
| `anim_specials_b_after.jpg` | Special moves, sheet B |
| `anim_walk_after_female_34.jpg` | Walking overhaul, after: the female lab rig, 3/4 view |
| `anim_walk_after_female_side.jpg` | Walking overhaul, after: the female lab rig, side view |
| `anim_walk_after_heavy_34.jpg` | Walking overhaul, after: the heavy lab rig, 3/4 view |
| `anim_walk_after_heavy_side.jpg` | Walking overhaul, after: the heavy lab rig, side view |
| `anim_walk_after_lean_34.jpg` | Walking overhaul, after: the lean lab rig, 3/4 view |
| `anim_walk_after_lean_side.jpg` | Walking overhaul, after: the lean lab rig, side view |
| `anim_walk_after_mesh_female_front.jpg` | Walking overhaul, after: the female mesh body from the front (walk, jog, run, sprint, starts, stops, turns) |
| `anim_walk_after_mesh_female_side.jpg` | Walking overhaul, after: the female mesh body from the side (walk, jog, run, sprint, starts, stops, turns) |
| `anim_walk_after_mesh_heavy_front.jpg` | Walking overhaul, after: the heavy mesh body from the front (walk, jog, run, sprint, starts, stops, turns) |
| `anim_walk_after_mesh_heavy_side.jpg` | Walking overhaul, after: the heavy mesh body from the side (walk, jog, run, sprint, starts, stops, turns) |
| `anim_walk_after_mesh_lean_front.jpg` | Walking overhaul, after: the lean mesh body from the front (walk, jog, run, sprint, starts, stops, turns) |
| `anim_walk_after_mesh_lean_side.jpg` | Walking overhaul, after: the lean mesh body from the side (walk, jog, run, sprint, starts, stops, turns) |
| `anim_walk_before_female_34.jpg` | Walking overhaul, before: the female lab rig, 3/4 view |
| `anim_walk_before_female_side.jpg` | Walking overhaul, before: the female lab rig, side view |
| `anim_walk_before_heavy_34.jpg` | Walking overhaul, before: the heavy lab rig, 3/4 view |
| `anim_walk_before_heavy_side.jpg` | Walking overhaul, before: the heavy lab rig, side view |
| `anim_walk_before_lean_34.jpg` | Walking overhaul, before: the lean lab rig, 3/4 view |
| `anim_walk_before_lean_side.jpg` | Walking overhaul, before: the lean lab rig, side view |
| `anim_walk_before_mesh_female_front.jpg` | Walking overhaul, before: the female mesh body from the front (walk, jog, run, sprint, starts, stops, turns) |
| `anim_walk_before_mesh_female_side.jpg` | Walking overhaul, before: the female mesh body from the side (walk, jog, run, sprint, starts, stops, turns) |
| `anim_walk_before_mesh_heavy_front.jpg` | Walking overhaul, before: the heavy mesh body from the front (walk, jog, run, sprint, starts, stops, turns) |
| `anim_walk_before_mesh_heavy_side.jpg` | Walking overhaul, before: the heavy mesh body from the side (walk, jog, run, sprint, starts, stops, turns) |
| `anim_walk_before_mesh_lean_front.jpg` | Walking overhaul, before: the lean mesh body from the front (walk, jog, run, sprint, starts, stops, turns) |
| `anim_walk_before_mesh_lean_side.jpg` | Walking overhaul, before: the lean mesh body from the side (walk, jog, run, sprint, starts, stops, turns) |
| `anim_walker_after.jpg` | A background walker's gait, after the gait-life pass |
| `anim_walker_before.jpg` | A background walker's gait, before the gait-life pass |

### Characters: faces, fallback, gloves

| File | Shows |
|---|---|
| `face_after.jpg` | Faces, after the faces / skin pass |
| `face_before.jpg` | Faces, before the faces / skin pass |
| `face_gear_after.jpg` | Faces with headgear and gear, after the faces / skin pass |
| `face_gear_before.jpg` | Faces with headgear and gear, before the faces / skin pass |
| `fallback_after.jpg` | The part-built fallback, after its softer pass |
| `fallback_before.jpg` | The part-built fallback, before its softer pass |
| `fallback_body_beginner.jpg` | The part-built fallback body, beginner physique (smooth, integrated muscle domes) |
| `fallback_body_elite.jpg` | The part-built fallback body, elite physique (smooth, integrated muscle domes) |
| `fallback_body_female.jpg` | The part-built fallback body, female physique (smooth, integrated muscle domes) |
| `fallback_body_heavyweight.jpg` | The part-built fallback body, heavyweight physique (smooth, integrated muscle domes) |
| `fallback_body_lean.jpg` | The part-built fallback body, lean physique (smooth, integrated muscle domes) |
| `fallback_body_power.jpg` | The part-built fallback body, power physique (smooth, integrated muscle domes) |
| `gloves_closeup_mesh.jpg` | Mesh gloves close up |
| `gloves_fallback_parts.jpg` | Part-built gloves |
| `gloves_guard_punch_comp.jpg` | Gloves in the guard and at a punch |

### Body review renders

| File | Shows |
|---|---|
| `council_body_beginner.jpg` | Body review render: beginner physique |
| `council_body_elite.jpg` | Body review render: elite physique |
| `council_body_female_lean.jpg` | Body review render: female lean physique |
| `council_body_heavy.jpg` | Body review render: heavy physique |
| `council_body_lean.jpg` | Body review render: lean physique |
| `council_body_power.jpg` | Body review render: power physique |
| `council_body_satin_waist.jpg` | Trunks: the satin under the seat with the waist bent (before / after) |
| `council_body_trunks.jpg` | Trunks as one garment |
| `council_body_trunks_hipcap.jpg` | Trunks seat at the hip cap |
| `council_body_trunks_posed.jpg` | Trunks in posed sits, kneels and strides |
| `council_body_trunks_sit.jpg` | Trunks seat in a sit |

### Hair review renders

Suffixes: `_f` / `_m` female / male, `_k` / `_s` kinky / straight hair type.

| File | Shows |
|---|---|
| `council_hair_afro_k.jpg` | Hair review round 1: afro kinky hair |
| `council_hair_afro_k_close.jpg` | Hair review round 1: afro kinky hair, close up |
| `council_hair_blue_split.jpg` | Hair review round 1: blue split dye |
| `council_hair_boxbraids_f.jpg` | Hair review round 1: box braids female |
| `council_hair_braids.jpg` | Hair review round 1: braids |
| `council_hair_braids_close.jpg` | Hair review round 1: braids, close up |
| `council_hair_cornrows.jpg` | Hair review round 1: cornrows |
| `council_hair_cornrows_close.jpg` | Hair review round 1: cornrows, close up |
| `council_hair_curlytop.jpg` | Hair review round 1: curly top |
| `council_hair_dreads.jpg` | Hair review round 1: dreadlocks |
| `council_hair_dreads_close.jpg` | Hair review round 1: dreadlocks, close up |
| `council_hair_fade_k.jpg` | Hair review round 1: fade kinky hair |
| `council_hair_fade_k_close.jpg` | Hair review round 1: fade kinky hair, close up |
| `council_hair_fade_s.jpg` | Hair review round 1: fade straight hair |
| `council_hair_long_f.jpg` | Hair review round 1: long hair female |
| `council_hair_longcurly_f.jpg` | Hair review round 1: long curly female |
| `council_hair_longcurly_m.jpg` | Hair review round 1: long curly male |
| `council_hair_longcurly_m_close.jpg` | Hair review round 1: long curly male, close up |
| `council_hair_mohawk.jpg` | Hair review round 1: mohawk |
| `council_hair_pony_f.jpg` | Hair review round 1: ponytail female |
| `council_hair_r2_blue_split.jpg` | Hair review round 2: blue split dye |
| `council_hair_r2_boxbraids_f.jpg` | Hair review round 2: box braids female |
| `council_hair_r2_boxbraids_f_close.jpg` | Hair review round 2: box braids female, close up |
| `council_hair_r2_boxbraids_m_close.jpg` | Hair review round 2: box braids male, close up |
| `council_hair_r2_buzz_s_close.jpg` | Hair review round 2: buzz cut straight hair, close up |
| `council_hair_r2_fade_k_close.jpg` | Hair review round 2: fade kinky hair, close up |
| `council_hair_r2_long_f.jpg` | Hair review round 2: long hair female |
| `council_hair_r2_long_s_m.jpg` | Hair review round 2: long hair straight hair male |
| `council_hair_r2_longcurly_k.jpg` | Hair review round 2: long curly kinky hair |
| `council_hair_r2_longcurly_m.jpg` | Hair review round 2: long curly male |
| `council_hair_r2_longcurly_m_close.jpg` | Hair review round 2: long curly male, close up |
| `council_hair_r2_volume_edges.jpg` | Hair review round 2: volume edges |
| `council_hair_r3_blue_split_low.jpg` | Hair review round 3: blue split dye (low detail) |
| `council_hair_r3_boxbraids_f.jpg` | Hair review round 3: box braids female |
| `council_hair_r3_boxbraids_f_low.jpg` | Hair review round 3: box braids female (low detail) |
| `council_hair_r3_boxbraids_m.jpg` | Hair review round 3: box braids male |
| `council_hair_r3_boxbraids_m_low.jpg` | Hair review round 3: box braids male (low detail) |
| `council_hair_r3_boxbraids_m_medium.jpg` | Hair review round 3: box braids male (medium detail) |
| `council_hair_r3_long_f_low.jpg` | Hair review round 3: long hair female (low detail) |
| `council_hair_r3_long_s_m_low.jpg` | Hair review round 3: long hair straight hair male (low detail) |
| `council_hair_r3_longcurly_k.jpg` | Hair review round 3: long curly kinky hair |
| `council_hair_r3_longcurly_m.jpg` | Hair review round 3: long curly male |
| `council_hair_r3_longcurly_m_medium.jpg` | Hair review round 3: long curly male (medium detail) |
| `council_hair_r3_longcurly_m_under.jpg` | Hair review round 3: long curly male from below |
| `council_hair_r3_part_crew.jpg` | Hair review round 3: parting: crew cut |
| `council_hair_r3_part_fade_k.jpg` | Hair review round 3: parting: fade kinky hair |
| `council_hair_r4_boxbraids_low.jpg` | Hair review round 4: box braids (low detail) |
| `council_hair_shortcurly.jpg` | Hair review round 1: short curly |
| `council_hair_shortdreads.jpg` | Hair review round 1: short dreads |
| `council_hair_twists.jpg` | Hair review round 1: twists |
| `council_hair_waves.jpg` | Hair review round 1: 360 waves |

### Interface review renders

| File | Shows |
|---|---|
| `council_ui_after_1024_barber.jpg` | UI review pass 1, after: barber on a 1024 x 768 tablet |
| `council_ui_after_1024_creator.jpg` | UI review pass 1, after: creator on a 1024 x 768 tablet |
| `council_ui_after_1024_hub.jpg` | UI review pass 1, after: Career Hub on a 1024 x 768 tablet |
| `council_ui_after_1920_career.jpg` | UI review pass 1, after: career on a 1920 x 1080 desktop |
| `council_ui_after_1920_creator.jpg` | UI review pass 1, after: creator on a 1920 x 1080 desktop |
| `council_ui_after_667_career.jpg` | UI review pass 1, after: career on a 667 x 375 phone |
| `council_ui_after_667_creator.jpg` | UI review pass 1, after: creator on a 667 x 375 phone |
| `council_ui_after_667_hub.jpg` | UI review pass 1, after: Career Hub on a 667 x 375 phone |
| `council_ui_after_844_barber.jpg` | UI review pass 1, after: barber on an 844 x 390 phone |
| `council_ui_after_844_creator.jpg` | UI review pass 1, after: creator on an 844 x 390 phone |
| `council_ui_after_844_settings.jpg` | UI review pass 1, after: settings on an 844 x 390 phone |
| `council_ui_before_1024_barber.jpg` | UI review pass 1, before: barber on a 1024 x 768 tablet |
| `council_ui_before_1024_creator.jpg` | UI review pass 1, before: creator on a 1024 x 768 tablet |
| `council_ui_before_1024_hub.jpg` | UI review pass 1, before: Career Hub on a 1024 x 768 tablet |
| `council_ui_before_1920_career.jpg` | UI review pass 1, before: career on a 1920 x 1080 desktop |
| `council_ui_before_1920_creator.jpg` | UI review pass 1, before: creator on a 1920 x 1080 desktop |
| `council_ui_before_667_career.jpg` | UI review pass 1, before: career on a 667 x 375 phone |
| `council_ui_before_667_creator.jpg` | UI review pass 1, before: creator on a 667 x 375 phone |
| `council_ui_before_667_hub.jpg` | UI review pass 1, before: Career Hub on a 667 x 375 phone |
| `council_ui_before_844_barber.jpg` | UI review pass 1, before: barber on an 844 x 390 phone |
| `council_ui_before_844_creator.jpg` | UI review pass 1, before: creator on an 844 x 390 phone |
| `council_ui_before_844_settings.jpg` | UI review pass 1, before: settings on an 844 x 390 phone |
| `council_ui_pass2_after_1024_career.jpg` | UI review pass 2, after: career on a 1024 x 768 tablet |
| `council_ui_pass2_after_1024_face.jpg` | UI review pass 2, after: creator face step on a 1024 x 768 tablet |
| `council_ui_pass2_after_667_creator.jpg` | UI review pass 2, after: creator on a 667 x 375 phone |
| `council_ui_pass2_after_667_locker.jpg` | UI review pass 2, after: locker room on a 667 x 375 phone |
| `council_ui_pass2_after_667_sliders.jpg` | UI review pass 2, after: sliders on a 667 x 375 phone |
| `council_ui_pass2_after_667_stepmenu.jpg` | UI review pass 2, after: step menu on a 667 x 375 phone |
| `council_ui_pass2_after_844_barber.jpg` | UI review pass 2, after: barber on an 844 x 390 phone |
| `council_ui_pass2_after_844_face.jpg` | UI review pass 2, after: creator face step on an 844 x 390 phone |
| `council_ui_pass2_after_844_settings.jpg` | UI review pass 2, after: settings on an 844 x 390 phone |
| `council_ui_pass2_before_1024_career.jpg` | UI review pass 2, before: career on a 1024 x 768 tablet |
| `council_ui_pass2_before_1024_face.jpg` | UI review pass 2, before: creator face step on a 1024 x 768 tablet |
| `council_ui_pass2_before_667_creator.jpg` | UI review pass 2, before: creator on a 667 x 375 phone |
| `council_ui_pass2_before_667_locker.jpg` | UI review pass 2, before: locker room on a 667 x 375 phone |
| `council_ui_pass2_before_667_sliders.jpg` | UI review pass 2, before: sliders on a 667 x 375 phone |
| `council_ui_pass2_before_844_barber.jpg` | UI review pass 2, before: barber on an 844 x 390 phone |
| `council_ui_pass2_before_844_face.jpg` | UI review pass 2, before: creator face step on an 844 x 390 phone |
| `council_ui_pass2_before_844_settings.jpg` | UI review pass 2, before: settings on an 844 x 390 phone |
| `council_ui_pass3_after_1024_career.jpg` | UI review pass 3, after: career on a 1024 x 768 tablet |
| `council_ui_pass3_after_1024_career_longest.jpg` | UI review pass 3, after: career (longest names) on a 1024 x 768 tablet |
| `council_ui_pass3_after_667_hair.jpg` | UI review pass 3, after: creator hair step on a 667 x 375 phone |
| `council_ui_pass3_after_844_barber.jpg` | UI review pass 3, after: barber on an 844 x 390 phone |
| `council_ui_pass3_after_844_stepmenu_pad.jpg` | UI review pass 3, after: step menu gamepad on an 844 x 390 phone |
| `council_ui_pass3_before_1024_career.jpg` | UI review pass 3, before: career on a 1024 x 768 tablet |
| `council_ui_pass3_before_667_hair.jpg` | UI review pass 3, before: creator hair step on a 667 x 375 phone |
| `council_ui_pass3_before_844_barber.jpg` | UI review pass 3, before: barber on an 844 x 390 phone |
| `council_ui_pass3_before_844_stepmenu_pad.jpg` | UI review pass 3, before: step menu gamepad on an 844 x 390 phone |
| `council_ui_pass4_after_1024_dock.jpg` | UI review pass 4, after: creator dock on a 1024 x 768 tablet |
| `council_ui_pass4_after_667_kb_dock.jpg` | UI review pass 4, after: keyboard creator dock on a 667 x 375 phone |
| `council_ui_pass4_after_667_pad_camhint.jpg` | UI review pass 4, after: gamepad camera hint on a 667 x 375 phone |
| `council_ui_pass4_after_844_pad_camhint.jpg` | UI review pass 4, after: gamepad camera hint on an 844 x 390 phone |
| `council_ui_pass4_before_1024_dock.jpg` | UI review pass 4, before: creator dock on a 1024 x 768 tablet |
| `council_ui_pass4_before_667_pad_camhint.jpg` | UI review pass 4, before: gamepad camera hint on a 667 x 375 phone |
| `council_ui_pass4_before_844_pad_camhint.jpg` | UI review pass 4, before: gamepad camera hint on an 844 x 390 phone |

### Character creator

| File | Shows |
|---|---|
| `creator_before_face.jpg` | Character creator before its rework: face |
| `creator_before_phone_face.jpg` | Character creator before its rework: phone face |
| `creator_body.jpg` | Character creator: body |
| `creator_face.jpg` | Character creator: face |
| `creator_face_advanced.jpg` | Character creator: face advanced |
| `creator_gear.jpg` | Character creator: gear |
| `creator_hair.jpg` | Character creator: hair |
| `creator_phone_body_advanced.jpg` | Character creator: phone body advanced |
| `creator_phone_hair.jpg` | Character creator: phone hair |
| `creator_skin_eyes.jpg` | Character creator: skin eyes |

### Training screens

| File | Shows |
|---|---|
| `training_drill_1920x1080.jpg` | Training UI: drill at 1920 x 1080 |
| `training_drill_667x375.jpg` | Training UI: drill at 667 x 375 |
| `training_drill_844x390.jpg` | Training UI: drill at 844 x 390 |
| `training_hub_body_1920x1080.jpg` | Training UI: hub body at 1920 x 1080 |
| `training_hub_gym_667x375.jpg` | Training UI: hub gym at 667 x 375 |
| `training_hub_training_1920x1080.jpg` | Training UI: hub training at 1920 x 1080 |
| `training_hub_training_844x390.jpg` | Training UI: hub training at 844 x 390 |
| `training_hub_training_cards_667x375.jpg` | Training UI: hub training cards at 667 x 375 |
| `training_muscle_1920x1080.jpg` | Training UI: muscle at 1920 x 1080 |
| `training_muscle_844x390.jpg` | Training UI: muscle at 844 x 390 |
| `training_muscle_history_1024x768.jpg` | Training UI: muscle history at 1024 x 768 |
| `training_muscle_history_1920x1080.jpg` | Training UI: muscle history at 1920 x 1080 |
| `training_muscle_history_667x375.jpg` | Training UI: muscle history at 667 x 375 |
| `training_result_1024x768.jpg` | Training UI: result at 1024 x 768 |
| `training_result_1920x1080.jpg` | Training UI: result at 1920 x 1080 |
| `training_result_667x375.jpg` | Training UI: result at 667 x 375 |
| `training_result_844x390.jpg` | Training UI: result at 844 x 390 |

### World and lighting

| File | Shows |
|---|---|
| `council_world_arena_crowd.jpg` | World review: arena crowd |
| `council_world_champion_lounge.jpg` | World review: champion lounge |
| `council_world_champion_lounge_from_lobby.jpg` | World review: champion lounge from lobby |
| `council_world_door_one_crowd.jpg` | World review: door one crowd |
| `council_world_lobby_media_set.jpg` | World review: lobby media set |
| `council_world_museum_front.jpg` | World review: museum front |
| `council_world_stadium_crowd.jpg` | World review: stadium crowd |
| `lighting_arena_round.jpg` | Lighting: arena round |
| `lighting_arena_walkout.jpg` | Lighting: arena walkout |
| `lighting_city_day.jpg` | Lighting: city day |
| `lighting_city_night.jpg` | Lighting: city night |
| `lighting_club_arena.jpg` | Lighting: club arena |
| `lighting_community_center.jpg` | Lighting: community center |
| `lighting_gym_boxing_floor.jpg` | Lighting: gym boxing floor |
| `lighting_gym_lobby.jpg` | Lighting: gym lobby |
| `lighting_gym_night.jpg` | Lighting: gym night |
| `lighting_gym_ring.jpg` | Lighting: gym ring |
| `lighting_gym_weights.jpg` | Lighting: gym weights |
| `lighting_menu.jpg` | Lighting: menu |
| `lighting_sparring_room.jpg` | Lighting: sparring room |
| `lighting_stadium_round.jpg` | Lighting: stadium round |

## Asset hair (hair cards)

`hair_assets/hair_<look>.jpg`: one sheet per look, BEFORE (the generated hair) over AFTER (the uploaded
hair cards as the client places and tints them). Views: 3/4, side, back, front, on the game's own head
with its painted skin. Both rows are Blender Cycles renders with matte hair. The scenes came from the
lune simulator: `tools/sim/export_ref.luau` (before) and `tools/sim/after_scene.luau` (after, the real
`HairAssets.Build`).

| Look | Style / type |
|---|---|
| buzz_k, waves_k | Buzz Cut, 360 Waves / Kinky |
| lowfade_k, highfade_k, midfade_s, taper_c, burst_cu | Low / High Fade (Kinky), Mid Fade (Straight), Taper Fade (Coiled), Burst Fade (Curly) |
| afro_k, afro_c_f | Afro / Kinky, Afro / Coiled (female) |
| shortdreads_c, dreads_k, twists_k | Short Dreads, Dreadlocks, Twists |
| braids_k_f, boxbraids_k_f, cornrows_k | Braids, Box Braids (female), Cornrows |
| long_s_f, long_w_m | Long Hair / Straight (female), Long Hair / Wavy (male) |
