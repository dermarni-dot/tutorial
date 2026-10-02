# Speed vs Brainrot

Three scripts:

| Script | Where it goes |
| --- | --- |
| `src/SpeedVsBrainrot_Server.server.lua` | ServerScriptService (a normal Script). Builds the whole world. |
| `src/SpeedVsBrainrot_HUD.client.lua` | StarterPlayer > StarterPlayerScripts (LocalScript) |
| `src/SpeedVsBrainrot_World.client.lua` | StarterPlayer > StarterPlayerScripts (LocalScript) |

## Maps and bosses

- **Map 1: Brainrot Skylands**. Its boss is **Il Grande Zoomerone**. 10 zones that pay **1 to 1K trophies**: Meadow, Desert, Tundra, Swamp, Lava, Candy, Neon, Crystal, Storm, Void.
- **Map 2: Turbo Badlands**. Its boss is **Tralalero Turbino**, a bigger, boxier boss. 6 zones that pay **1.5K to 500K trophies**: Jungle, Haunted, Factory, Space, Rainbow, Inferno.
- Each map has its own start island with a speed pad, 4 eggs, leaderboards and a portal.
- Reaching a map's finish unlocks the next map and takes you there. To add a third map, copy a block in `MAPS`.
- **Every zone has its own boss** that chases you through it, and each one is bigger and faster than the last: Tung Tung Sahur, Brr Brr Patapim, Lirili Larila, Bombardiro Crocodilo, Trippi Troppi, Ballerina Cappuccina, Chimpanzini Bananini, Cappuccino Assassino and Bombombini Gusini on Map 1; Frigo Camelo, Glorbo Fruttodrillo, La Vaca Saturno, Garamararam and Bobrito Bandito on Map 2. The last zone of each map has the map's big boss. When you cross into the next zone, the old boss vanishes and the new one takes over. Bosses swing their legs as they run and kick up dust. A bar at the top of the screen shows who is chasing you and how close they are. Edit them in `ZONE_BOSSES`.
- **Zones are long (400 studs)**, so you have room to pull away from the boss, and it starts further behind you. Obstacles, decorations and cash repeat down the whole zone. Change `ZoneLength` in `CONFIG` to make them longer or shorter. The start islands stay the same size (`IslandLength`).
- The boss gets faster in every zone. Each zone has a **pace**, so speed is relative: the same Speed makes you run faster in a harder zone, and its boss is faster too.
- **Leaving a zone takes a certain Speed.** The golden gate shows the requirement and glows red until you have it. If you're too slow, you're pushed back.
- **Getting hit sends you back to the start.** That covers obstacles, falling off and the boss catching you. You tumble with stars around your head and a red flash, then reappear at the start.
- **Cash on the floor** comes in bill stacks with pale paper edges, a printed top with a "$" seal, and a gold paper band. Gold coins lie next to them. Piles grow in later zones: one stack, then two crossed stacks with a coin pile, then a pyramid topped with a gold bar. Each pile spins, sparkles and glows, with its value in a green tag above it.
- **Obstacles** move smoothly on every screen and follow the server clock. They are sliders, spinners, swinging logs, crushers, blinking lasers and fire jets, and lightning or meteor strikes. Each zone has only a few.

## Eggs, pets, rebirth, prestige

- **4 eggs per map**:
  - Map 1: 20, 100, 500 and 1K trophies.
  - Map 2: 2.5K, 10K, 50K and 250K trophies.
- Each egg holds 4 pets, Common to Legendary, for 32 pets in total.
- Eggs are detailed: a pedestal, stripes, spots and a shine. They spin and glow, and show their pets and odds above them.
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
- **Cash pickups**: a cash brick with "+545" pops up and flies into the Cash tile, and a green swirl spins around the player.
- **Zone cleared**: a gold card drops in, a shine sweeps across it and the trophies count up. The card then flies into the Trophies tile.
- **Egg icons**: each egg has its own design, matching its 3D egg, with a smooth egg shape, shading, a glossy highlight and a shadow underneath.
- **Egg hatch**: the screen dims, the egg wobbles and cracks, there is a flash and the halves fly apart. Your actual pet pops out in front of spinning rays, with its rarity. Every pet is drawn by its kind (bunny, pup, cat, fox, wolf, bear, bee, beetle, penguin, dragon, slime, bird, cloud, unicorn, robot, bat, wisp, overlord) in its own colors, in the hatch screen and in the Pets menu. Fusing pets plays its own version.
- The whole UI is drawn at 80% size so it covers less of the screen. Change `UI_SIZE` in the HUD script to adjust it.

No emojis or uploaded images: every icon is drawn from rounded frames (the `ICONS` table in the HUD script).

## World script (smoothness, animations, lighting)

- Moving obstacles, cash piles and eggs are animated on your own screen every frame, so they move smoothly.
- **Running**: when you're fast, a bouncy run, then a ninja dash. Both come from Roblox's free animation packs. The playback speed is capped so it never looks frantic. You also lean forward, leave a speed trail, and the camera view widens.
- **Lighting**: soft haze, bloom on neon, sun rays and a light color grade. Map 1 is a sunny day and Map 2 a warm late afternoon.

![HUD](svb_hud.png)
![Menus](svb_menus.png)
![Egg hatch](svb_hatch.png)
![Egg icons](svb_eggs.png)
![All pets](svb_pets.png)
![Cash piles](cash3d.png)
![3D eggs up close](eggs3d_closeups.png)
![3D eggs, Map 1](eggs3d_map1.png)
![3D eggs, Map 2](eggs3d_map2.png)
