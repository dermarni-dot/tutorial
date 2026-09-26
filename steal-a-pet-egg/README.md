# Steal a Pet Egg

A Roblox "steal a ___" game. Eggs grow in guarded nests out in the wild. Grab one,
outrun the nest's guardian, and carry it home to hatch. Hatched pets earn cash every
second. Train your speed to raid farther, rarer biomes, and steal from other
players along the way.

## Open it

1. Double-click **StealAPetEgg.rbxlx** (or in Roblox Studio: File > Open from File).
2. Press **Play**. The map, bases, biomes, guardians and HUD are all built from code, so there is nothing to place by hand.
3. To test stealing between players, use **Test > Clients and Servers > 2 Players > Start**.

To save progress in Studio, publish the place, then turn on
Game Settings > Security > **Enable Studio Access to API Services**.

## How it plays

- **The map:** your base sits in town. A road leads out through 5 biomes, each harder than the last:

  | Biome | Guardian | Guardian speed | Speed needed | Eggs |
  |---|---|---|---|---|
  | Whispering Forest | Bramble Bear | 20 | 0 | Common, Uncommon |
  | Scorch Dunes | Dune Scorpion | 30 | 11 | Uncommon, Rare |
  | Frostpeak | Frost Yeti | 42 | 24 | Rare, Epic |
  | Magma Crater | Lava Golem | 56 | 40 | Epic, Legendary |
  | Starfall Void | Void Wraith | 75 | 61 | Legendary, Mythic |

  Base walk speed is 24, plus your Speed stat (you start with 5).

- **Grabbing eggs:** hold E on an egg in a nest. The guardian chases you. If it touches you, it takes the egg back and stuns you. Get far enough from its nest and it gives up.
- **Carrying:** you run 10% slower with an egg. Step into your base and the egg drops into your open pet pen to incubate.
- **Speed:** stand on the **treadmill** in your base to gain Speed (it gets slower the faster you are), or buy +5 Speed on the yellow pad.
- **Stealing:**
  - Hold E on an egg incubating in someone's base (1.25s).
  - Hold E on the egg on another player's head (0.6s) to snatch it.
  - Stolen eggs have a 25% chance to hatch shiny (normal: 5%). Shiny = 3x income.
- **Bonk Bat:** swing it (slash animation, sound, "BONK!" pop). Hit an egg carrier and they drop it. An egg stolen from a base flies back to its owner.
- **Base Lock:** the blue pad. Blocks stealing from your base for 60s, then recharges for 90s.
- **Fuse Machine:** the pink pad. 3 identical pets become 1 **Big** pet (4x income), and 3 Big pets become 1 **Huge** pet (16x).
- **Pet pen and selling:** every base has one wide open pen (no roof, no slots) that holds 24 eggs and pets. Hold E on your own pet to sell it.
- 6 bases per server (set Max Players to 6 in your game settings). Cash, Speed, treadmill tier, eggs and pets save automatically.

## Where things live

| Script | Place | Does |
|---|---|---|
| Config | ReplicatedStorage.Shared | **Every number you'd want to tune:** biomes, guardian speeds, egg odds, hatch times, pets, speed curve, prices |
| Util | ReplicatedStorage.Shared | Number/time formatting, weighted random |
| Main | ServerScriptService | Starts everything, loads and saves players |
| MapBuilder | ServerScriptService.Modules | Builds the lighting, terrain, town, bases, biomes, nests and particles |
| Visuals | ServerScriptService.Modules | Egg, pet and guardian models (placeholder shapes) |
| GameService | ServerScriptService.Modules | Core gameplay: nests, guardians, carrying, stealing, hatching, fusing, treadmill |
| DataService | ServerScriptService.Modules | DataStore saving |
| Monetization | ServerScriptService.Modules | Robux purchases |
| ClientMain | StarterPlayer.StarterPlayerScripts | HUD, chase warning, biome lighting moods and banners, notifications, shop buttons |

## Turning on Robux purchases

1. On the Creator Dashboard, create three **Developer Products** (Instant Hatch, Egg Rain, +25 Speed) and one **Game Pass** (2x Cash).
2. Paste their IDs into `Config.Products`.
3. The shop buttons appear on the right side of the screen once an ID is not 0.

## Adding pets or biomes

- **New pet:** add a line to a rarity's `Creatures` list in Config, for example
  `{ Name = "Blaze Fox", Income = 42, Color = Color3.fromRGB(255, 90, 30) }`.
  Don't rename pets after launch, because saves store them by name.
- **New biome:** add an entry to `Config.Biomes`. The map grows to fit it automatically.

## Good next steps

- Swap the placeholder shapes in `Visuals` for real pet and guardian models.
- Trails that multiply speed, and bear traps that slow guardians.
- A pet index with rewards for discovering every pet.
- Sounds for grabbing, getting caught, bonking and hatching.

## Using Rojo instead

The `src/` folder and `default.project.json` map the same scripts for Rojo users.
