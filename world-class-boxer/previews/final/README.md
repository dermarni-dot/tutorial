# Final character renders (visual judge, round 2)

These are offline renders of complete characters, as the game shows them when the mesh APIs are on. Each one combines the AnatomyBody, AnatomyHead and AnatomyHair meshes, including the gloves, boots, wraps and trunks pieces, on the athletic rig from Integration A. Everything came from the current working tree. Nothing in the repo was changed to make them.

Every sheet was re-rendered after the neck lift (see [Neck lift](#neck-lift) at the end), so all of them show the current neck and punches. The sections in between record what each earlier pass changed.

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
