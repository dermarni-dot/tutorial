# v10 lighting: bright, vivid and colourful

Offline Cycles renders (`tools/sim/world_scene.luau` -> `tools/sim/world_render.py`, 20 samples at 960x540) of the game
with the lighting pass that answers "it's just dark and bland; add better, colourful lighting". The renderer now reads the
Lighting state the server sets (`scene.lighting`, from `Config.Lighting` through `MapBuilder`) and the fight-night
profiles (`scene.venueLighting`, `VenueFX.Profiles`): the sun, the sky and the fills scale with `Brightness` /
`Ambient` / `OutdoorAmbient`, the exposure follows `ExposureCompensation`, and a compositor chain approximates the
`ColorCorrectionEffect` (saturation, contrast, brightness, tint, with Ambience's zone grade stacked on top) and the
`BloomEffect` (a glare pass). Approximate: Cycles is not Future lighting, and no Roblox material textures.

| File | What it shows |
|---|---|
| `gym_ring_before.jpg` | The main hall before this pass (the same view, the old Lighting) |
| `gym_ring.jpg` | The main hall: warm window keys, the neon zone signs, the red / blue apron LEDs and gel washes over the ring, the magenta / cyan accent spots, the glowing round timer |
| `venue_t3_title.jpg` | The Arena on a world title night, ringside: white ring keys, gold corner glows and apron LEDs, the gold fascia trims, the spots in their title gels, the tinted house wash over the stands |
| `venue_t3_title_wide.jpg` | The same night from high in the bowl |
| `city_main_day.jpg` | Main Street by day: the warm sun, the saturated sky, the shop neon and the gold billboard frames |
| `city_main_night.jpg` | Main Street after dark: a blue night fill, the coloured shop neon and its pools, the lit billboards, the magenta / cyan / gold / green accents under alternate street lights, the lit windows |
| `menu_stage.jpg` | The title screen: the warm key, the magenta rim and cyan kicker, the gradient backdrop with its magenta / blue wall washes |

## Lighting values (the world outside fights)

| Property | before | after (`Config.Lighting.Global`) |
|---|---|---|
| Technology | Future | Future |
| ClockTime | 13.6 | 13.6 |
| Brightness | 3.6 | 4.4 |
| ExposureCompensation (base) | 0.1 (Ambience then set 0 outdoors, 0.18 in the hall) | 0.35 base; Ambience adds the zone offset (hall +0.1, night outdoors +0.2) |
| Ambient | (138, 132, 126) | (156, 150, 146) |
| OutdoorAmbient | (150, 158, 172) | (166, 178, 204) |
| ColorShift_Top | (255, 240, 216) | (255, 234, 196) |
| ColorShift_Bottom | (210, 220, 240) | (196, 214, 244) |
| ShadowSoftness | 0.2 | 0.38 |
| EnvironmentSpecularScale | 0.7 | 0.8 |
| GymGrade (ColorCorrection) | B 0.03, C 0.08, S 0.14, tint (255, 250, 244) | B 0.04, C 0.1, S 0.25, tint (255, 248, 238) |
| GymBloom | I 0.3, size 28, threshold 1.6 | I 0.5, size 34, threshold 1.2 |
| GymSunRays | I 0.08, spread 0.7 | I 0.14, spread 0.8 |
| Atmosphere | density 0.28, offset 0.3, colour (222, 228, 238), decay (150, 172, 204), glare 0.25, haze 1.6 | density 0.2, offset 0.32, colour (228, 236, 250), decay (96, 150, 230), glare 0.42, haze 1.9 |
| Sky | sun 14, moon 11 | sun 16, moon 11, 1500 stars |
| Night (Ambience, after dusk) | OutdoorAmbient -> (96, 106, 136) | OutdoorAmbient -> (82, 98, 164), Ambient -> (120, 118, 140), atmosphere -> violet (150, 130, 200) / decay (40, 48, 120); grade StreetNight S +0.2 |

## Fight nights (VenueFX profiles)

| Venue | before | after |
|---|---|---|
| Arena | bright 0.4, ambient (68, 70, 84), outdoor (52, 54, 70), exposure 0.16, sat 0.08, bloom 0.5 / 1.4 | bright 0.7, ambient (86, 90, 116), outdoor (70, 76, 112), exposure 0.3, sat 0.24, bloom 0.75 / 1.1, house tint (190, 200, 255) |
| Stadium | bright 1.0, ambient (72, 76, 94), exposure 0.16, sat 0.1, bloom 0.6 / 1.35 | bright 1.2, ambient (90, 96, 124), exposure 0.3, sat 0.24, bloom 0.8 / 1.1 |
| ClubArena | bright 0.45, ambient (80, 74, 88), exposure 0.2, sat 0.04, bloom 0.5 / 1.4 | bright 0.6, ambient (96, 86, 110), exposure 0.32, sat 0.22, bloom 0.7 / 1.15, house tint pink |
| CommunityCenter | bright 1.1, ambient (122, 116, 106), exposure 0.2, sat -0.06 | bright 1.3, ambient (134, 128, 118), exposure 0.3, sat 0.08 |
| Gym (sparring) | bright 2.8, ambient (120, 112, 104), exposure 0.15, sat 0.02 | bright 3.4, ambient (140, 134, 128), exposure 0.3, sat 0.14 |

Ring keys (255, 250, 242) at 5.0 (were (255, 242, 224) at 4.2), kickers 3.0, the rig banks at 0.7 of their power in
white. The follow spots step through a gel palette (magenta, cyan, gold, red, blue, green; gold and white on a title
night) while they sweep the house, and go back to their lamp colours on the boxers in the rounds. Client-local: corner
glows (red / blue, gold on a title night) at the four posts, apron LED strips, a glowing trim on every LED fascia, the
house lights tinted red side / blue side. Pyro flashes at 8 (were 5), range 56, in the corner's colour.
