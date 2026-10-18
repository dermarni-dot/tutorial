# Become a World-Class Boxer

A Roblox boxing career game, written entirely in procedural Luau. You create a boxer, train in a gym,
eat, rest and spar, take fights from the amateurs up to world title nights in big arenas, earn money
and fame, buy homes and gear, and upgrade your gym. Nothing in the world is an uploaded model: the
city, the gyms, the arenas, the equipment and every character are built from code when the server
starts. The boxers themselves are the standard Roblox R15 body with Blender-modelled muscle-tier body
parts, the classic head with classic faces, and Blender-modelled hair cards.

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

### Bodies and faces: nothing to switch on
The bodies (the muscle-tier MeshParts) and the faces (Decals) are ordinary uploaded **Mesh** and **Image**
assets (`src/shared/BodyAssetData.lua`). The server loads the meshes with `AssetService:CreateMeshPartAsync`
and swaps them into the rig; the faces are plain Decal textures. They need no Editable APIs and no ID
verification. Like the hair, they belong to the group, so **publish the place under the group** (see
[Asset hair](#asset-hair)). A mesh that fails to load keeps the default R15 part; an id of 0 means the
default part / the engine's classic smile.

### Hair tinting and cap painting (EditableImage / EditableMesh)
Only the asset hair's per-boxer tint and its scalp-cap painting (and its generated fallback hair) use the
Editable APIs. In a **published** game these need:
- **Game Settings > Security > Allow Mesh / Image APIs** turned on for the experience.
- An **ID-verified** creator account (Roblox requires it for EditableMesh / EditableImage in live games).

Studio play works without either. Without them every boxer keeps the part-built round-1 hair (fully
animated, nothing breaks, a warning is logged once); bodies and faces are unaffected. Under memory
pressure AnatomyClient first lowers the hair's detail level and returns far-away characters to the
round-1 hair. The training screen's anatomical body map is painted into an EditableImage too, and falls back
to plain frames the same way.

Players can lower the hair's detail in **Settings > Graphics detail** (Auto / High / Medium / Low; see
[Performance](#performance)). `Config.Anatomy.enabled = false` (in `src/shared/Config.lua`) switches the
client-built hair off for everyone; budgets (full-detail characters, ranges, per-frame build time) are set
in the same table.

### Saving (DataStore)
Careers are saved with DataStoreService in the store `Config.DataStoreName` (`WorldClassBoxer_v2`).
- **Published game:** saving works as is.
- **Studio:** turn on **Game Settings > Security > Enable Studio Access to API Services** to save.
  If it is off, Studio plays a session-only career and never writes anything.
- **Failed load:** if a DataStore read fails when a player joins, the server keeps retrying. The
  player sees "Couldn't reach Roblox's save servers. Retrying..." and nothing can overwrite the real
  career. After about two minutes of failures, the player is kicked with a clear message.
- **One server at a time:** the saved career carries a session lock (which server is playing it and
  when that server last saved). A player who hops to another server while the old one is still
  writing the leave save waits on the loading screen until it lands (at most about 30 seconds: the
  lock of a server that died is taken over after that, and one older than 3 minutes is ignored).
  Every save refreshes the lock, a heartbeat keeps it fresh through long fights without saves, and
  the leave save, the shutdown saves and a player who gives up on the loading screen hand it back.
  The leave save is the session's last write. Every save also carries a save counter, so an older
  copy never overwrites a newer one: if a newer save from another server still lands, the next save
  here is refused and the player plays on from that newer copy, with a toast "Your career was
  updated from another server." The progress made on this server since the join is replaced by
  that copy, and the newer save is never rolled back. If that re-read fails as well, the player is
  asked to rejoin.
- **Saved world size:** retired AI boxers are pruned from the saved world. The game keeps those the
  career still refers to (fight history, offers, belt holders) and the 40 most recently retired
  rivals the player fought, so a long career's save stays small.

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
| Run | hold Shift | click the left stick (L3): until the stick is back in the centre | RUN (left of the jump button): until you stand still |
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

**Character creator.** Seven steps: Name, Face, Skin, Hair, Body, Gear and Style.
- **Moving between steps:** the step bar under the title (click a step to jump to it), **BACK** /
  **NEXT**, or **LB / RB** on a controller.
- **Presets first:** each step opens with them. The classic faces (a grid of face swatches, each drawn with
  its own texture on your skin tone), skin swatches, hairstyle cards with a little head wearing each style
  (filtered by Short / Fades / Curly / Locs / Long), body types, gear kits and boxing styles.
- **Main controls:** the four to six that matter most, each with a one-line hint. **ADVANCED** opens
  every other slider of that step.
- **UNDO** (also **Ctrl+Z**, or **Y** on a controller) steps back through the last 20 changes. A whole
  slider drag counts as one change.
- **RESET** puts the current step back to its defaults, and **RANDOM** randomises it. On the first
  step, RANDOM rolls a whole new look.
- **Colours** are swatch grids, with the picked colour ticked and named. A free colour wheel sits
  under Advanced.
- **Camera:** it frames the face on the face, skin and hair steps and the whole body on the others.
- **Face:** pick one of ten classic faces (the smile is the default); the step's preview cyclers show the
  fight moods and fight damage on your boxer. **Skin:** tone and finish (smoothness, sheen). **Body:** body
  type, height, division, weight and reach; training builds the muscle (the face sculpt, eye and body-shape
  sliders of the organic characters are gone with them).
  - Turn: drag the boxer (mouse or finger), use the arrows on the dock, or the right stick.
  - Zoom: the mouse wheel over the 3D view, the dock's - / +, or **LT / RT**.
- **Live preview:** every change shows on your boxer. While a slider moves, the preview goes to the
  server at most four times a second, and once more when you let go.

**Fights.** The default map (every key and button below can be changed in **Moves & Controls**):

| Action | Keyboard & mouse | Controller (Xbox / PlayStation) | Touch |
|---|---|---|---|
| Move | WASD | Left stick | Thumbstick |
| Run (in the ring: quicker footwork) | hold Shift | click the left stick (L3): until the stick is back in the centre | SPRINT (top left in the ring; a toggle) |
| Jab | Left click (or J) | X / Square | JAB |
| Cross | Right click (or K) | Y / Triangle | CROSS |
| Lead hook | F (or L) | B / Circle | HOOK (alternates hands) |
| Rear hook | R (or ;) | A / Cross | HOOK |
| Uppercut | T (or U) | RT / R2 | UPPER |
| Overhand | Middle click (or O) | tap RB / R1 (on the press; once you own a special move, on the release: RB held + a button is a special) | OVERHAND |
| Body hook | G | LB + B / L1 + Circle | BODY, then HOOK |
| Body shot (arms the next punch) | tap C | tap LB / L1 | tap BODY |
| Block (guard up / down) | tap B | tap LT / L2 | tap BLOCK |
| Slip left / right | Q / E | flick the right stick left / right | swipe BLOCK left / right |
| Dodge (roll under) | Space | flick the right stick down | swipe BLOCK down |
| Quick dodge | Shift + Space | click the right stick (R3) | hold BLOCK, then swipe down |
| Parry | V | D-pad up (or flick the right stick up) | swipe BLOCK up |
| Pivot left / right | double-tap A / D (or Z / X) | D-pad left / right | swipe CLINCH left / right |
| Counter jab | hold Q + left click | flick left, then X / Square | a slip on BLOCK, then JAB within half a second |
| Counter cross | hold E + right click | flick right, then Y / Triangle | a slip on BLOCK, then CROSS within half a second |
| Clinch | Ctrl | D-pad down | tap CLINCH |
| Special moves | 1 - 9 (in the menu's order) | hold RB / R1 + a button (below) | the gold pads left of the punches |
| Show / hide the controls strip | tap H | tap View / Share | - |
| Moves & Controls menu (pauses a solo fight) | Tab in a fight, ` (under Esc) anywhere | hold View / Share | MOVES (top left) |
| Get up after a knockdown | mash Space | mash A / Cross | tap the panel |

How the conflicts with the old map were resolved: the body modifier moved from Shift to **C** (Shift is the
sprint and the quick-dodge chord), block from F to **B**, parry from R to **V**, roll from C to **Space**
(the dodge), the overhand from 6 / O to the **middle mouse button** (O still works), the pivots from Z / X
to a **double tap of A / D** (Z / X still work), and the number row **1 - 9** now throws the special moves
(the old letter alternates J / K / L / ; / U / O stay as second keys). The fight camera is the broadcast
one, so the mouse buttons never turn the camera in a fight: left and right click are free to punch.
**Tab** is Roblox's player list everywhere else (the list takes the key and swallows it), so a fight
hides the player list for its duration and takes Tab for the Moves & Controls menu; the backquote key
**`** opens the menu anywhere, in the ring or out of it. Around the gym and the city you walk (6.5 studs/s, a
brisk 1.7 m/s at the boxer's scale; `Config.TownWalkSpeed`) and **Shift** runs (16, `Config.TownRunSpeed`); in the
ring it is quicker footwork while held (to cut him off or get off the ropes): the server speeds your
feet up by a third, not while you punch or block, and charges stamina for every second you move with it
(none comes back meanwhile; it stops when you are down to your last 15 %). On a pad a click of the left
stick (L3) does the same, in the ring and out of it, until the stick is back in the centre or you click
again. On touch the round **RUN** pad left of the jump button runs you round the gym and the city (lit while
on; it stops once you stand still after running, or on a second tap; it is not there in a fight, a drill or
the menus), and in the ring the **SPRINT** pad (top left, next to MOVES) turns the quicker footwork on and
off (the bell, a knockdown or the menu turns it off). Every device has both, so touch players cross the
town as fast as anyone and a PvP bout is even. The key strip shows the sprint's key or button too (SPRINT,
lit while it is on).

**Chords and double taps.** A chord is "hold the first key, press the second" (Shift + Space, Q + click).
On a pad a right-stick flick counts as held for half a second, so "flick left, then X" is the counter jab.
In the ring a flick **up** doubles as D-pad up (the parry), whatever that is bound to, unless you give the
flick a binding of its own; the **left-stick click** is the sprint (the ring's quicker footwork) and only
doubles as D-pad down (the clinch) when you bind the sprint elsewhere. The **right-stick click** is the
quick dodge (it used to double as the pivot; an unbound R3 still does), which leaves **LT + A** free: a
held guard throws the rear hook like any other punch. RB / R1 is both the overhand (tapped on its own)
and the special-move modifier (held while another button is pressed). Until you own a special move the
overhand goes on the press; from then on it goes when you let go of RB, so a chord can still claim the
button: RB + X check hook, RB + Y pull counter, RB + B liver shot, RB + A loaded overhand, RB + RT lead
uppercut, RB + LT Philly shell counter, RB + LB step-back counter, RB + D-pad up gazelle punch, RB + D-pad
down peek-a-boo rush (a chord for a move you do not own yet says LOCKED). **View / Share** does what the
map gives it (the controls strip by default; bind it to anything) and held for a second always opens the
menu. A double tap is two presses of one key within a third of a second; a
plain press of A or D still walks.

**Touch.** The punch cluster sits bottom right (HOOK / UPPER over JAB / CROSS, OVERHAND and BODY on top),
the unlocked special moves in a grid of gold pads left of it (up to three a row, never up into the
scoreboard), BLOCK and CLINCH on the left edge above the thumbstick, and MOVES and the SPRINT toggle
under the left board.
Every pad is at least a fingertip (44 px) on screen. The head movement is in swipes, so nothing needs
more pads: **BLOCK** taps raise / drop the guard, a swipe left / right slips, down rolls under, up
parries, and holding it a moment before swiping down is the quick dodge; **CLINCH** taps tie him up and a
swipe left / right pivots; a slip followed by **JAB** or **CROSS** within half a second is the counter
jab / cross. The commentary ticker leaves the picture while the pads are up.

**Tap, don't hold.** Block, the body-shot modifier and the controls legend are toggles on every
device: a tap turns them on, the next tap turns them off. A press held longer than about a third of
a second still works as a hold and lets go when you release. Throwing a punch drops a tapped guard
(you cannot punch through your own gloves) and spends a tapped body modifier. The fight HUD lights
what is on: the **GUARD UP** and **BODY SHOT ARMED** chips above the ticker, the BLOCK / BODY key
caps and the touch pads.

**Moves & Controls menu** (main menu > CONTROLS, Settings > Controls, the Career Hub's CONTROLS button,
**`** anywhere, **Tab** in a fight, hold **View / Share** on a pad, the **MOVES** pad on touch, or
`State.open.Controls()` from any screen; the same key closes it again; while it is open the game's own
hotkeys H / P / M and the pad's D-pad shortcuts are off, so any of them can be bound). **It pauses a career
fight or a spar:** the server stops the round at the next quiet moment (nobody mid-punch, nobody down) and
everything waits (the clock, the AI, stamina and every recovery: it is for reading, not a breather;
ROUND PAUSED shows on the HUD and the window) until the window closes, or for at most a minute with it
open; a new pause needs three seconds of boxing after the last one. A **PvP** bout never pauses (the
window says THE FIGHT GOES ON). Four tabs, all mouse, touch and
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
  DEFAULTS (a rebind or a row reset keeps the list where it was, and on a pad the selection on the
  same cap). Movement, the get-up mash and the hold-to-open are fixed. Settings > RESET TO DEFAULTS
  resets the options only and keeps your key map.
- **Console:** aim assist (Off / Low / High), controller vibration on / off and strength, a test
  rumble. The same three settings sit in Settings > Controls.

The custom map is saved with the profile (`settings.ui.keymap`, through the same `SaveSettings`
request as every setting) and the server sanitizes it with `Keymap.Sanitize`: only known actions,
only valid keys for that device, at most two keyboard bindings and one pad binding each, nothing
reserved (Escape, the function keys, a plain press of W / A / S / D). Its cost never depends on what a
client sends: only the first eight entries of an action's list are read, and key names are checked
against the KeyCode enum read once (nothing a client sends is cached). Aim assist and the vibration
settings go through the same allow-list.

**Special moves** (`src/shared/Moves.lua`). Nine signature moves, each a real set-up followed by one or
two ordinary punches landed on the animation's own schedule (`FightMotion.SpecialHits`), so every
head and body reaction plays as for any punch. A move unlocks by **style and career tier** (its home
styles get it early, everyone a few tiers later) **or by a training milestone** (sessions on one
exercise); nothing new is saved, the set is worked out from the profile each time, so old saves just
work. A move newly unlocked by a promotion, a training milestone or a fight result is announced (NEW
SPECIAL MOVE, with its key or chord; after the fight when it comes during one). In a fight the key strip
(**H** / **View**) has a row of your unlocked specials with their keys (the strip packs itself to the
screen: one line of moves on a wide screen, two or three on a tablet or a phone, where a pad's button
names are the longest), and the touch pads are gold.
All specials share one cooldown and each needs its stamina: a press inside the cooldown says SPECIAL
READY IN 0.8s, one without the gas NO GAS FOR THE LIVER SHOT (the touch pads and the strip dim
meanwhile), and nothing is sent; if the server still refuses one (it decides), it says why and the
move you started is called off. The AI uses them too (its style's moves once it is past the amateurs),
each in the situation it is for; a gym partner keeps them for the harder sessions (none in a Light
spar, fewer in a Medium or Hard one than on fight night). A medium-or-worse shot taken cancels the
punches you have not thrown yet.

| Move | Home styles (tier) | Anyone from | Or train | What it does |
|---|---|---|---|---|
| Check hook | Out-boxer, Counter puncher (Local Pro) | International Contender | 10 Agility Ladder | Lead hook as he steps in, then a pivot out: a counter when it catches him punching, an angle for the next shot |
| Philly shell counter | Counter puncher, Boxer-puncher (Regional Champion) | Top 10 Ranked | 12 Shadow Boxing | Shoulder roll (head shots slide off for a third of a second), then the cross; what it rolls makes the cross a counter |
| Pull counter | Counter puncher, Out-boxer (Regional Champion) | Top 10 Ranked | 10 Double-End Bag | Lean back out of a straight punch, land the right hand as he resets |
| Liver shot | Swarmer, Slugger (Local Pro) | International Contender | 12 Heavy Bag | Dipping left hook under the elbow; a clean one folds a man a beat later even when his body is far from done |
| Gazelle punch | Slugger, Swarmer (National Champion) | Title Challenger | 10 Jump Rope | Leaping lead hook from outside jab range (the root leaps 1.2 studs): long reach, big power, easy to see coming |
| Peek-a-boo rush | Swarmer (National Champion) | Title Challenger | 15 Mitt Work | Bob and weave in (slipping head shots), then a left and a right hook on arrival |
| Step-back counter | Out-boxer, Boxer-puncher (Regional Champion) | Top 10 Ranked | 10 Treadmill | Two steps back (everything misses), the cross reaches further as he follows |
| Loaded overhand | Slugger, Boxer-puncher (Amateur) | National Champion | 8 Heavy Bag | The slugger's big one: a dip loads the back leg, then the overhand with the whole body behind it; two thirds lands through a block (the everyday overhand: half), harder knockdown odds |
| Lead uppercut | Boxer-puncher, Swarmer (Local Pro) | International Contender | 10 Speed Bag | A short left uppercut with no wind-up to see; lands bigger on a rolling head |

Each move has its own stamina cost, accuracy and damage multipliers, knockdown-odds multiplier and a
cooldown (1.4 - 2.6 s) on the server; the act strings are `special|<id>|<hand>|<windup>|<power>`. Only
the counter jab / cross come out of a slip's recovery (once per slip), whatever a client claims.

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

Every boxer is the standard Roblox R15 body: Blender-modelled muscle-tier body parts that change as he
trains, the classic head with a classic face, his own hair and his gear.

**How a character is made** (server, `src/shared/Builder*.lua`).
1. A HumanoidDescription with empty body-part ids (the engine's default parts), `BodyTypeScale = 0` and
   `ProportionScale = 0`. Only Height (inches / 70), Width / Depth (the frame: `Config.BodyTypes` width /
   depth; women x 0.92 / 0.94) and Head (the frame's head share x 0.942: a 0.927-stud head on the Athletic
   man) scale it. Training never widens the frame: the tiers carry the muscle. `Builder.ScaleKey` re-applies
   the description only on a real change.
2. `BuilderTiers` swaps each of the 14 non-head parts for its tier's MeshPart (`Humanoid:ReplaceBodyPartR15`),
   only when that part's tier changed (one part replicates). See **Body** below.
3. `BuilderHead` swaps the default head for the classic head (a Part with the Head SpecialMesh) once and gives
   it a Decal `face` (not for a player wearing their avatar's face: see **Hair & faces from the player's
   avatar** below). The head sits on the Neck pivot (no neck lift: the tier torso has no neck stub).
4. The layers on top: the round-1 hair (the fallback under the asset hair), the beard, trunks, boots,
   gloves / wraps, robe, headgear, damage marks and sweat.
5. `LookData` (a compact JSON attribute) carries what the clients build the hair from (`headShape =
   "classic"`, the rig, the hair look). Only the hair is built on the clients (AnatomyClient, Hair section).

**Body: the muscle tiers.** Five tiers per part (1 lean, 2 toned, 3 athletic, 4 muscular, 5 elite), modelled
in Blender at the game's proportions (`tools/body`, `tools/body/CONTRACT.md`; uploaded meshes in
`BodyAssetData.lua`). Each part reads the muscles it carries (`BodyTiers.MAP`):

| Part | Muscles (weight) |
|---|---|
| UpperTorso | pecs .22, upper chest .14, lats .18, upper back .10, traps .10, abs .14, obliques .06, serratus .06 |
| LowerTorso | lower abs .25, obliques .15, glutes .40, lower back .20 |
| Upper arms | biceps .34, triceps .34, front delts .10, side delts .16, rear delts .06 |
| Lower arms | forearms |
| Upper legs | quads .55, hamstrings .30, glutes .15 |
| Lower legs | calves |
| Hands / feet | their forearm's / calf's tier |

A muscle's level is its value / 100 x (0.55 + 0.45 / the frame's potential) (the rule the physique uses:
a maxed Lean frame still looks trained, a Heavyweight frame still out-sizes it; women x 0.8). Tier 2 starts
at level 0.18, tier 3 at 0.36, tier 4 at 0.56, tier 5 at 0.78 (an Athletic frame: 76 of its 95 cap), with a
0.03 hysteresis so a part never flickers at a boundary. A part jumps straight to its tier (several at once
when a group grows a lot). NPCs get their tiers from their own builds.

**How a part is swapped.** One template per (tier, part) is made per server with
`AssetService:CreateMeshPartAsync` (in the background from boot; a failure keeps the default part and is
retried after 2 minutes) with its RigAttachments and accessory attachments at their part-space positions,
an `OriginalSize` (the mesh's bounding box) and an `OriginalPosition` per attachment. The engine scales a
replaced part "as normal" (from its OriginalSize by the humanoid's scales); BuilderTiers then checks the part
ended at exactly OriginalSize x the ratio the default part had (its Size / OriginalSize) and re-aims the
joints at the attachments, so a part is scaled once, never twice (the head swap is guarded the same way).
Welds that held on to the old part move to the new one, and `HipHeight` is recomputed from the legs. The
model attribute `BodyTiers` (one digit per part, 0 = a default part) tells the clients the rig changed.

**Faces.** Ten classic faces to pick from (smile, grin, smirk, confident, cool, happy, wink, determined,
focused, stern; `look.face.key`, saved and sanitised: old saves get the smile) and seven mood faces (angry,
grit, surprised, tired, hurt, dazed, KO). FaceFX swaps the Decal's texture by mood (`BodyAssetData.expressions`):
a hit shows the hurt face for 0.4-0.9 s, a knockdown the dazed face, a KO the KO face, the server's Expr
attribute its mood (pain, dazed, effort, happy, anger, fatigue, ...), heavy work the grit face, a spent
fighter the tired face; neutral is his own face. A mood whose face is not uploaded keeps his own face.

**Beards** stay as 3D shells on the classic head (the way a beard accessory sits on a classic face), with
the moustache in the gap the classic faces leave between the eyes and the mouth.

**Gear** is sized from the tier parts' own boxes (the meshes' bounding boxes at the boxer's scale) and
placed at their joints: gloves from the forearm's measured girth (`tiers[n].fit`) at the wrist joint (the arm
axis moves out per tier), wraps at the wrist joint and over the palm, the waistband from the waist joint,
trunks, boots, robe and headgear from the part sizes.

**Hair.** 30 styles plus bald across five hair types (straight, wavy, curly, kinky, coiled). They
include fades from skin to high (as gradients), crops, curly tops, afros, 360 waves, twists,
cornrows, box braids, dreadlocks, long hair, ponytails and wolf cuts, with sliders for volume, curl
size, frizz, density and length. Dyes come as tips, streaks, ombre or split. Hair and beards grow a
little every in-game day. HairFX swings long hair, locs and braids and bounces curly volumes (tested against
a proxy of the body's boxes), and hair that reaches the canvas in a knockdown rests on it. Sweaty hair
turns heavier and darker.

Most styles are drawn with **asset hair** (see [Asset hair](#asset-hair)); every other style, and any
style whose assets fail to load, keeps the generated hair, laid on the classic head's own shape
(`AnatomyHairKit.CLASSIC`, a rounded cylinder).

**Hair & faces from the player's avatar.** A player's boxer wears the hair and the face of that player's own
Roblox avatar on the game's muscle-tier body (`src/shared/AvatarLook.lua`, `Config.AvatarLook`). NPCs always
wear the game look.
- The server fetches the avatar once per player and session (`Players:GetHumanoidDescriptionFromUserId`,
  pcall'd, in the background: the boxer is built with the game look at once and rebuilt when the avatar
  arrives; a failed fetch is retried after 20 s, doubling up to 10 min). Only `HairAccessory` (every id, at most
  8), `Face` and `Head` (a Dynamic Head, which carries its face) are copied into the boxer's
  HumanoidDescription: never the avatar's body parts, scales, clothes or other accessories. The engine loads
  and attaches the hair accessories (`ApplyDescription`). The avatar choice is part of `Builder.ScaleKey`, so
  the description is re-applied only when the avatar or the setting changes, never on every cosmetics run.
- With avatar hair, the model carries `AvatarHair = true`: no round-1 hair parts (an empty sealed `Hair`
  folder), and `LookData` gets `hair.avatar = true` (it moves the HairSig), so the clients build no asset or
  generated hair. An avatar without hair gives a bald boxer. The beard is the game's, as before.
- With an avatar face or Dynamic Head, the model carries `AvatarFace = true`: the classic head swap and the
  face decal are skipped (the engine's head and face stay), there is no `FaceKey`, and FaceFX's mood faces
  are off for that boxer. An avatar with neither keeps the chosen classic face. With avatar hair on the classic
  head, the accessories are re-welded to the classic head after the swap (`BuilderHair.FixAccessories`).
- Headgear and hoods hide the hair accessories whole (their Handle's `Transparency`, restored afterwards, the
  same `HGHidden` / `HGBaseT` attributes as the built hair).
- The setting "Use my avatar's hair & face" (saved as `appearance.avatar`, default on; old saves get it on) is
  in the creator (hair and face pages), at the barber (free) and on the Settings screen (`SetAvatarLook`). Off
  = the game's hair styles and faces exactly as before.
- If the avatar's items fail to load (offsale, deleted, moderated), `ApplyDescription` is retried without
  them: the game look, and the avatar is tried again after 10 minutes. `Config.AvatarLook.enabled = false`
  turns it off for everyone; `hair` / `face = false` keep that part on the game look.

**Damage and condition.** Black eyes, cuts, bruises, swelling, a bloody nose and a split lip show as simple
overlays on the head at the classic face's features (translucent marks, blood as Beams); a damage layer
uploaded as a full-face decal (`BodyAssetData.damage`, optional) is shown instead, faded by the damage.
Rib bruises show on the torso. Face damage persists after a fight (stages: fresh, light, moderate, heavy,
severe) and heals over in-game days. Sweat shines the skin.

### Asset hair

Hair cards (`tools/hair`) replace the generated hair for these styles:

| Family | Styles (types) |
|---|---|
| Fades and short | Buzz Cut, 360 Waves, Low / Mid / High / Taper / Burst Fade, Fade, Crew Cut, Caesar Cut (straight and wavy get a combed crop top, curly / kinky / coiled a sponge-curl top) |
| Afro | Afro (Kinky, Coiled, Straight, Wavy; a looser Curly version), High Top |
| Locs | Short Dreads, Dreadlocks, Twists |
| Braids | Braids, Box Braids, Cornrows |
| Long | Long Hair (Straight; Wavy has its own cards) |

Everything else keeps the generated hair: Bald, Short Curly, Curly Top, Long Curly, Messy Hair, Slick
Back, Undercut, Mohawk, Ponytail, Wolf Cut, Modern Athlete, Textured Crop, and Long Hair on curly types
(which AnatomyHair draws as long curls).

**How it is drawn.**
- **Meshes** are uploaded `Mesh` assets, one per piece (at most 16 a style), built in the game's
  nominal head space. The client loads them with `AssetService:CreateMeshPartAsync` and welds them to
  the Head.
- **Skull fit:** each piece is sized to the head (width, crown, front and back of the head's field, against
  the organic skull the cards were modelled on) and to the Head part. On the classic head (a rounded
  cylinder 1.2 nominal studs wide, where the cards' skull was 0.77) the four extents give x 1.567 / 1.015 /
  1.224; matched only there the scalp cap sank up to 0.141 nominal studs into the head's upper corners, so the
  classic head takes `HK.CLASSIC_FIT` on top (x 1.06 / 1.20 / 1.20, 0.06 down): the cap's worst point is
  0.055 under the surface (the top corners), its middle 0.066 above it, and every card piece's 10th percentile
  is outside the head (`lune run tools/sim/fit_classic_hair.luau`).
  Hanging pieces stretch with the hair length; volume pieces grow outward from the scalp with the
  volume slider.
- **Textures** are greyscale strand atlases with alpha (`Image` assets). The client tints them per
  boxer in an EditableImage with the generated hair's own palette: darker roots, lighter tips, dyes,
  highlights and greying with age. Dark colours keep their strand contrast.
- **The scalp cap.** One shared cap mesh carries the short hair of every cut. Its texture is painted
  per boxer: a strand tile (`short` for straight / wavy, `shortcoil` for curly types, `waves` for 360
  Waves) times the style's own coverage. That coverage uses the same fade height, hairline type,
  line-up and growth as the generated hair, plus a barber's line round each ear. Fades thin the tile's
  strands as they go down. Fur shells over the cap give the top its depth.
- **Animation:** HairFX swings and bounces the cards exactly as it did the generated pieces.
- **Sharing:** NPCs share their tinted images by hair colour. You, your opponent and previews keep
  their own, so sweat can darken them.

**Fallback.** Whenever a style has no assets, an asset fails to load (permissions, moderation,
network), an image cannot be made, or Editable images are unavailable, the same build draws the
generated hair instead. Nothing is lost:
- A failed id is retried once a minute later, and boxers already drawn with the fallback are rebuilt
  then.
- Below that, the round-1 part-built hair still applies.
- `Config.HairAssets.enabled = false` turns asset hair off for everyone.

**Requirements.**
- The assets belong to the group (creator id 524947123). Roblox only lets an experience load
  group-owned meshes and images when the **experience is owned by the same group**, so publish the
  place under the group.
- The Editable APIs must be on for the tint and the cap paint (see [Hair tinting and cap painting](#hair-tinting-and-cap-painting-editableimage--editablemesh)).
- New images can take a while to pass moderation. Until they do, those styles fall back.

**Rebuilding the assets.** Run each family's builder in Blender's Python (bpy 4.2:
`python build_fades.py`, `build_afro.py`, `build_locs.py`, `build_braids.py`, `build_long.py`). Then
`python publish.py` uploads only what changed (cached by file hash in `tools/hair/uploaded.json`)
and rewrites `src/shared/HairAssetData.lua`. `tools/hair/CONTRACT.md` is the format. The `.blend`
files are not committed; each builder writes them to `tools/hair/blend/`.

**Cost.**
- About 8-27k triangles a head: the cap is about 7k, and locs are the most.
- Image memory: 4 MB per 1024² texture. Texture size follows the detail level (1024² full, 512²
  medium, 256² low; fur shells at half size), and NPCs share theirs by colour.
- The tint and cap paint take 0.5-2 s of time-sliced CPU per build in the simulator (lune).

**Not verified in Roblox.** The renders and tests come from the offline simulator and Blender, not
Studio, so check these in Studio:
- Alpha sorting across the overlapping card pieces.
- Whether card alpha needs the parts' 0.02 Transparency (`Config.HairAssets.alphaTransparency`).
- The `.mesh` UV direction. If strands show upside down, set `HairAssetData.flipV` /
  `Config.HairAssets.flipV`.

## Animation

Everything is procedural, driven on each client by `Animator.client.lua` and the `Anim*` modules.
- **Fight styles:** each style has its own stance, bounce, guard and idle life, and a per-boxer
  persona keeps two boxers of one style from moving alike. The styles are Out-boxer, Swarmer,
  Slugger, Counter puncher and Boxer-puncher.
- **Footwork:** feet plant in the world and never slide. Inside the ring: step-drag shuffles,
  pivots, backpedalling and side steps. Outside it: walk, jog, run and sprint gaits picked by the
  speed alone (the town walk always walks, the Shift run always runs). The shoes roll over their real
  soles (heel strike, toe spring, never into the floor); a walker pushes off up onto the toes with the
  knee bending, a runner falls freely through the flight and sinks into a bent knee on each landing, the
  arms swing close to the body (a runner's from beside the hip to the chest, elbows near 90), the feet
  land close to one line, sharp reversals pivot on a planted foot. On ramps the shoe lies along the
  slope; on stairs each shoe lands on one tread, clear of the risers.
- **Punches:** kinetic chains (legs, hips, shoulders, fist), aimed at the opponent's chin or body:
  - jab: fast and snappy;
  - cross: hip turn and full extension;
  - hooks: an arc round the body;
  - uppercuts: leg drive;
  - body shots: change level at the knees.
- **Defence:** slips, rolls, parries, pivots, the shell and clinches.
- **Hit reactions:** light head snaps, medium stumbles, heavy leg wobbles and critical buckles, each
  directional.
- **Knockdowns:** flash, forward, side, on the ropes and in the corner (the back comes to rest against
  the post and its turnbuckle pads).
- **Knockouts:** one-punch timber falls, delayed KOs, standing KOs held up by the referee, face-first
  and backward collapses. KOs play in slow motion.
- **Get-ups:** staged for each kind of fall.
- **Gym poses:** every exercise and flex has its own pose, and coaches, cornermen and members train
  around you.
- **Crowds:** distant and off-screen figures update less often. A background figure that stands still
  and moves slowly updates at half rate from 45 studs and at a sixth of the rate off screen. Walkers,
  punches in flight, fighters and your own boxer are never slowed this way.

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
  good reps, quality, time, heart rate, calories; the set, rep, good-rep, quality and time tiles each
  carry a fill bar) next to a "muscles worked" card: an anatomical body map lit by
  `Config.ExerciseTargets`. A phone too narrow for the card gets a strip over the panel instead (a
  small map and the muscles' names). The report that follows shows the grade, every muscle that grew
  (under NOW / TONIGHT / LEVEL: the 65% of the gain that lands at once, the rest that lands when you
  sleep, and the muscle's level now; the gain popups, the report's side card and the Muscle
  Progression screen show the same split), every stat that rose (old -> new),
  the pump / soreness / sweat / veins / fat chips and the body map re-lit by the growth (on a phone,
  beside the grade; the header steps up under the record line so the first growth rows show without
  scrolling). It stays up until CONTINUE / CLOSE (B), or until a window opens over it or a bout takes
  the player (a PvP match found from the queue closes it and gives the camera back). On top of it:
  a **+XP toast** that counts up (training levels, level-ups), and a column of **gain popups** (one per stat and per
  muscle part, old -> new) that slide in one after another. Where a column would run into the panel
  (a phone, a 1024 tablet) the toast shrinks into the top-right corner (a shorter caption, the card
  sized to it at the text floor) and the popups become one row
  of chips in the band above the report (stats first, "+N more" when they do not all fit; the
  report lists every one). FLEX strikes a pose; MUSCLES opens the Muscle Progression screen on the
  parts that just grew. On touch every drill and report button is a fingertip high (44 px), and the
  instructions name the drill's own buttons and the thumbstick instead of keyboard keys (the rope's
  called foot reads A / D on a keyboard, the D-pad on a controller and the button on touch). Names are
  never cut at the readability floor: the Hub's exercise cards list the stats they build strongest
  first and end in "+N more" where the card is narrow (the smallest phones take one column of
  cards), and the gain chips, the growth names and the cost chip are sized to their text.
- **Muscle Progression screen** (`MuscleScreen.lua`, Hub Body tab "3D MUSCLE VIEW", the "3D" button
  of every group row - finger-high on touch, with a sore group's soreness on its own line under the
  name - or MUSCLES on a training report): a rotating 3D figure (a frozen copy of
  your character in a ViewportFrame: his tier parts, face and hair) with tabs for Arms, Chest, Core, Legs,
  Shoulders, Back and Neck. The picked group lights up on the figure (neon shells over the region,
  the round-1 muscle overlays tint) and the panel shows its level against your frame's potential,
  every sub-muscle, soreness, the week's change and a **growth-over-time graph** from the daily
  history the server keeps (`profile.muscleHist`, one row per career day, capped at 90, served by
  `GetMuscleHistory`). Drag with the mouse or a finger to turn the figure, or use the right stick;
  LB / RB step the groups, B (Backspace) closes; left alone it turns by itself. Picking Back turns
  the figure round (Chest and Core turn it back to the front), and those one-sided groups sway
  around their side instead of spinning away. Closing it returns to the Hub's Body tab; another
  window opening over it (a drill, a store, the menu) closes it without bringing the Hub back.
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

The body shows the training through the muscle tiers (see [Characters](#characters)): every part jumps up
a tier as the muscles it carries grow, and back down with detraining. Body fat, definition, vascularity,
pump and soreness are tracked (and shown on the training screens) but no longer drawn on the body. The
trained body is classified into a physique:
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

**What the server trusts.** The session quality is the server's own number; the client's score is
ignored. `StartActivity` draws the whole drill on the server (`Training.DrillPlan`: every combination,
lift zone, cue, beat, rope cue and time limit) and sends that plan to the client, which plays exactly
it. The client sends every input its drill takes through `Remotes.ActivityInput` (`id, down, t` on the
drill clock, and an `@` marker when a segment starts). `FinishActivity` replays the stream through the
same judges (`ReplicatedStorage.Shared.DrillScore`, shared code: the drill the player sees and the
server's replay cannot disagree) and sets `quality = 0.5 + 0.95 * score`. Inputs must arrive as they
happen: one stamped ahead of the server's clock, more than 6 s behind it, or 3.5 s further behind than
the session's quickest input is dropped, so a stream written after the fact counts for nothing. Presses
with no drill behind them (no markers, the wrong keys, the wrong moments) score nothing, mashing costs
points (a stray beat, a jump between rope passes), and a reaction faster than 0.1 s counts as jumping
the cue. The replay also holds the stream to the drill's own pacing: every segment of the plan carries
its `gap`, the time the client waits between the previous segment's end and its start (the round
banners, the rests between rounds and sets, the beat after each combination or rep, a cue's lead-in;
`DrillScore.WAIT`, the same numbers `Activities.lua` waits). A segment the stream starts sooner is
started at the allowed moment instead, so whatever was pressed before it counts for nothing, and a
session handed in under 80% of the plan's quickest honest play (`plan.minTime`) is a sloppy session
that never counts as a record. A client that keeps the pacing and plays perfectly saves only its
reaction times: a perfect bot finishes the bench in 25 s (an honest perfect run takes 29 s), while one
that skips the banners and rests scores nothing. Roadwork and swimming are measured on the
server frame by frame. A step longer than a sprint can explain is a teleport, and more ground over 3 s
than the humanoid's speed (+15%) covers is a speed hack; either earns nothing and holds the next
checkpoint back for a second. Only a new closest approach to the next checkpoint (or pool end) counts
as ground covered, and a checkpoint needs 70% of its leg run that way: circling at the start or running
back and forth adds nothing. Par is the course at the humanoid's own speed (the shortest line, each
checkpoint taken at the edge of its 11-stud trigger), the pace (par / time) stops at 1.05, and a run
(or swim) quicker than 0.75 x par is sloppy. Nobody runs par itself: the grade is
`0.5 + 0.95 * (pace - 0.45) / 0.42` (clamped), so a clean line at full speed (pace ~0.85) is an S, a
decent run (~0.76) an A and a wandering one (~0.65) a C. Stamina sets the speed (and so the time a
session takes), not the grade; a session ended early is graded on the ground covered at that speed,
no better than a B. `Training.Migrate` also repairs the
career counters (records, titles, defenses, quality wins, sessions, gear condition, belts, regional,
identity strings) so one corrupt save value can never block the join.

**Drills and the control map.** Mitt work, the heavy bag, the double-end bag, shadow boxing and the
speed bag prompt and listen for the fight's own bindings (`Settings.Keymap()` through
`Keymap.Keys` / `Keymap.ActionText`): a custom map, mouse buttons and the pad's buttons and
right-stick flicks included; a drill's instructions carry `{jab}`-style tokens that read as the key
or button in use (on touch: the drill's own button). A drill's button names only the plain keys it
listens for (a chord or a double tap such as the pivot's `2x A` cannot reach a drill). MOVES &
CONTROLS on the Hub's Training tab opens the moves list and control map; closing it brings the
Training tab back.

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
- **Clinch:** a tie-up from close range holds both men for a moment, then the referee (the coach in a
  spar) breaks it. The pair slides to a clinch distance sized to both chests, so a heavyweight's deep
  chest holds them further apart.
- **Concussion:** builds with head damage. It slows punches and movement, lowers accuracy and
  defence, and blurs and drains the screen. It recovers between rounds and over days. Repeated
  trauma carries over the career.
- **Controls:** shown on screen (tap **H**, or **View / Share** on a controller, in a fight); the
  full Moves & Controls menu on **Tab** (hold **View / Share**, the **MOVES** pad on touch), which
  pauses a career fight or a spar. The keyboard, controller and touch layouts, remapping, the special
  moves and the console options are in [Controls](#controls).
- **Fight nights:** weigh-ins, ring walks, a referee, judges' scorecards and a crowd. The venues are
  a community centre, a club arena, the Grand Arena and the National Stadium for title fights. The
  big venues have fight-night lighting, LED screens, broadcast cameras and a walkout stage.

## PvP: player vs player

Two players in the same server can box each other with their own boxers: the same engine, punches,
knockdowns, referee, judges and HUD as a career fight, with the stats of each player's profile.

**Starting a bout.**
- **Challenge:** walk up to another boxer and press **T** (**Y** on a pad, tap the CHALLENGE prompt on touch), or open the
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

**Controls.** The fight's own (see Controls), the same on every device: touch players get every move
too (swipes on BLOCK / CLINCH for the head movement and the pivots, the OVERHAND pad, the SPRINT toggle
for the ring's quicker footwork). The Moves & Controls menu opens in a PvP bout but never pauses it
(THE FIGHT GOES ON), and the console aim assist only ever helps punches the server holds as pad input.

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

## Performance

One graphics level drives every client system, so phones and low-end PCs can drop work while a good
machine keeps the full look.

**The setting.** Settings > **Graphics detail**: Auto, High, Medium or Low. On Auto the row shows the
level Auto picked ("Auto: Medium"). The line under it reads the level in force and the live frame rate,
then what to do at that level ("Running at Medium · 58 FPS. If the game stutters, pick Low ..."; on Low it
says what Low leaves out, on Auto that Auto steps by itself). The choice is saved with the profile.

**Perf** (`src/client/modules/Perf.lua`) turns the choice into a level from 1 to 3. Every system reads
it the same way: `Perf.Level()`, `Perf.Pick(low, medium, high)`, `Perf.Changed` (fired with the new
level) and the client attribute `GfxLevel`. Picking High, Medium or Low fixes the level. Auto works
like this:

| | Auto |
|---|---|
| Start | High on desktops and consoles. Medium on touch devices: a phone (short side under 500 px) never climbs above Medium, a tablet can reach High |
| Step down | one level after 6 s under 40 FPS, 4 s under 25 FPS, or one 2-second window under 15 FPS. A device crawling under 4 FPS (window after window of nothing but quarter-second frames) steps down after three such windows |
| A cap is not a slow device | slow frames held back by a frame-rate cap (Roblox's own 30 FPS setting, a phone's battery saver) keep the level. Auto reads them as a cap when they come evenly paced and the frame's work would fit a 50 FPS frame: the scripts' span from PreRender to the end of Heartbeat, and the render thread's CPU and GPU time (`Stats.RenderCPUFrameTime` / `RenderGPUFrameTime`). Settings then says the device caps the frame rate (`Perf.Capped()`). Where the render times read 0, the scripts' span alone keeps Auto at Medium or above |
| Step up | one level after 20 s of smooth frames at 57+ FPS, never above where the device started. Not within 60 s of a step down; that wait doubles (up to 8 minutes) each time a climb has to be undone. After two undone climbs to a level, Auto stops trying it until the scene changes (the camera moves more than 1,000 studs: the gym, an arena, the city, the menu) or Auto is picked again |
| Not judged | the join (until 3 s after the game has loaded), single frames over 0.25 s (loading, a big build, the app in the background) and windows made mostly of them (unless three come in a row: a crawl), an unfocused window, the main menu's set being built, the boosted first builds of your boxer's and your opponent's meshes |
| After a step | 6 s for the systems to shed or take on their work before the next judgement |
| Other settings | a change to any other setting re-applies Graphics without moving Auto's level |

**What the levels change.** High is the full look. Medium and Low only take work away; they keep every
character, every piece of UI and all gameplay information. Your own boxer keeps High's animation and hair
settings at every level. Your opponent keeps High's distances too; below High his hair moves every second
frame. Both are built first. The bodies and faces cost the same at every level: they are ordinary MeshParts
and Decals the server builds (no client generation, no Editable memory).

| System | Medium | Low |
|---|---|---|
| Client-built hair (`AnatomyClient.DETAIL`) | 4 full-detail characters, full detail to 50 studs, low-detail hair to 160, 2 ms of build time a frame, every colour texture | 1 full-detail character, 30 / 140 studs, 1.5 ms a frame. NPCs' hair in vertex colours; you, your opponent and previews keep every texture |
| Character animation (Animator LOD bands) | full detail to 30 studs; every 2nd frame past 60, every 3rd past 90, none past 150; still background figures at half rate from 15 studs | 25 / 60 / 80 / 140 studs; still figures every 3rd frame |
| Faces (FaceFX) | the mood's face texture checked 12 times a second within 60 studs (the opponent and you at any distance): one compare per head, a swap is one local Decal write | the same (it costs next to nothing) |
| Hair (HairFX) | full rate to 20 studs, half rate to 45; swinging hair tested against a proxy of the body's boxes | 15 / 30 studs |
| Character lights (CharacterLight) | fill and rim light | fill light only |
| Full-screen effects (LightLevels) | no depth of field | no depth of field, bloom or sun rays (colour grades, blur and atmosphere stay at every level) |
| Fights (FightClient) | sweat / blood spray x0.75, 8 blood drops on the canvas, ropes in front of the camera checked every 0.1 s | no impact lights, spray x0.5, 4 drops, no blur pulse on a heavy shot taken, ropes every 0.16 s, the built-in crowd at 15 Hz |
| Arenas (VenueFX) | 2 key-light shadows, spot rays at 7 Hz, crowd bob budget 280 / 150 parts a tick | 1 key-light shadow, spot rays at 4 Hz, crowd budget 160 / 0, printed impostor rows behind the front row |
| Training screens (BodyMap, MuscleScreen) | muscle map painted at 1 image px per design px; the muscle viewer's shells breathe at 20 Hz | 0.75 px without the glow layer; shells hold still, the figure turns at 30 Hz |
| Main menu (MainMenu, MenuStage) | 20 dust motes; the set: 2 of its 4 light shadows, dust at about half rate, signs at 3/4 resolution | 10 motes; the set: no light shadows, no dust, signs at half resolution |
| Gym and city lights (WorldLOD) | shadows only from the lights marked ShadowKeep; small accent lights past 90 studs and mid lights past 220 off | no light shadows; accent lights off; mid lights past 110 and big fills past 170 off; parts under 4 studs cast no shadow |
| Signs (SurfaceGui / BillboardGui) | drawn to 3/4 of their distance at 3/4 resolution | half distance, half resolution (scale-only layouts, so nothing moves) |
| Particles and gym effects (WorldLOD, Ambience, GymVisuals) | continuous particles at 55%, none beyond 260 studs; gym dust x0.55; sun shafts drawn to 130 studs with 3 bounce lights (170 and 6 at High); 4 sweat puddles, gone at 45 studs | particles at 25%, none beyond 150 studs; no gym dust, sun shafts or sweat puddles |
| Gym motion (GymMirror, GymVisuals, Ambience) | mirror at 24 Hz; equipment moves within 120 studs, fans and timers within 130 | mirror at 15 Hz; 90 / 100 studs |
| City (CityVisuals) | Main Street crowd x0.75, 36 window grids, fans / pedestrians / cars move within 140 / 170 / 210 studs | crowd x0.5, 24 grids, 100 / 120 / 160 studs, the street at 20 Hz |

High is the full look: AnatomyClient's own defaults on Auto (`Config.Anatomy`: 6 full-detail characters,
70 / 160 studs, 2.5 ms a frame) and its "full" preset when High is picked by name (10, 90 / 200 studs,
4 ms); animation bands 45 / 110 / 170 / 230; hair 25 / 60; 3 arena key shadows, spot rays at 12 Hz, crowd budget 420 / 300; mirror at 30 Hz.
High also gains two savings nobody can see: the gym and city lights far beyond any view switch off
(an arena fight is 5,700 studs from the gym, whose 170 lights used to stay on through every bout), and
the gym's ambience loops pause while the camera is that far away.

**Bodies and faces.**
- A tier body is 14 MeshParts of 190-1,800 triangles (about 6.7k a body for the tiers; the classic head is the
  engine's own), uploaded Mesh assets the engine streams and instances like any avatar part: no Lua at run
  time on the clients, nothing generated, no EditableMesh / EditableImage memory.
- The server makes at most 70 templates (5 tiers x 14 parts) once, in the background from boot. A tier
  change swaps only the parts whose tier moved (one replicated part each); an unchanged build swaps nothing.
- A face expression is a local Decal texture write when the mood changes (the 17 face images load once).
- Retired with the organic characters: the per-client mesh generation of the bodies and heads (the "Time until
  every character's meshes are built" and most of the Editable memory in the tables below), the head's damage
  painting, BodyFX's blend shapes and the round-1 muscle parts (the gym members' part counts below are older).

**Server.**
- The fight venues' templates (8,600 instances in ServerStorage, about a fifth of the boot's Lua) are
  built 3 s after the server is up instead of in front of the first join (`Venues.New` still builds
  them at once if a fight ever comes first).
- Map and venue parts have CanTouch off (nothing listens to `.Touched`), and the posed gym NPCs skip
  the Humanoid state machine.
- Gym members' gear and round-1 hair are built at low detail when the clients draw their hair themselves
  anyway (decided once at boot by a probe EditableMesh on the server); without the Editable APIs they stay at
  medium detail. (Measured with the retired round-1 muscle layer: 10,703 -> 9,108 instances and 2,788 ->
  2,180 parts replicated to every join; the muscle layer itself, ~30-60 parts a boxer, is gone now.)
- Fighters slide by their root (one assembly move instead of `Model:PivotTo` of ~270 parts), and the
  10 Hz fight state message is a 42-byte buffer (64 B on the wire, was ~387 B).
- **StreamingEnabled is off**, and `default.project.json` now says so for Workspace, so a `rojo serve`
  into a new Studio place (where it defaults on) cannot turn it on. Measured in the simulator: at
  Roblox's default 1024-stud radius streaming withholds only the training camp (127 parts, about 2%),
  since the NPCs and the whole gym sit within 200 studs of the centre. At a 256-stud radius it saves
  12-19% of the join's instances, but VenueFX then fails in both a spar and a career fight (no
  `Anchors.RingCenter` yet), the gym's client-built dressing drops from 1,014 to 47 instances, the
  fight's start message carries instance references that can arrive missing, and about 40 one-shot
  scans in the client would have to become event-driven. Its real gain would be other players' fight
  arenas (1,500-3,100 instances each, 5,700 studs away): that needs Atomic arenas plus
  `RequestStreamAroundAsync` before the start message, and is left for later.

**Measured** (headless simulator, client Lua on a desktop CPU; a mid-range phone runs Lua about 3x
slower, a low-end one about 5x; GPU work is not simulated). This first table was measured when the
levels came in, before the per-system work above, so its Medium and Low rows show only the presets
and lights of that time:

| At the tier-1 gym floor, after the meshes are built | Low | Medium | High (picked by name) |
|---|---|---|---|
| Time until every character's meshes are built | 20 s | 74 s | 127 s |
| Character meshes / colour textures / Editable memory | 132 / 27 / 5.2 MB | 400 / 72 / 16.1 MB | 633 / 205 / 43.3 MB |
| Lights on / lights casting shadows (before WorldLOD) | 51 / 0 (90 / 4) | 71 / 2 (91 / 4) | 88 / 4 (91 / 4) |
| Particle emitters running / particles per second (before) | 6 / 1 (12 / 128) | 12 / 27 (12 / 128) | 12 / 128 (12 / 128) |
| Parts casting shadows (before) | 3,104 (5,587) | 5,577 (5,590) | 5,655 (5,655) |
| Client Lua per frame, ms (before) | 6.5 (7.0) | 7.0 (7.2) | 7.1 (7.1) |

| Measured since | Before | After |
|---|---|---|
| A phone (844 x 390) on Auto at the gym: mesh preset | desktop (6 full-detail characters, 70 / 160 studs, 2.5 ms a frame) | Medium (4, 50 / 120 studs at the time, 2 ms) |
| ... time until the meshes are built / Editable memory / live Editables | 134 s / 21.3 MB / 535 | 60 s / 12.1 MB / 281 |
| ... client Lua per frame once built | 11.9 ms (the builder still busy) | 9.6 ms |
| The gym floor's animation at Medium (Animator, Lua + engine ms a frame) | 3.23 | 2.33 |
| Blend shapes, a career fight's round 2 (AnatomyClient, Lua / engine ms a frame) | Low 1.16 / 1.84, High 1.15 / 1.75 | Low 0.91 / 1.51, High 0.86 / 1.41 |
| The Body tab's rebuild (training UI) | 355 ms | High 71, Medium 82, Low 17 ms |
| Your opponent's round-1 head at a spar's start (Low / High) | 16.0 / 13.5 s | 0.5 / 0.5 s |
| Main menu dust loop per frame, Low / Medium / High | 0.17 / 0.16 / 0.17 ms | 0.07 / 0.11 / 0.17 ms |
| Main menu set's shadow-casting lights, Low / Medium / High | 4 / 4 / 4 | 0 / 2 / 4 |
| Peak Editable memory through creation, a tour, training and a spar (Low / Medium / High) | | 15.6 / 45.5 / 71.3 MB |
| Server script start to its first yield | 0.36 s | 0.20 s |
| Hair's body maps built in the gym at Low (a tour up to all 25 members) | one for every Body build (62 in the full scenario, single parts of 5-7 ms in one frame) | 1, for the one member whose hair swings, in slices |
| The opponent's face blend shapes on Low / Medium | 14 Hz | 8 / 10 Hz |

The GPU savings (lights, shadows, particles, signs, depth of field) are not in these numbers.

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

Offline renders of the real generators and Builder, made outside Roblox with a three.js renderer. They show
the organic characters that the tier body and the classic head replaced (renders of the tier body and the
faces are made by `tools/body/build_body.py` / `faces.py`).
Lighting approximates Roblox's Future lighting, so expect small differences in Studio.

**`previews/final/`** shows the current characters, and holds every later pass's previews too. Its
`README.md` explains how they were made and lists every image in the folder (animation filmstrips,
review renders, interface and training screens, lighting, Graphics level comparisons).

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
| `perf_characters_low_vs_high.jpg` | Graphics levels: your boxer at High (the same at every level) and a gym NPC on Low before and after the optimization pass |
| `perf_gym_levels.jpg`, `perf_stadium_levels.jpg`, `perf_city_night_levels.jpg` | The gym, the stadium and Main Street before the optimization pass, after at High and after at Low |
| `perf_fight_hud_low_vs_high.jpg`, `perf_fight_hud_phone_low_vs_high.jpg`, `perf_settings_graphics_note.jpg` | The fight HUD at Low and High (identical), and the Settings Graphics note at each level |

**`previews/final/hair_assets/`** compares the hair before and after the asset hair: one sheet per look
(`hair_<look>.jpg`: 3/4, side, back, front), the generated hair above and the asset hair below, on the
game's own painted head. Both rows are Blender Cycles renders (`tools/hair/previews.py`, matte hair).
The after row is exactly what the client builds: the offline simulator ran the real `HairAssets.Build`
(placement, skull fit, cap paint and tint) on each look (`tools/sim/after_scene.luau`).

**`previews/rework/`** has the round-2 working renders, one folder per area: `R-anim`, `R-body`,
`R-hair`, `R-head`, `R-ui` and `integration-A`.

**`previews/round1/`** has the round-1 part-built characters, for comparison. Its `README.md` lists
them.

## Known limitations

- **The tier body and classic faces, not yet seen in Studio.** The swap, the scaling and the faces were checked
  in the lune simulator with a fake engine (`tools/sim/test_bodytiers.luau`), not in Roblox. To check in Studio:
  - that `ReplaceBodyPartR15` scales the tier part once (BuilderTiers corrects either way; a part visibly the
    wrong size, or joints off their attachments, means the engine did something else again);
  - the `HipHeight` BuilderTiers computes (feet on the floor), the `RootRigAttachment` at the LowerTorso
    centre (unverified against the live rig) and the Grip attachment's orientation (a held tool);
  - that the default head is swapped for the classic head (the Decal must show on its front) and that
    the classic head's shape matches `AnatomyHairKit.CLASSIC` (rounded cylinder, round 0.24 of 0.6: read off
    its silhouette, not measured).
- **Hair on the classic head.** The cards were modelled on the organic skull (0.77 studs wide nominal) and are
  mapped onto the classic head (1.2 wide) per axis (`HK.CLASSIC_FIT`): short cuts' scalp cap stands about
  0.05 studs off the head in the middle of its sides and still dips up to 0.04 studs into the head's upper
  corners; long hair and locs hang a little wider than before. A proper fix is a cap and cards modelled on
  the classic head.
- **No muscle definition or pump on the body.** The tiers are rigid meshes: fat, definition, veins, the
  post-workout pump and flexing are tracked but no longer drawn; a part jumps a whole tier at a time.
- **Faces don't animate** (no blinks or eye movement): an expression is a texture swap. Damage marks are simple
  overlays (no decals uploaded for them yet: `BodyAssetData.damage`).
- A much shorter boxer cannot always reach a much taller one's chin. When the smallest women punch
  up at a Balanced man, some overhands and uppercuts land under the chin. In an offline test of 200
  such punches, 31 missed or broke a quality check, against 30 before the neck was lengthened.
- **Clinch arms and heads.** The tie-up holds the chests apart, but its arms are fixed angles: the
  forearms and gloves sink up to about 17 cm into the partner's chest for the whole hold, and both
  men turn the head the same way, so the foreheads press into each other. Fighters keep High's detail
  at every Graphics level, so phones show it too. The fix is an arm aim at the partner's shoulder and
  upper back from the live distance, and a sideways offset so the heads pass (AnimFight's clinch
  guard).
- **Head-hook specials up close** (check hook, peek-a-boo, gazelle punch) put the lead glove into the
  opponent's chest for a frame or two (8-11 cm). The torso keep-out that cleared the body punches
  only runs for body-targeted punches.
- **Gym guard entry.** Going from the lie-up pose into the training guard, the lead forearm crosses
  the chest and its elbow sinks into the pec for about 4 frames.
- **Hair against ring parts.** Hair is tested against its own body and the canvas, not the ring:
  heavy locs can dip into a cover corner pad for a moment as the back lands against it.
- **Asset hair, not yet seen in Studio.** Everything about the hair cards was checked offline (Blender
  renders, the lune simulator), not in Roblox. To check in Studio:
  - card alpha and its sorting across up to 16 overlapping parts;
  - the `.mesh` UV direction (`flipV`);
  - the 0.02 part transparency the cards use for their alpha.

  Known looks:
  - long hair is sleek, sits close to the head and shows some card banding from behind;
  - the afro is on the small side, a little mushroom-shaped;
  - cornrows stand about 0.03 studs proud of the scalp (the clearance floor);
  - fades still show faint shell edges at the bottom of the gradient.

  Locs cost the most, up to 27k triangles a head with the cap.
- **Measured, not felt.** The Graphics levels' numbers come from the headless simulator on a desktop
  CPU (client Lua; a phone runs Lua 3-5 times slower). GPU work (shadows, lights, particles, depth of
  field) is not simulated, and the levels have not been timed on a real phone.
