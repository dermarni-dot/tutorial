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
| `21_neck_lift_proposal.jpg` | The neck with the head polish fixer's Builder lift and Body column requests applied (`scratchpad/integration2/PF-head.md`), against the current tree |
| `22_mouths_beards_eyes.jpg` | Polish pass on the head: mouths and beards at 3/4, and eye macros |
| `23_cast_lead_hook.jpg` | All 15 at the moment the lead hook lands, seen from above: the fist swings round the body into the side of the jaw with the elbow bent (game polish pass) |

The judge's full defect list, with generator file and function and a fix for each, went back to the orchestrator. The main defects these images show:

- **Neck and boots:** the neck barely shows (the chin is only 0.1–0.26 studs above the deltoids), and the boots are about 22 % of body height (a real foot is about 15 %).
- **Gloves and trunks:** the gloves look like mittens or tubes, and the trunk legs look like inflated tubes.
- **Lips and eyes:** in profile the lips stick out past the nose. The eyeballs show as white triangles in profile.
- **Hair and beards:**
  - the afro is shaped like a mushroom or helmet
  - some locs stick out sideways at the shoulders
  - cornrows and 360 waves are painted stripes
  - beards look like solid slabs
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

The other sheets are unchanged from the judge's set.

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

The longer neck needs the Builder and Body requests in `PF-head.md`; see `21`. The final regression pass tried them: the neck rendered as intended, but the animation lab's punch gates then failed (an overhand forearm passes through the boxer's own raised head, and some lead hooks lose lateral travel), so they are not applied yet.


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
