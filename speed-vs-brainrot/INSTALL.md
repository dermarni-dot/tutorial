# Installing Speed vs Brainrot (for a person or another Claude chat)

Everything is plain Luau. There are 4 scripts and no models or images to upload,
because the server script builds the whole world (parts and Terrain) when the game starts.

## Fastest way: open the ready-made place

Open `SpeedVsBrainrot.rbxlx` in Roblox Studio (File > Open from File). All 4 scripts
are already in the right places. Then do step 2 (game settings) and press Play.
To put the game into an existing place instead, use step 1.

## 1. Put the scripts in place (Roblox Studio)

| File | Where | Type |
| --- | --- | --- |
| `src/SpeedVsBrainrot_Server.server.lua` | ServerScriptService | **Script** |
| `src/SpeedVsBrainrot_HUD.client.lua` | StarterPlayer > StarterPlayerScripts | **LocalScript** |
| `src/SpeedVsBrainrot_World.client.lua` | StarterPlayer > StarterPlayerScripts | **LocalScript** |
| `src/SpeedVsBrainrot_Admin.client.lua` | StarterPlayer > StarterPlayerScripts | **LocalScript** |

For each one: create the Script or LocalScript in the right place, name it after the
file (without `.server.lua` or `.client.lua`), and paste the whole file in.
Replace any older copies of these scripts. If an old `SpeedVsBrainrot_Client`
LocalScript still draws its own stat boxes, delete those boxes or turn that script off,
so the HUD doesn't show twice.

## 2. Game settings

- **Game Settings > Security > Enable Studio Access to API Services**: on. This is needed
  for saving, the leaderboards and the admin list. The game still runs without it,
  but nothing is saved in Studio.
- **Workspace > StreamingEnabled**: on is recommended. The map is about 20,000 parts plus terrain.
- Delete the default Baseplate if you like. The script removes it anyway.
- Don't add your own Terrain where the map goes: the script fills in its own terrain
  (cliffs, scenery, ocean and clouds) along the Z axis when the game starts.

## 3. Optional settings (top of the server script, `CONFIG`)

- `CashGamepassId`: your "3x Cash" game pass ID (0 = off).
- `OwnerUserIds`: extra owner accounts for the admin panel. The game's owner is
  always an admin already.
- `ZoneLength`, `BossHeadStart`, `BossLeash`, `CashPerZone`, speed costs and more are
  explained in comments next to each value.
- Maps, zones, bosses, eggs and pets are tables (`MAPS`, `ZONE_BOSSES`) near the top.

## 3b. Optional: your own scenery models

Make a Folder named `SVB_Props` in **ServerStorage** (the .rbxlx already has it) and put
models in it named `Tree`, `PineTree`, `PalmTree`, `DeadTree`, `Bush`, `Rock` or
`Mushroom`. Toolbox models work. Each one replaces the built-in version of that prop
everywhere. The script anchors, sizes and grounds them itself. Leave out any you don't
want, and the built-in version is used. Use low-part models: they're placed many times.

## 4. Test

Press Play in Studio. You spawn on Map 1's island. Grab cash, buy speed on the green
pad, cross the red line and run from the boss. In Studio you're the owner, so the
**ADMIN** button (or F2) is there: use it to give yourself cash or speed and unlock Map 2.

## Notes for a Claude chat doing the install

- Copy each file's full contents exactly. They are long (the server script is about
  5,200 lines), so don't summarize or shorten them.
- The server script must be a normal Script. The other three must be LocalScripts.
- Nothing else is needed: no ReplicatedStorage setup, folders, remotes or assets
  (the `SVB_Props` folder is optional).
  The server creates `SVB_Remotes`, `SVB_Pets`, `SVB_Maps` and so on when it starts.
