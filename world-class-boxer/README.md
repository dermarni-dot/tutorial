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

### Organic characters (EditableMesh)
Characters are drawn with procedurally generated meshes. The pieces are:
- `src/shared/MeshKit.lua` and the `Anatomy*` generators (body, head and skull, hair),
- `src/client/modules/AnatomyClient.lua`, which builds the meshes on each client from the
  `LookData` the server publishes on every character.

In a **published** game, these meshes need two things:
- **Game Settings > Security > Allow Mesh / Image APIs** turned on for the experience.
- An **ID-verified** creator account. Roblox requires this for EditableMesh / EditableImage in live
  games.

Studio play works without either.

**Automatic fallback.** The game falls back to the part-built characters automatically in three
cases:
- the APIs are unavailable,
- a mesh cannot be created,
- a device runs out of Editable memory.

In that case every client keeps the part-built characters. They are fully dressed and animated,
nothing breaks, and a warning is logged once. Under memory pressure, AnatomyClient first lowers the
detail level and returns far-away characters to parts before it gives up on meshes. Players can
lower the meshes in **Settings > Graphics detail** (Auto / High / Medium / Low). To switch the meshes
off for everyone, set `Config.Anatomy.enabled = false` in `src/shared/Config.lua`. Budgets, ranges and
the per-frame build time are set in the same table.

The main menu boxer and the fighter-card portrait are copies of your character. They show the same
organic look, and they also fall back to parts when meshes are unavailable.

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

The comment above the table lists every key, where it plays and what to upload (length, loop or
one-shot). The keys include the crowd bed and reactions, the ring bell, walkout / arena / gym music,
coach and corner shouts, the referee count, the announcer, impacts, ambience, heartbeat, breathing
and camera flashes.

When a slot is empty:
- **Crowd sounds, camera flashes and coach shouts** play a shaped built-in stand-in
  (`Config.SoundFallbacks`).
- **Music and the announcer** stay silent.

Music plays through the Settings screen's Music volume. Everything else plays through its SFX volume.
Test every id in Studio. An id that the experience is not allowed to play stays silent and only logs
a warning.

## Feature tour

- **Main menu:** a cinematic gym set with your boxer under the lights. From there: Career, Character,
  Gym, Rankings, Store, Settings. Press **M** in game to open it again.
- **Character creator and barber:** body frame, skin, face shape and sculpt (skull, cheekbones, jaw,
  chin, eyes, nose shapes, lips), eyes, brows, boxer wear (cauliflower ear, broken nose), 30+
  hairstyles across five hair types with strand detail (clumping, frizz, volume, curl size), beards,
  dyes and fades.
- **Training:** heavy bag, speed bag, double-end bag, mitt work, shadow boxing, sparring, bench,
  barbell, dumbbells, squats, pull-ups, medicine ball, skipping, roadwork, agility ladder and cardio
  machines. Each exercise grows its own muscle groups, which show on the body: pump,
  soreness, recovery, detraining, body fat and vascularity. Training also uses energy, hydration,
  nutrition and fatigue.
- **Fights and sparring:** head, body and stamina health, punch types (jab, cross, hooks, uppercut,
  overhand, body shots), blocks, parries, slips, rolls, pivots and clinches.
  - Damage: cuts and swelling, flash knockdowns, standing eight counts.
  - Knockouts: several animated kinds, including one-punch, delayed and face-first.
  - Officials: a referee, judges' scorecards and a crowd.
  - Controls: keys are shown on screen (hold **H**), and touch gets its own pads.
- **Career:** amateur to pro, rankings with four sanctioning bodies, world titles, offers, rivals,
  a camp before each fight, retirement and legacy. Your record and belts appear on the fighter card
  (Career Hub, **H**).
- **City life:** homes from an apartment up to a mansion, stores, sponsors and fans. Gym tiers grow
  from a basement gym to an elite training centre.
- **Venues:** gyms, a sparring room and arenas with fight-night lighting, LED screens, broadcast
  cameras and a walkout stage.
- **Settings:** UI scale, music and SFX volume, screen effects, camera shake, graphics detail, the main
  menu at start, and the fight control strip.
