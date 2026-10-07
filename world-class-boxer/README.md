# Become a World-Class Boxer

A Roblox boxing career game, written entirely in procedural Luau. You create a boxer, train in a gym,
eat, rest and spar, take fights from the amateurs up to world title nights in big arenas, earn money
and fame, buy homes and gear, and upgrade your gym. Nothing in the world is an uploaded model: the
city, the gyms, the arenas, the equipment and every character are built from code when the server
starts. On each client, the characters are then given organic, generated meshes.

## Opening the game

**Place file.** Open `BecomeAWorldClassBoxer.rbxlx` in Roblox Studio and press Play. This file is a
built snapshot. It can be older than `src/`, so rebuild it after you pull changes (see below).

**Rojo (recommended for development).** The project file is `default.project.json`:

| Folder | Becomes |
|---|---|
| `src/shared` | `ReplicatedStorage.Shared` (data, builders, mesh generators) |
| `src/server` | `ServerScriptService` (`Main` + `BoxerModules`) |
| `src/client/*.client.lua` | `StarterPlayerScripts` |
| `src/client/modules` | `StarterPlayerScripts.BoxerClient` |

```sh
rojo build -o BecomeAWorldClassBoxer.rbxlx   # a fresh place file
rojo serve                                   # live sync into Studio (Rojo plugin > Connect)
```
Lint with `selene src`.

## Publishing requirements

### Organic characters (EditableMesh / EditableImage)
Characters are drawn with procedurally generated meshes and textures (see [Characters](#characters)).
In a **published** game these need two things:
- **Game Settings > Security > Allow Mesh / Image APIs** turned on for the experience.
- An **ID-verified** creator account. Roblox requires this for EditableMesh / EditableImage in live
  games.

Studio play works without either.

**Automatic fallback.** The game falls back to the part-built characters on its own in three cases:
- the APIs are unavailable (the setting is off, or the creator is not verified),
- a mesh cannot be created,
- a device runs out of Editable memory.

In that case every character keeps the part-built look. It is fully dressed and animated, nothing
breaks, and a warning is logged once. Under memory pressure, AnatomyClient first lowers the detail
level and returns far-away characters to parts before it gives up on meshes. The training screen's
anatomical body map is painted into an EditableImage too, and falls back to plain frames the same way.

Players can lower the meshes in **Settings > Graphics detail** (Auto / High / Medium / Low). To switch
the meshes off for everyone, set `Config.Anatomy.enabled = false` in `src/shared/Config.lua`. Budgets
(full-detail characters, ranges, per-frame build time, triangle budgets per section) are set in the
same table.

### Saving (DataStore)
Careers are saved with DataStoreService in the store `Config.DataStoreName` (`WorldClassBoxer_v2`).
- **Published game:** saving works as is.
- **Studio:** turn on **Game Settings > Security > Enable Studio Access to API Services** to save.
  If it is off, Studio plays a session-only career and never writes anything.
- **Failed load:** if a DataStore read fails when a player joins, the server keeps retrying. The
  player sees "Couldn't reach Roblox's save servers. Retrying..." and nothing can overwrite the real
  career. After about two minutes of failures, the player is kicked with a clear message.

Old saves stay valid. Every new field has a default and is sanitised. Player settings (UI scale,
volumes, graphics detail, screen FX, camera shake) are saved with the profile.

## Controls

Every on-screen hint follows the device you used last: key caps on keyboard and mouse, the
controller's own button names on a gamepad (Xbox **A / B / X / Y, LB / RB, LT / RT**, or
PlayStation **Cross / Circle / Square / Triangle, L1 / R1, L2 / R2**, read from the connected
controller), and tap hints with the touch pads on a phone or tablet. Picking up another device
switches them on the spot.

**Around the gym**

| Action | Keyboard | Controller | Touch |
|---|---|---|---|
| Move / camera | WASD, mouse | Left stick / right stick | Thumbstick, drag |
| Use a station or counter | E | X / Square | Tap the prompt |
| Career Hub | H | D-pad up | CAREER HUB button |
| Main menu | M | D-pad down | MENU button |

**Menus and windows.** On a controller, every window (Career Hub, creator, barber, locker room,
nutrition, sleep, stores, results, sparring picker) opens with a button already selected. The D-pad
or left stick moves the selection, **A** presses, and **B** closes the window (in the creator it goes
back a page). The right stick scrolls long lists. On a selected slider, option cycler, toggle or
colour wheel, D-pad left / right changes the value (**A** flips a toggle, steps a cycler or darkens
the colour). In the Career Hub, **LB / RB** step through the tabs. The main menu uses the D-pad, **A**
to select and **B** to go back.

**Fights**

| Action | Keyboard | Controller (Xbox / PlayStation) | Touch |
|---|---|---|---|
| Jab | 1 / J (or left click) | X / Square | JAB |
| Cross | 2 / K (or right click) | Y / Triangle | CROSS |
| Lead hook | 3 / L | B / Circle | HOOK (alternates hands) |
| Rear hook | 4 / ; | A / Cross | HOOK |
| Uppercut | 5 / U | RT / R2 | UPPER |
| Overhand | 6 / O | RB / R1 | - |
| Body shot (with a punch) | hold Shift | hold LB / L1 | BODY toggle |
| Block | hold F | hold LT / L2 | hold BLOCK |
| Slip left / right | Q / E | flick the right stick left / right | drag BLOCK left / right |
| Roll | C | flick the right stick down | - |
| Parry | R | D-pad up (or flick the right stick up) | - |
| Pivot left / right | Z / X | D-pad left / right, or click the right stick (toward the left stick's lean) | - |
| Clinch | G | D-pad down or click the left stick | CLINCH |
| Show the controls | hold H | hold View / Share | - |
| Get up after a knockdown | mash Space | mash A / Cross | tap the panel |

When you are down, every press counts and a press while the marker is in the green zone counts three
times, on every device. During a fight the left stick still moves your boxer. The controller's
fight buttons are bound only for the fight: jumping, the camera's right stick and the prompts' X
button come back when it ends.

**Training minigames.** Each drill's buttons show the key or button that works it. A controller
uses the fight layout: punches on the face buttons and triggers, slips and rolls as right-stick
flicks, pivots and parries on the D-pad. The speed bag's left and right hands are **X / Y**. Lifts,
slams, jumps, pace and breathing are **A** (on the heavy bag the POWER shot is **LT**, because **A**
is the rear hook). Footwork, the agility ladder and the rope's feet use the D-pad. On roadwork and
swimming you move with the left stick, and **Y** finishes early. **View / Share** quits a drill. On
the session report, **A** continues, **X** flexes and **B** closes.

## Characters

Every boxer is generated from his look (face sculpt, skin, hair, physique, gear) and his training, so
no two look alike.

**How a character is made.**
1. The server (`src/shared/Builder*.lua`) scales an R15 rig to athletic proportions for the frame and
   physique and builds the round-1 part-built look on it: layered muscle parts, a face rig, hair,
   beard, gear. This is the fallback, and it carries collisions and animation. The Builder also
   lowers the Neck joint's pivot below the head (by 0.26 of the head's height for men, 0.22 for
   women), so the head sits on a visible neck instead of on the trapezius.
2. It publishes `LookData` (a compact JSON attribute) and a signature per section on the model.
   Meshes do not replicate, so each client generates them itself.
3. On each client, `AnatomyClient` runs the shared generators (`MeshKit`, `AnatomyBody*`,
   `AnatomyHead*`, `AnatomySkull`, `AnatomyHair*`) within a per-frame time budget. It welds the meshes
   to the rig, and hides the parts they replace only once the replacement exists.

**Levels of detail.** The local player, the fight opponent and the nearest few characters (default 6
within 70 studs) get full detail. Others get medium or low. Beyond 160 studs characters stay
part-built. Mesh builds are cached by signature, so identical NPCs share work.

**Body.** One continuous skin over a real ribcage, with:
- chest: upper and lower pecs, serratus;
- shoulders and back: deltoid caps that blend into the chest and arms, traps, lats;
- arms: biceps, triceps and a tapering forearm;
- core: abs (upper and lower), obliques;
- legs: glutes, quads, hamstrings, calves.

Muscle definition comes from smooth geometry and painted shading (separation grooves, crowns, veins),
not hard edges. Blend shapes flex muscles in punches and poses, show the pump after training, follow
breathing and jiggle on impacts.

**Gear.** These are organic meshes too:
- padded gloves with stitching, laces, brand marks, finishes and wear;
- boots or trainers with soles, welts and criss-cross laces;
- layered hand wraps under the gloves;
- trunks (four cuts), sports tops, robes.

**Faces.** A rounded skull with forehead, cheekbones, jaw and chin, sculpted by six face shapes plus
sliders, with subtle asymmetry. The face also has:
- eyes that sit in sockets: lids, lashes, iris texture, wet highlights;
- ten nose types with bridge, nostrils and cartilage;
- lips with a vermilion and corners;
- ears, cauliflower ear and broken-nose options.

The skin is painted with pores, freckles, moles, scars, wrinkles with age, stubble and flush. FaceFX
blinks, moves the eyes (saccades, gaze at the opponent, dazed drift) and blends eleven expressions:
neutral, confident, determined, anger, fear, fatigue, pain, dazed, effort, happy and KO.

**Hair.** 30 styles plus bald across five hair types (straight, wavy, curly, kinky, coiled). They
include fades from skin to high (as gradients), crops, curly tops, afros made of curl clusters, 360
waves, twists, cornrows, box braids, dreadlocks, long hair, ponytails and wolf cuts. Hair follows the
skull in layered clumps and strands, with sliders for volume, curl size, frizz, density and length.
Dyes come as tips, streaks, ombre or split. Hair and beards grow a little every in-game day. HairFX
swings long hair, locs and braids, bounces curly volumes, keeps tips out of the shoulders and makes
sweaty hair heavier and darker.

**Damage and condition.** Sweat, grime, bruises, swelling, cuts, a black eye, a bloody nose and a
split lip show on the meshes. Face damage persists after a fight (stages: fresh, light, moderate,
heavy, severe) and heals over in-game days.

## Animation

Everything is procedural, driven on each client by `Animator.client.lua` and the `Anim*` modules.
- **Fight styles:** each style has its own stance, bounce, guard and idle life, and a per-boxer
  persona keeps two boxers of one style from moving alike. The styles are Out-boxer, Swarmer,
  Slugger, Counter puncher and Boxer-puncher.
- **Footwork:** feet plant in the world and never slide. Inside the ring: step-drag shuffles,
  pivots, backpedalling and side steps. Outside it: walk, jog, run and sprint gaits with heel-toe
  roll.
- **Punches:** kinetic chains (legs, hips, shoulders, fist), aimed at the opponent's chin or body:
  - jab: fast and snappy;
  - cross: hip turn and full extension;
  - hooks: an arc round the body;
  - uppercuts: leg drive;
  - body shots: change level at the knees.
- **Defence:** slips, rolls, parries, pivots, the shell and clinches.
- **Hit reactions:** light head snaps, medium stumbles, heavy leg wobbles and critical buckles, each
  directional.
- **Knockdowns:** flash, forward, side, on the ropes and in the corner.
- **Knockouts:** one-punch timber falls, delayed KOs, standing KOs held up by the referee, face-first
  and backward collapses. KOs play in slow motion.
- **Get-ups:** staged for each kind of fall.
- **Gym poses:** every exercise and flex has its own pose, and coaches, cornermen and members train
  around you.

## Interface

- **Main menu:** your boxer in his corner of a gym at night, with a drifting camera, light shafts and
  dust. Its items are Continue / New Career, Career, Character, Gym, Rankings, Store and Settings.
  Press **M** (D-pad down on a controller) in the world to open it again. It works with keyboard and gamepad.
- **Fighter card:** a posed studio portrait of your boxer, with:
  - name, nickname, weight class and nationality flag;
  - record, knockouts and KO ratio;
  - four world-title belt slots and rankings per sanctioning body;
  - physique, style and recent form.
- **Career Hub (H, D-pad up):** tabs for Career, Training, Body, Stats, Gym, Gear, Coaches, Sponsors, Life,
  Rankings, Rivals, Shop and Legacy.
- **Training UI:** a progress bar for every exercise, and an anatomical body map. The map shows the
  muscles an exercise works, the growth each muscle got from a session, and how developed each
  muscle is.
- **Fight HUD:** a broadcast-style scoreboard showing:
  - separate HEAD, BODY and STAMINA bars, with permanent-damage caps;
  - status chips (DAZED, IN DANGER, OUT ON HIS FEET);
  - the round timer, hit markers and crowd reactions;
  - commentary, corner advice and a tale of the tape.

  Phones get a compact strip and touch pads.
- **Settings:** UI scale, music and SFX volume, screen effects (blur, colour drain, flashes), camera
  shake, graphics detail, main menu at start, and the fight control strip.

## Training and physique

Everyone starts lean, with little muscle and average conditioning. Each exercise grows its own muscles
(`Config.ExerciseTargets`), up to the potential of the boxer's frame (Lean, Athletic, Muscular, Power
Build or Heavyweight Build):

| Exercise | Grows |
|---|---|
| Bench press | Chest, front delts, triceps |
| Dumbbells | Biceps, forearms, side delts (and arm veins) |
| Squats | Quads, glutes, calves, hamstrings |
| Pull-ups | Lats, upper back, traps, biceps, core |
| Medicine ball | Abs, obliques, lower abs, serratus |
| Deadlift (barbell) | Lower back, traps, hamstrings, glutes (thicker neck) |
| Heavy bag, mitts, speed bag, double-end bag, shadow boxing, sparring | Shoulders, arms, core, neck |
| Roadwork, rope, ladder, treadmill, bike, rower, swimming | Legs and conditioning, lower body fat |

Body fat, definition, vascularity, pump, soreness, recovery and detraining all show on the body. The
trained body is classified into a physique, which sets the visible shape:
- Beginner Lean
- Lean Technical
- Balanced Pro
- Power Puncher
- Heavyweight
- Elite Champion

Training also uses energy, hydration, nutrition and fatigue. Graded minigames reward good technique.

## Gyms

Your gym grows through four tiers (`Config.GymTiers`). Each has its own decor, lighting, equipment
condition and training multiplier.

| Tier | What changes |
|---|---|
| Beginner Gym | Torn bags, taped ropes, flickering lights, water stains |
| Intermediate Gym | Fresh paint, club ring, sponsor banners, LED strips, round timers |
| Elite Training Center | Cryotherapy, plunge pools, sports science lab, motion tracking, analytics wall |
| World Champion Facility | Gold trim, title photos, media wall, red carpet, fan zone |

Each tier needs a share of the equipment upgraded and a career tier. Owning the Smart System can
stand in for Elite's career tier, and World Champion also needs the Recovery Chamber.

The gym itself has:
- a heavy bag that swings on its chain, dents and sounds on impact;
- ambient sound, coaches shouting instructions, and members training;
- sparring with an audience;
- posters, trophies and mirrors;
- sun shafts, dust and sweat puddles.

## Fights and the KO model

- **Three health pools:** HEAD, BODY and STAMINA. Head punches cost head HP by type: the jab least,
  then the cross, then hooks, then the uppercut and overhand, the most. Body shots drain body HP and
  stamina.
- **Head tiers:**
  - 100–30 %: conscious.
  - 30–15 %: dazed.
  - 15–5 %: severe danger.
  - under 5 %: a high chance of being knocked out.
- **Knockdown odds** (`Config.KOChance`) are worked out for every landed head shot. They depend on:
  - the defender's chin, conditioning and current stamina;
  - the attacker's power;
  - how cleanly the punch landed and the punch type;
  - whether it was a counter;
  - previous knockdowns, concussion and career trauma.
- **Knockdowns:** not every hard punch drops a fighter. A fresh fighter only goes down to a clean
  power counter (a flash knockdown). Hard shots also cause stumbles and loss of balance.
  - Severities: flash, normal, heavy, out cold.
  - Downed fighters beat the count with a timing and mashing get-up, then take a mandatory eight
    count.
  - Three knockdowns in a round is a TKO. The referee and the ringside doctor can also stop a
    fight.
- **Concussion:** builds with head damage. It slows punches and movement, lowers accuracy and
  defence, and blurs and drains the screen. It recovers between rounds and over days. Repeated
  trauma carries over the career.
- **Controls:** shown on screen (hold **H**, or **View / Share** on a controller, in a fight). The
  full keyboard, controller and touch layouts are in [Controls](#controls).
- **Fight nights:** weigh-ins, ring walks, a referee, judges' scorecards and a crowd. The venues are
  a community centre, a club arena, the Grand Arena and the National Stadium for title fights. The
  big venues have fight-night lighting, LED screens, broadcast cameras and a walkout stage.

## Career and city

- **Career ladder:** ten tiers from Amateur to Boxing Legend, with purses and rounds that grow.
  - 270 AI boxers across nine weight classes.
  - Rankings with four sanctioning bodies (WBA, WBC, IBF, WBO).
  - Title fights, unifications and defences.
  - Rivals and trilogies.
  - A training camp before each fight.
  - Injuries.
  - Retirement and a Hall of Fame legacy.
- **Money and status:** sponsors (four slots) and fans grow with fame. You can buy a City Apartment,
  a Suburban House or a Mansion, plus upgrades (garage, home gym, trophy room, recovery suite, pool
  deck), coaches and gear from seven brands.
- **The city:** around the gym are Main Street's shops (diner, supplements, pro shop, barbershop and
  more), houses, a park and the arena. Shops have walk-in counters.

## Adding sounds

The game ships only with sounds that every Roblox client has built in (`rbxasset://sounds/...`). Every
other sound is an optional slot in `Config.SoundIds` (`src/shared/Config.lua`). Each slot defaults to
`""`, and an empty slot is skipped.

To fill a slot, paste an audio asset that you own or that is public on the Creator Store, either as
`"rbxassetid://123456789"` or as the bare number:

```lua
Config.SoundIds = {
	CrowdRoar = "rbxassetid://123456789",
	WalkoutMusic = "987654321",
	...
}
```

| Group | Keys |
|---|---|
| Crowd | `CrowdRoar`, `CrowdMurmur`, `CrowdBoo`, `CrowdOoh` |
| Ring | `RingBell`, `RefereeCount`, `Announcer` |
| Music | `WalkoutMusic`, `ArenaMusic`, `GymMusic` |
| Voices | `CoachShout`, `CornerShout` |
| Impacts | `PunchImpact`, `BodyShot`, `BagThud`, `BagChain`, `SpeedBag` |
| Ambience and body | `GymAmbience`, `CityAmbience`, `Heartbeat`, `Breathing`, `CameraFlash` |

The comment above the table says where each one plays and what to upload (length, loop or one-shot).

When a slot is empty:
- **Crowd, bell, count, coach and corner shouts, impacts, heartbeat, city ambience and camera
  flashes** play a shaped built-in stand-in (`Config.SoundFallbacks`).
- **Music, the announcer, the gym ambience slot and breathing** stay silent. The gym already runs its
  own built-in air-conditioning bed.

Music plays through the Settings screen's Music volume. Everything else plays through its SFX volume.
Test every id in Studio. An id that the experience is not allowed to play stays silent and only logs
a warning.

## Preview images

Offline renders of the real generators and Builder, made outside Roblox with a three.js renderer.
Lighting approximates Roblox's Future lighting, so expect small differences in Studio.

**`previews/final/`** shows the current characters. Its `README.md` explains how they were made.

| File | Shows |
|---|---|
| `01_cast_idle_stance.jpg` | 15 boxers in their style's fight-stance idle |
| `02_cast_cross.jpg` | The same 15 as the cross lands |
| `03_faces_front.jpg`, `04_faces_three_quarter.jpg`, `05_faces_profile.jpg` | 15 faces from the front, at 3/4 and in profile |
| `06_hair_back.jpg` | Heads from behind (fades, locs, braids, napes) |
| `07_macro_eyes_gloves_boots_mouths.jpg` | Close-ups of eyes, gloves, boots and mouths |
| `08_wraps_and_flex.jpg` | Hand wraps, and the double-biceps flex |
| `09_round1_fallback_cast.jpg` | The part-built fallback (mesh APIs off) |
| `10_poses_balanced_highfade.jpg` to `13_poses_heavyweight_dreads.jpg` | Pose sheets: idle, guard, jab, cross, hook, uppercut, knockdown or KO, flexes |
| `14_closeups_elite_cornrows.jpg` to `17_closeups_female_longhair.jpg` | Face, profile, back of head, torso, gloves and boots close-ups |
| `18_neck_interface_clay.jpg`, `19_faces_clay.jpg` | Untextured (clay) geometry |
| `20_medium_detail.jpg` | Medium detail (distant NPCs) |
| `21_neck_lift.jpg` | The neck before and after the lift: front, profile, the guard, clay and the part-built fallback |
| `22_mouths_beards_eyes.jpg` | Mouths, beards and eye macros |
| `23_cast_lead_hook.jpg` | The lead hook landing, from above |

**`previews/rework/`** has the round-2 working renders, one folder per area: `R-anim`, `R-body`,
`R-hair`, `R-head`, `R-ui` and `integration-A`.

**`previews/round1/`** has the round-1 part-built characters, for comparison. Its `README.md` lists
them.

## Known limitations

- The preview renders are not Roblox screenshots. Test the look in Studio with the mesh APIs on.
- On the most muscular builds, a soft crease still shows where the deltoid meets the torso. Some
  glove angles still read a little like mittens.
- The neck is a plain column. The trapezius does not slope up into it, so from behind it can look
  like a pipe standing on the shoulders. Women's necks can look a little long in profile.
- A much shorter boxer cannot always reach a much taller one's chin. When the smallest women punch
  up at a Balanced man, some overhands and uppercuts land under the chin. In an offline test of 200
  such punches, 31 missed or broke a quality check, against 30 before the neck was lengthened.
- On the palest skin tones, the chest highlights can look a little chalkier than the face.
