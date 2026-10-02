# Speed vs Brainrot

Four scripts:

| Script | Where it goes |
| --- | --- |
| `src/SpeedVsBrainrot_Server.server.lua` | ServerScriptService (a normal Script). Builds the whole world. |
| `src/SpeedVsBrainrot_HUD.client.lua` | StarterPlayer > StarterPlayerScripts (LocalScript) |
| `src/SpeedVsBrainrot_World.client.lua` | StarterPlayer > StarterPlayerScripts (LocalScript) |
| `src/SpeedVsBrainrot_Admin.client.lua` | StarterPlayer > StarterPlayerScripts (LocalScript) |

## Admin panel

- The game's **owner is always an admin**: the account that owns the game, or the owner (rank 255) if it's a group game. In Studio, everyone testing is the owner. To add more owner accounts, put their UserIds in `CONFIG.OwnerUserIds`.
- Admins get an **ADMIN** button at the top right, or press **F2**. Everything works by clicking:
  - **Player tab**: pick a player, or Everyone, from the list. You can then:
    - give or take cash, speed and trophies, with quick buttons or a custom amount;
    - give any pet as Normal, Golden or Rainbow;
    - go to the player, bring them to you, or send them to Map 1 or Map 2;
    - unlock all maps or unlock prestige;
    - turn on god mode, so nothing can hit them;
    - reset their data or kick them. Both need a second click to confirm.
    - send them to any zone on Map 1 or Map 2;
    - give +1 or +10 rebirths, or every pet at once;
    - freeze them, respawn them, make them tiny or giant, or pause their boss.
  - **Server tab**:
    - send an announcement banner to everyone;
    - start a cash event (x2, x5 or x10), a speed event (x1.5 to x3) or a trophy event (x2 to x10);
    - make it rain cash in every zone;
    - switch to low gravity;
    - set the time of day (day, sunset, night) or let the zones decide;
    - make the bosses slow, fast or paused, or remove them all.
  - **Me tab**: fly (move normally and look up or down to climb; Space and Ctrl also work on a keyboard), spectate a player, and quick buttons for god mode, cash and speed for yourself.
  - The panel shrinks to fit phone screens, and a row with too many buttons scrolls sideways.
  - **Admins tab** (owner only): add an admin by typing a username (they can be offline) or by picking someone in the player list, and remove admins. The admin list is saved and works in every server.
- Every click is checked on the server, so nobody else can use these buttons. Announcements and kick reasons go through Roblox's text filter.

## Maps and bosses

- **Map 1: Brainrot Skylands**. Its boss is **Il Grande Zoomerone**, a king with a crown, cape and sceptre. 10 zones that pay **1 to 1K trophies**: Meadow, Desert, Tundra, Swamp, Lava, Candy, Neon, Crystal, Storm, Void.
- **Map 2: Turbo Badlands**. Its boss is **Tralalero Turbino**, a bigger shark in big sneakers. 6 zones that pay **1.5K to 500K trophies**: Jungle, Haunted, Factory, Space, Rainbow, Inferno.
- Each map has its own start island with a speed pad, 4 eggs, leaderboards and a portal.
- Reaching a map's finish unlocks the next map and takes you there. To add a third map, copy a block in `MAPS`.
- **One boss per map** chases you through every zone of that map. It has big eyes with a shine, an open mouth with teeth, arms that pump and legs that swing as it runs, and it kicks up dust.
- **How the boss's speed works**:
  - It gets faster in every zone: each zone has a pace it runs at least.
  - If you're faster than it, it keeps speeding up until it's faster than you, so it slowly catches up.
  - Each map's boss has a **top speed** it can never go past: Il Grande Zoomerone tops out at 175, Tralalero Turbino at 330. Get faster than that and you can leave it behind for good. Change `topSpeed` on each map's `boss` in `MAPS`, and `BossAccel` and `BossOvertake` in `CONFIG` for how fast it speeds up.
  - The bar at the top of the screen shows who is chasing you, how far behind it is, and its speed against yours, with "MAX" once it's at its top speed.
- **Zones are long (600 studs) and wide (180 studs)**, so you have room to pull away from the boss, and it starts further behind you. Obstacles, decorations and cash repeat down the whole zone. Change `ZoneLength` in `CONFIG` to make them longer or shorter. The start islands stay the same size (`IslandLength`).
- Each zone has a **pace**, so speed is relative: the same Speed makes you run faster in a harder zone, and the boss runs faster there too.
- **Every zone is open to everyone.** There's no Speed you need to get in. The only way to fail is getting caught (or hit). The golden gate at the end of each zone shows the trophies you get for making it out.
- **Getting hit sends you back to the start.** That covers obstacles, falling off and the boss catching you. You tumble with stars around your head and a red flash, then reappear at the start.
- **Every zone has its own textures** in place of plain plastic studs. Each has its own ground, a trail down the middle and patches on the ground, and the cliff underneath matches the theme:
  - Meadow: grass and a dirt trail.
  - Desert: sand and sandstone.
  - Tundra: snow, a sheet of ice and glacier patches.
  - Swamp: mud and a pebble trail.
  - Lava Lands: basalt and glowing cracked-lava patches.
  - Candy Kingdom: pink marble and a candy-cane striped trail.
  - Neon City: asphalt road with yellow lane lines.
  - Crystal Caves: slate, a marble trail and glass patches.
  - Storm Peaks: rock and cobblestone.
  - The Void: granite tiles.
  - Jungle: leafy grass and a mud trail.
  - Haunted Woods: dark ground and cobblestone.
  - Robo Factory: diamond-plate metal with lane lines.
  - Outer Space: moon rock and a metal walkway.
  - Rainbow Road: white marble with rainbow lanes.
  - Inferno: basalt and cracked lava.
  - The start islands use grass, ground, cobblestone paths and a marble egg deck. The speed pad keeps its classic studs.
- **The world uses real Roblox Terrain**, not only flat parts:
  - Each zone floats on a terrain cliff in its own rock and sand materials, with boulders hanging underneath.
  - Outside the glass walls, each zone has its own scenery, made of terrain:
    - rolling hills (Meadow, Swamp, Jungle, Candy, Space, Rainbow);
    - sandstone mesas (Desert);
    - jagged peaks (Tundra, Storm, Haunted);
    - volcanoes with glowing tops (Lava, Inferno);
    - spikes (Crystal, Void);
    - towers (Neon, Factory).
  - The start islands are terrain too: grass terraces and a rocky underside.
  - Below the world there is a real terrain ocean with waves, Roblox's 3D clouds overhead, and grassy sky islands floating off to the sides.
- **Ramps**: zones with a solid floor have a small ramp hump every 200 studs, so the run isn't one flat strip. Zones with holes in the floor skip them.
- **Your own models (optional)**: put models in `ServerStorage > SVB_Props` named `Tree`, `PineTree`, `PalmTree`, `DeadTree`, `Bush`, `Rock` or `Mushroom` (Toolbox models are fine). The game then uses them in place of its built-in blocky versions. They are anchored, sized and stood on the ground automatically, with a random turn each. Leave the folder empty to keep the built-in ones.
- **Cash on the floor** comes in bill stacks with pale paper edges, a printed top with a "$" seal, and a gold paper band. Gold coins lie next to them. Piles grow in later zones: one stack, then two crossed stacks with a coin pile, then a pyramid topped with a gold bar. Each pile spins, sparkles and glows, with its value in a green tag above it.
- **Obstacles** move smoothly on every screen and follow the server clock. They are sliders, spinners, swinging logs, crushers, blinking lasers and fire jets, and lightning or meteor strikes. Each zone has only a few, and none is impossible:
  - sliders never move faster than 32 studs a second, so you can see them coming;
  - spinners and crushers are slower;
  - lasers and fire jets stay on for less time;
  - hitboxes fit the obstacles more tightly;
  - every goo or lava river has three bridges;
  - ice walls have wider gaps;
  - there are fewer lightning and meteor strikes and fewer holes in the Void.
- **Map detail**:
  - Each zone runs through land: banks in the zone's own terrain (grass, sand, snow and so on) on both sides, with hills, mesas, peaks or towers behind them.
  - Striped curbs line the walls, and lamp posts glow in the zone's color.
  - A gantry over the middle of each zone shows its number and name.

## Eggs, pets, rebirth, prestige

- **4 eggs per map**:
  - Map 1: 20, 100, 500 and 1K trophies.
  - Map 2: 2.5K, 10K, 50K and 250K trophies.
- Each egg holds 4 pets, Common to Legendary, for 32 pets in total.
- Eggs are detailed: a pedestal, stripes, spots and a shine. They spin and glow, and show their pets and odds above them.
- **Buying speed**: each purchase gives you 10% of the Speed you already have (at least +1), so it keeps up as you get faster. You can buy it two ways:
  - stand on the green pad on the island (it's smaller now) and it keeps buying;
  - tap the green **Buy Speed** button under your stats, or hold it to keep buying.
  - Both show exactly how much Speed you get and what it costs. The price turns red when you can't afford it. Change `SpeedStep` in `CONFIG` to change the 10%.
- **Rebirth** resets your cash and speed for a cash multiplier.
- **Prestige** unlocks once you reach the final zone of the final map. You start over from Map 1 with a permanent trophy multiplier. You keep your pets and rebirths.
- **Every egg has its own design**, painted flat on the shell so nothing sticks out:
  - Grass: a fringe of grass blades and daisies.
  - Sand: desert layers and a turquoise band with gold diamonds.
  - Ice: snowflakes under a frosty glass shell.
  - Lava: dark rock with glowing cracks.
  - Jungle: watermelon stripes and a tribal band.
  - Candy: crossing swirls and sprinkles.
  - Robo: shiny metal with neon circuits.
  - Cosmic: a nebula swirl, stars and a shimmering force field.
- **Leaderboards** on every island show top Cash, top Speed and most Pets Hatched. They are global, saved in ordered data stores.

## HUD

- **Stat tiles**: Speed, Cash and Trophies on studded brick tiles. The numbers count up.
- **Buttons**:
  - Teleport: spawn, the speed pad, the eggs, Map 1 or Map 2.
  - 3x Cash gamepass.
  - Invite.
  - Pets, with Fuse 3 to upgrade.
  - Rebirth.
  - Prestige, which stays locked until you can use it.
- **Cash pickups**: a cash brick with "+545" pops up and flies into the Cash tile. Around the player who grabbed it (everyone sees it): a green swirl, a green glow on the body, a green and a gold ring rippling out on the floor, bills and coins bursting out and bouncing, and "$" signs floating up.
- **Zone cleared**: a gold card drops in, a shine sweeps across it and the trophies count up. The card then flies into the Trophies tile.
- **Egg icons**: each egg has its own design, matching its 3D egg, with a smooth egg shape, shading, a glossy highlight and a shadow underneath.
- **Egg hatch**: the screen dims, the egg wobbles and cracks, there is a flash and the halves fly apart. Your actual pet pops out in front of spinning rays, with its rarity. Every pet is drawn by its kind (bunny, pup, cat, fox, wolf, bear, bee, beetle, penguin, dragon, slime, bird, cloud, unicorn, robot, bat, wisp, overlord) in its own colors, in the hatch screen and in the Pets menu. Fusing pets plays its own version.
- The whole UI is drawn at 80% size so it covers less of the screen. Change `UI_SIZE` in the HUD script to adjust it.
- **On phones** (touch screens and short screens) the HUD switches to a compact layout: the stats and the Buy Speed button go in a row along the top and the buttons in one row under them, away from the thumbstick and the jump button.

No emojis or uploaded images: every icon is drawn from rounded frames (the `ICONS` table in the HUD script).

## World script (smoothness, animations, lighting)

- Moving obstacles, cash piles and eggs are animated on your own screen every frame, so they move smoothly.
- **Running**: when you're fast, a bouncy run, then a ninja dash. Both come from Roblox's free animation packs. The playback speed is capped so it never looks frantic. You also lean forward, leave a speed trail, and the camera view widens.
- **Lighting and sky per zone** (toned down so it's no longer too bright: lower exposure, less bloom, softer haze; `LIGHT_SCALE` in the World script makes it brighter or darker): as you cross into a new zone, the sky, sun angle, haze, color grade and cloud cover blend smoothly to match it. The Desert is a hazy gold, the Tundra a cold bright white, Lava a smoky red dusk, Neon City and Space night time, Storm Peaks dark and overcast, and so on. Bloom on neon and sun rays stay on everywhere.

![Meadow zone](map_meadow.png)
![Desert zone](map_desert.png)
![Overview](map_overview.png)
![HUD](svb_hud.png)
![Menus](svb_menus.png)
![Egg hatch](svb_hatch.png)
![Egg icons](svb_eggs.png)
![All pets](svb_pets.png)
![Cash piles](cash3d.png)
![Cash pickup effect](cash_pickup_fx.png)
![3D eggs up close](eggs3d_closeups.png)
![3D eggs, Map 1](eggs3d_map1.png)
![3D eggs, Map 2](eggs3d_map2.png)
