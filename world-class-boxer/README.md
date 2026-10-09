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

Old saves stay valid. Every new field has a default and is sanitised. Player settings (UI scale, volumes, graphics detail, screen
FX, camera shake, the custom control map, aim assist and vibration) are saved with the profile.

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
| PvP panel | P | D-pad right | PVP button |
| Challenge another boxer | T (near him) | Y / Triangle (near him) | Tap the prompt |

**Menus and windows.** On a controller, every window (Career Hub, creator, barber, locker room,
nutrition, sleep, stores, results, sparring picker) opens with a button already selected. The D-pad
or left stick moves the selection, **A** presses, and **B** closes the window (in the creator it goes
back a page). The right stick scrolls long lists. On a selected slider, option cycler, toggle or
colour wheel, D-pad left / right changes the value (**A** flips a toggle, steps a cycler or darkens
the colour). Held on a slider, the D-pad keeps stepping it, and **X** puts the slider back to its
default. In the Career Hub, **LB / RB** step through the tabs. The main menu uses the D-pad, **A**
to select and **B** to go back.

**Sliders** (creator, barber, settings) work the same everywhere:
- Each slider shows its value in plain words next to the number ("Wide · +40", "Very long · 90%",
  "Loud · 85%", "5'10\"").
- Click or tap anywhere on the bar to jump there. Drag from the bar: the drag keeps following even if
  the pointer or finger drifts off it, and the list does not scroll meanwhile.
- **-** and **+** step it. Hold them to keep stepping.
- With the mouse resting on a bar, the wheel steps it.
- A notch marks the default, and the round button at the top right puts the slider back on it.

**Character creator.** Seven steps: Name, Face, Skin & Eyes, Hair, Body, Gear and Style.
- **Moving between steps:** the step bar under the title (click a step to jump to it), **BACK** /
  **NEXT**, or **LB / RB** on a controller.
- **Presets first:** each step opens with them. Face presets, skin and eye swatches, hairstyle cards
  with a little head wearing each style (filtered by Short / Fades / Curly / Locs / Long), body types,
  gear kits and boxing styles.
- **Main controls:** the four to six that matter most, each with a one-line hint. **ADVANCED** opens
  every other slider of that step.
- **UNDO** (also **Ctrl+Z**, or **Y** on a controller) steps back through the last 20 changes. A whole
  slider drag counts as one change.
- **RESET** puts the current step back to its defaults, and **RANDOM** randomises it. On the first
  step, RANDOM rolls a whole new look.
- **Colours** are swatch grids, with the picked colour ticked and named. A free colour wheel sits
  under Advanced.
- **Camera:** it frames the face on the face, skin and hair steps and the whole body on the others.
  - Turn: drag the boxer (mouse or finger), use the arrows on the dock, or the right stick.
  - Zoom: the mouse wheel over the 3D view, the dock's - / +, or **LT / RT**.
- **Live preview:** every change shows on your boxer. While a slider moves, the preview goes to the
  server at most four times a second, and once more when you let go.

**Fights.** The default map (every key and button below can be changed in **Moves & Controls**):

| Action | Keyboard & mouse | Controller (Xbox / PlayStation) | Touch |
|---|---|---|---|
| Move | WASD | Left stick | Thumbstick |
| Sprint (outside the ring) | hold Shift | click the left stick | - |
| Jab | Left click (or J) | X / Square | JAB |
| Cross | Right click (or K) | Y / Triangle | CROSS |
| Lead hook | F (or L) | B / Circle | HOOK (alternates hands) |
| Rear hook | R (or ;) | A / Cross | HOOK |
| Uppercut | T (or U) | RT / R2 | UPPER |
| Overhand | Middle click (or O) | tap RB / R1 | - |
| Body hook | G | LB + B / L1 + Circle | BODY, then HOOK |
| Body shot (arms the next punch) | tap C | tap LB / L1 | tap BODY |
| Block (guard up / down) | tap B | tap LT / L2 | tap BLOCK |
| Slip left / right | Q / E | flick the right stick left / right | drag BLOCK left / right |
| Dodge (roll under) | Space | flick the right stick down | - |
| Quick dodge | Shift + Space | LT + A / L2 + Cross | - |
| Parry | V | D-pad up (or flick the right stick up) | - |
| Pivot left / right | double-tap A / D (or Z / X) | D-pad left / right | - |
| Counter jab | hold Q + left click | flick left, then X / Square | - |
| Counter cross | hold E + right click | flick right, then Y / Triangle | - |
| Clinch | Ctrl | D-pad down or click the left stick | CLINCH |
| Special moves | 1 - 9 (in the menu's order) | hold RB / R1 + a button (below) | the gold pads above the punches |
| Show / hide the controls strip | tap H | tap View / Share | - |
| Moves & Controls menu | Tab | hold View / Share | - |
| Get up after a knockdown | mash Space | mash A / Cross | tap the panel |

How the conflicts with the old map were resolved: the body modifier moved from Shift to **C** (Shift is the
sprint and the quick-dodge chord), block from F to **B**, parry from R to **V**, roll from C to **Space**
(the dodge), the overhand from 6 / O to the **middle mouse button** (O still works), the pivots from Z / X
to a **double tap of A / D** (Z / X still work), and the number row **1 - 9** now throws the special moves
(the old letter alternates J / K / L / ; / U / O stay as second keys). The fight camera is the broadcast
one, so the mouse buttons never turn the camera in a fight: left and right click are free to punch.

**Chords and double taps.** A chord is "hold the first key, press the second" (Shift + Space, Q + click).
On a pad a right-stick flick counts as held for half a second, so "flick left, then X" is the counter jab.
In the ring a flick **up** doubles as D-pad up (the parry), the **left-stick click** as D-pad down (the
clinch) and the **right-stick click** as D-pad left (the pivot), whatever those are bound to, unless you
give the flick or the click a binding of its own (the sprint does not count: it has no use between the
ropes). RB / R1 is both the overhand (tapped on its own) and the special-move modifier (held while another
button is pressed): RB + X check hook, RB + Y pull counter, RB + B liver shot, RB + A overhand right,
RB + RT lead uppercut, RB + LT Philly shell counter, RB + LB step-back counter, RB + D-pad up gazelle
punch, RB + D-pad down peek-a-boo rush. A double tap is two presses of one key within a third of a
second; a plain press of A or D still walks.

**Tap, don't hold.** Block, the body-shot modifier and the controls legend are toggles on every
device: a tap turns them on, the next tap turns them off. A press held longer than about a third of
a second still works as a hold and lets go when you release. Throwing a punch drops a tapped guard
(you cannot punch through your own gloves) and spends a tapped body modifier. The fight HUD lights
what is on: the **GUARD UP** and **BODY SHOT ARMED** chips above the ticker, the BLOCK / BODY key
caps and the touch pads.

**Moves & Controls menu** (main menu > CONTROLS, Settings > Controls, the Career Hub's CONTROLS button,
**Tab** in a fight, hold **View / Share** on a pad, or `State.open.Controls()` from any screen; while it
is open the game's own hotkeys H / P / M and the pad's D-pad shortcuts are off, so any of them can be
bound). Four tabs, all mouse, touch and
controller navigable (D-pad / left stick moves, A presses, B closes, the right stick scrolls):
- **Moves:** Basic, Punches, Advanced and Special sections. Every move shows its key cap, button or
  touch pad for the device you pick (it starts on the one you are using, and follows a device
  change), what it does and when to use it. Special moves say LOCKED / UNLOCKED and how they unlock.
- **Keyboard / Controller:** rebind any action. Click (or select and press A on) a key cap, then press
  the new key or button; hold one key and press another for a chord, tap a key twice for a double
  tap, flick the right stick for a flick. Backspace clears a keyboard slot, Escape / B cancels. A key
  another action already uses is **swapped** over (that action takes the old key), so no two actions
  share a key; a conflicting map loaded from an older save is shown in red with the other action
  named. Two slots per action on the keyboard, one on the pad; a per-row reset and RESET ALL TO
  DEFAULTS. Movement, the get-up mash and the hold-to-open are fixed.
- **Console:** aim assist (Off / Low / High), controller vibration on / off and strength, a test
  rumble. The same three settings sit in Settings > Controls.

The custom map is saved with the profile (`settings.ui.keymap`, through the same `SaveSettings`
request as every setting) and the server sanitizes it with `Keymap.Sanitize`: only known actions,
only valid keys for that device, at most two keyboard bindings and one pad binding each, nothing
reserved (Escape, the function keys, a plain press of W / A / S / D). Aim assist and the vibration
settings go through the same allow-list.

**Special moves** (`src/shared/Moves.lua`). Nine signature moves, each a real set-up followed by one or
two ordinary punches landed on the animation's own schedule (`FightMotion.SpecialHits`), so every
head and body reaction plays as for any punch. A move unlocks by **style and career tier** (its home
styles get it early, everyone a few tiers later) **or by a training milestone** (sessions on one
exercise); nothing new is saved, the set is worked out from the profile each time, so old saves just
work. The AI uses them too (its style's moves once it is good enough), each in the situation it is
for. A medium-or-worse shot taken cancels the punches you have not thrown yet.

| Move | Home styles (tier) | Anyone from | Or train | What it does |
|---|---|---|---|---|
| Check hook | Out-boxer, Counter puncher (Local Pro) | International Contender | 10 Agility Ladder | Lead hook as he steps in, then a pivot out: a counter when it catches him punching, an angle for the next shot |
| Philly shell counter | Counter puncher, Boxer-puncher (Regional Champion) | Top 10 Ranked | 12 Shadow Boxing | Shoulder roll (head shots slide off for a third of a second), then the cross; what it rolls makes the cross a counter |
| Pull counter | Counter puncher, Out-boxer (Regional Champion) | Top 10 Ranked | 10 Double-End Bag | Lean back out of a straight punch, land the right hand as he resets |
| Liver shot | Swarmer, Slugger (Local Pro) | International Contender | 12 Heavy Bag | Dipping left hook under the elbow; a clean one folds a man a beat later even when his body is far from done |
| Gazelle punch | Slugger, Swarmer (National Champion) | Title Challenger | 10 Jump Rope | Leaping lead hook from outside jab range (the root leaps 1.2 studs): long reach, big power, easy to see coming |
| Peek-a-boo rush | Swarmer (National Champion) | Title Challenger | 15 Mitt Work | Bob and weave in (slipping head shots), then a left and a right hook on arrival |
| Step-back counter | Out-boxer, Boxer-puncher (Regional Champion) | Top 10 Ranked | 10 Treadmill | Two steps back (everything misses), the cross reaches further as he follows |
| Overhand right | Slugger, Boxer-puncher (Amateur) | National Champion | 8 Heavy Bag | The slugger's looping right over the guard: two thirds lands through a block |
| Lead uppercut | Boxer-puncher, Swarmer (Local Pro) | International Contender | 10 Speed Bag | A short left uppercut with no wind-up to see; lands bigger on a rolling head |

Each move has its own stamina cost, accuracy and damage multipliers, knockdown-odds multiplier and a
cooldown (1.4 - 2.6 s) on the server; the act strings are `special|<id>|<hand>|<windup>|<power>`.

**Console.** *Aim assist* (gamepad only): the left stick is read relative to the opponent, so pushing
up always closes the distance and sideways always circles him (High also keeps you squared up while
you circle); the facing itself is the server's. The server adds a small hit-chance forgiveness (Low
+2 points, High +4) to punches thrown from a pad. The level is read from the **saved** setting, never
from a message, and the device is the one the **server** holds you on: it starts as the keyboard, a
device message moves it (switches are rate-limited: more than three in half a minute lock the help
for the rest of it) and a switch to the pad arms the help only two seconds later; any keyboard, mouse
or touch input switches it off for five seconds, and once the server has seen your character move at
all it also wants the thumbstick's fractional magnitudes in the replicated `Humanoid.MoveDirection`
within the last ten seconds (a keyboard only ever gives 0 or 1), so a keyboard client tagging its
punches as pad input gets nothing. The help never lifts a punch past 85 % and counts for at most 25
punches a round. *Vibration*: hits taken (scaled by how hard), hits landed (a
short tick, more on power shots and counters), blocked shots (a buzz), stumbles and knockdowns (both
motors), through `HapticService` with a strength slider; every call is guarded. *Fight camera*: it
backs off as the fighters separate so both stay in frame, eases a touch more on a pad, and the right
stick nudges it round the pair and up or down (a flick of the same stick is still a slip, roll or parry).

**Impact.** Camera shake scales with the punch's power (a jab barely moves the picture, an overhand
rocks it; power shots and counters you land kick it too) and with the Settings shake slider. Impact
sounds are layered by punch kind (straights snap high, hooks slap, uppercuts and overhands thump, body
shots thud with a grunt, heavy shots and counters add a low crack) with pitch and volume varied every
time; the same sound at nearly the same pitch is never played twice in a row. Sweat (and blood) sprays
off the far side of the head or body, more off power shots and counters, and the point of contact
flashes (bigger for power shots, a triple burst for counters).

**Every round starts in the corners.** Both boxers are put in their own corners and held there (no
steps, no punches: the server refuses every fight input) while a big **3 · 2 · 1 · BOX!** counts in,
one tick a number and the bell on BOX!. Movement and punches come back exactly on BOX!. The training
drills that used to need a hold (lifts, medicine-ball slams, recovery breathing) take a tap to start
and a tap to finish too.

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
- **Training UI:** every exercise runs with a session progress bar and a metrics strip (set, reps,
  good reps, quality, time, heart rate, calories) next to a "muscles worked" card: an anatomical
  body map lit by `Config.ExerciseTargets`. The report that follows shows the grade, every muscle
  that grew (its level before, the growth now, tonight's share, the gain), every stat that rose
  (old -> new), the pump / soreness / sweat / veins / fat chips and the body map re-lit by the
  growth. On top of it: a **+XP toast** that counts up (training levels, level-ups), and a column of
  **gain popups** (one per stat and per muscle part, old -> new) that slide in one after another.
  On a phone the report fills the screen, so the toast shrinks into the top-right corner and the
  popups become one row of chips in the band above the report (stats first, "+N more" when they do
  not all fit; the report lists every one). FLEX strikes a pose; MUSCLES opens the Muscle
  Progression screen on the parts that just grew.
- **Muscle Progression screen** (`MuscleScreen.lua`, Hub Body tab "3D MUSCLE VIEW", the "3D" button
  of every group row, or MUSCLES on a training report): a rotating 3D figure (a frozen copy of
  your character in a ViewportFrame, meshes included) with tabs for Arms, Chest, Core, Legs,
  Shoulders, Back and Neck. The picked group lights up on the figure (neon shells over the region,
  the round-1 muscle overlays tint) and the panel shows its level against your frame's potential,
  every sub-muscle, soreness, the week's change and a **growth-over-time graph** from the daily
  history the server keeps (`profile.muscleHist`, one row per career day, capped at 90, served by
  `GetMuscleHistory`). Drag with the mouse or a finger to turn the figure, or use the right stick;
  LB / RB step the groups, B closes; left alone it turns by itself.
- **Fight HUD:** a broadcast-style scoreboard showing:
  - separate HEAD, BODY and STAMINA bars, with permanent-damage caps;
  - status chips (DAZED, IN DANGER, OUT ON HIS FEET);
  - the round timer, hit markers and crowd reactions;
  - commentary, corner advice and a tale of the tape.

  Phones get a compact strip and touch pads.
- **Settings:** UI scale, music and SFX volume, screen effects (blur, colour drain, flashes), camera
  shake, graphics detail, main menu at start, the fight control strip, and under Controls the Moves &
  Controls window (remapping), aim assist and controller vibration.

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
Every session also pays **training XP** (`profile.xp`, `Training.XPInfo`): a base for showing up
plus the session's stat and muscle gains, scaled by the grade. Level n needs 150 x n^2 XP in total.
XP is a progress counter for the result screen and never feeds the fight math.

The report's XP toast, gain popups, growth rows and the Muscle Progression screen are described
under Interface; the daily group history behind the screen's graph is `profile.muscleHist` (one row
of the seven groups per career day, logged by `Training.Perform` / `Sleep` / `PassDays` / `Migrate`,
capped at 90 rows, dropped when corrupt, served by `GetMuscleHistory`; no DataVersion bump).

**What the server trusts.** `FinishActivity` no longer takes the client's score at face value:
the client fires `Remotes.ActivityInput` once per press a drill accepted, the server counts them
(at most every 0.09 s) against its own clock, and the score is capped at
`0.5 + 0.95 * min(1, elapsed / t) * min(1, presses / n)` with `t` / `n` per minigame
(`PRESS_FLOOR` in Main.server.lua, about 60% of an honest perfect run) and at the client formula's
own maximum of 1.45. An idle client that waits out a drill and claims 1.5 gets a 0.5 session; a
macro has to put in the real time and presses to equal an honest perfect session, never beat it.
Roadwork and swimming are measured on the server frame by frame: a root that jumps more than the
humanoid's speed allows (or covers more ground in a second than it could) earns no distance, a
checkpoint only counts for a runner who covered the ground to it (`done = min(checkpoints,
distance / course)`), any pace bonus needs at least half the par time, and a session under 30 s
(swim 20 s) is sloppy. `Training.Migrate` also repairs the career counters (records, titles,
defenses, quality wins, sessions, gear condition, belts, regional, identity strings) so one corrupt
save value can never block the join.

**Drills and the control map.** Mitt work, the heavy bag, the double-end bag, shadow boxing and the
speed bag prompt and listen for the fight's own bindings (`Settings.Keymap()` through
`Keymap.Keys` / `Keymap.ActionText`): a custom map, mouse buttons and the pad's buttons and
right-stick flicks included; a drill's instructions carry `{jab}`-style tokens that read as the key,
button or touch name in use. MOVES & CONTROLS on the Hub's Training tab opens the moves list and
control map (`State.open.Controls`).

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

**Sparring** (the ring's picker: Light, Medium, Hard) is a real session, not a drill. The partner is
picked near your level (Light a little below you, Medium around you, Hard above you) and works at a
gym pace, throwing a lot more than a fight-night opponent would, so a session can be won, lost (on
the coach's card, or stopped by the coach) or drawn. Light and Medium have no knockdowns: the coach
calls time instead, and in Medium one such call ends the session. Hard allows knockdowns and the
coach stops it after a count you do not pass. Every result still trains you; a loss or a stoppage
is worth a little less than a win, and you have to throw punches to get anything at all.

## Fights and the KO model

**Getting into the ring.** A booked fight is fought LIVE from the Career Hub (early, with a confirm step,
or on fight night) or SIMULATED. Simulating needs a camp behind it: at least one camp day slept through
(a fresh offer cannot be simulated on the spot) and no more than one simulation a minute, so the purse
cannot be farmed by booking and simulating in a loop. The `Request` remote itself is rate-limited per
player (12 calls a second, bursts of 24; beyond that `{ throttled = true }`), a rejected action sends no
profile summary back, and look previews outside the creator / barber / locker are refused (full
rebuilds at most twice a second, head-only previews five times).

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
- **Controls:** shown on screen (tap **H**, or **View / Share** on a controller, in a fight); the
  full Moves & Controls menu on **Tab** (hold **View / Share**). The keyboard, controller and touch
  layouts, remapping, the special moves and the console options are in [Controls](#controls).
- **Fight nights:** weigh-ins, ring walks, a referee, judges' scorecards and a crowd. The venues are
  a community centre, a club arena, the Grand Arena and the National Stadium for title fights. The
  big venues have fight-night lighting, LED screens, broadcast cameras and a walkout stage.

## PvP: player vs player

Two players in the same server can box each other with their own boxers: the same engine, punches,
knockdowns, referee, judges and HUD as a career fight, with the stats of each player's profile.

**Starting a bout.**
- **Challenge:** walk up to another boxer and press **T** (**Y** on a pad, tap on touch), or open the
  PvP panel (**P**, **D-pad right**, the **PVP** button or the Career Hub's **PvP** tab) and pick a
  boxer from the list. Choose **Sparring** or a **Ranked Bout** of 3 or 6 rounds.
- The other player gets a popup for 20 seconds: **ACCEPT** / **DECLINE** (keys **Y** / **N**, pad **A** /
  **B**, or the buttons). You can't challenge someone who is training, in the ring, at the barber, in
  a queue or already asked; one challenge at a time, at most one every 4 seconds, and a declined
  challenger waits 30 seconds before asking the same player again.
- **Find Match** (in the PvP panel) queues you for a ranked 3-round bout. It pairs the two closest
  PvP ratings; the accepted gap starts at 150 and widens every second, and after 30 seconds anybody
  in the queue is a match.
- Both players see a **MATCH FOUND** screen (both boxers, records and ratings) for 4 seconds, then
  they are taken to their own arena (the City Club for ranked bouts, the sparring ring for spars) and
  brought back to the gym afterwards.

**Sparring vs ranked.**
| | Sparring | Ranked bout |
|---|---|---|
| Rounds | 2 x 45 s | 3 or 6 x 60 s |
| Damage | lighter (x0.5), headgear | full |
| Knockdowns | none: the coach calls time | yes, KO / TKO / decision |
| Record | none (counted as a spar) | PvP record W-L-D, KOs, rating |
| Reward | - | small purse ($400 win / $200 draw / $100 loss) and a little fame |
| Face marks | a light carry-over | like a career fight |

**What PvP never touches:** the career record, training camps and booked fights, injuries,
concussion trauma and suspensions. Only the normal face-damage carry-over follows you home. The
fight's training gains are not awarded either (spar the gym's partners for those).

**Rating.** Every profile gets a PvP rating (Elo, starting at 1000, K 40 for the first 10 ranked
bouts and 28 after) and a rank name (Rookie, Contender, Prospect, Veteran, Elite, Champion). Ranked
results move both ratings by the same amount in opposite directions.

**Farming protection.** The same two players can't start another ranked bout for 90 seconds. Within
24 hours, the second ranked bout against the same opponent pays half (rating and rewards), the third
a quarter, and from the fourth on nothing. The server keeps the last opponents per profile (at most
20) for this.

**Leaving, resetting, dying.** In a ranked bout after the first bell, the player who leaves the
game, resets or dies loses by forfeit (method "Forfeit"); the other player wins and both records are
saved (the leaver's before his leave save). Before the first bell, or in a spar, the bout is just
called off. The reset button is locked during ranked bouts, like career fights.

**Security.** The clients only send inputs. Damage, knockdowns, scoring and results are decided by
the server; every fight message is rate-limited (30 a second per player, get-up presses 15 a
second), the target of a challenge is looked up on the server by UserId, and both players are
checked again (free, alive, not training) when a challenge is accepted and when the match starts.

**Saves.** PvP data lives in `profile.pvp` (`rating, peak, w, l, d, ko, koLoss, bouts, spars,
recent`). Old saves have none; it is created on the first PvP bout and every read is nil-safe.
`DataVersion` is unchanged.

**Spectating** is not built in: the arenas are private instances far from the gym.

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
