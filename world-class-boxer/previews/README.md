# Boxer character previews

Still images of the overhauled boxer characters, so you can see them without opening Roblox Studio.

| Image | What it shows |
|---|---|
| `01_amateur.png` | Day-1 amateur: the creator's default look (`Looks.Defaults(1)`, Short Dreads) on a brand-new career body (`Training.NewBody`, which the game draws with the Beginner Lean physique). Full body, guard (chest up), face front and 3/4. |
| `02_lean_technical.png` | Lean Technical physique: Lean frame, about 7% body fat, Taper Fade. The beard is grown in because the random look has beard style None with growth of 0.8 or more, and the Builder draws that as Short Boxed. |
| `03_power_puncher.png` | Power Puncher physique: Power Build frame, Afro (afro-textured hair), Short Boxed beard, Ironvale gloves. |
| `04_heavyweight.png` | Heavyweight physique: 6'4", about 20% body fat, Buzz Cut and Full Beard. |
| `05_elite_champion.png` | Elite Champion physique: about 7% body fat, Cornrows, gold World Champion gloves with a crown logo, "KING" waistband. |
| `06_female_ponytail.png` | Female boxer with a Ponytail and the Lean Technical physique. |
| `07_hairstyles.png` | Head close-ups of nine hairstyles: Taper Fade, Afro, Dreadlocks, Textured Crop, Curly Top, Cornrows, Wolf Cut, Ponytail and Buzz Cut with a Full Beard. |
| `08_face_damage_stages.png` | One boxer at face-damage stages 0 to 4 (fresh, light, moderate, heavy, severe) through `Builder.SetDamage`. Each damage table was checked against `Config.FaceDamageStage`. Front and 3/4 views. |
| `09_sweat.png` | The same boxer dry and at `Builder.SetSweat(0.9)`: higher reflectance, plus face sheen and sweat-bead parts. |
| `10_gloves_wraps.png` | Close-ups of the hands: branded custom gloves (Kazari, patent red, lightning logo) from the front and the side, gel hand wraps, and the starter "Worn" gloves. |
| `11_random_boxers_grid.png` | Eight AI opponents from `Looks.Random` and `Looks.RandomBuild` with different seeds, weight classes and archetypes, to show that no two look alike. |

## How they were made

These are offline renders of the real Builder geometry:

- Every character was built by the game's own `Builder.CreateNPC` / `Builder.Cosmetics` code with `detail = "full"`, running inside the headless Roblox simulator.
- The R15 rig was scaled by the HumanoidDescription scales that `Builder.Description` sets.
- The arms were posed by setting the rig's Motor6D `Transform` values.
- Every visible part, beam and SurfaceGui label was exported, then drawn with three.js in headless Chromium.

Some things are approximated, so **Studio will look somewhat different**:

- **Lighting.** A warm key light, a cool fill light and two rim lights stand in for Roblox Future lighting. Shadows are soft, and tone mapping is ACES. There is no SSAO and no bloom.
- **Materials.** Roughness and metalness values stand in for Roblox's SmoothPlastic, Plastic, Fabric, Leather, Sand, Rubber and Foil. The 2022 material textures (fabric weave, sand grain) are not reproduced.
- **Head shape.** The Roblox "Head" SpecialMesh is drawn as a rounded cylinder.
- **Beams.** Hair strands, veins and blood are drawn as camera-facing ribbons along the Beam Bezier curve.
- **Text.** Labels use local fonts in place of Michroma, Oswald, Bangers, Garamond and GothamBlack.
- **Client-side effects are not shown.** That includes the animation, breathing, FaceFX/BodyFX and the client's extra sweat and pump effects. Only the server-built geometry appears.
- **Shadows.** Parts follow the Builder's `CastShadow` flags. Most cosmetic parts do not cast shadows; the body shadow comes from the "Hull" parts.
- **Snapshot.** The geometry was exported from the Builder code on disk at about 02:20 on 5 October. The Builder files have changed since then (for example, the hair code moved to `BuilderHair.lua`), so a fresh export may differ slightly.
