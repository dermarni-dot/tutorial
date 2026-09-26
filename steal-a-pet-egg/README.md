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

- **The map:** your base sits in town. A road leads out through 8 biomes, each harder than the last:

  | Biome | Guardian | Guardian speed | Speed needed | Eggs |
  |---|---|---|---|---|
  | Whispering Forest | Bramble Bear | 28.6 | 0 | Common, Uncommon |
  | Scorch Dunes | Dune Scorpion | 106.5 | 1K | Uncommon, Rare |
  | Frostpeak | Frost Yeti | 159.3 | 25K | Rare, Epic |
  | Magma Crater | Lava Golem | 199 | 200K | Epic, Legendary |
  | Starfall Void | Void Wraith | 232.8 | 1M | Legendary, Mythic |
  | Candy Kingdom | Gummy Titan | 269.1 | 5M | Legendary, Mythic, Divine, Secret |
  | Sunken Reef | Reef King | 308.1 | 25M | Mythic, Divine, Secret |
  | Celestial Heights (boss) | Seraph Sentinel | 343.8 | 100M | Mythic, Divine, Secret (8%!) |

  Walk speed climbs with every tenfold of your Speed stat, faster and faster: 5 Speed walks at 49, 300 at 100, 11K at 162, 1M at 260 and 100M at 384 (max 420). Guardian speed is in studs per second; each guardian is just a hair slower than you are while carrying an egg with its zone's Speed needed. Tune it with `Config.BaseWalkSpeed`, `WalkPerTenfold` and `WalkCurve`.

- **Grabbing eggs:** hold E on an egg in a nest. The guardian chases you. If it catches you: **SLAP!** A giant glove smacks you, you go spinning through the air with a screen flash, shake and a big SLAP! text, then land back at the start of your base with dizzy stars while it takes its egg back. Get far enough from its nest and it gives up.
- **Carrying:** you run 10% slower with an egg. Step into your base and the egg drops into your open pet pen to incubate.
- **Speed:** stand on the **treadmill** in your base to gain Speed. The gold pad sells 12 treadmill tiers, each doubling what it gives: Basic x1, Bronze x2, Silver x4, Gold x8, Diamond x16, Emerald x32, Cosmic x64, Galaxy x128, Nebula x256, Supernova x512, Quantum x1024 and Celestial x2048.
  - Every tier looks fancier: tier-colored belt stripes, neon side trims, a light under the belt, then shiny rails from Gold, glass frames and rising sparkles, a spinning halo of orbs from Cosmic, flames for Supernova and a rainbow belt for Celestial.
  - A live screen on the console shows your tier, multiplier and Speed per second; a row of lights shows how many tiers you own.
  - While you train the belt speeds up and kicks out speed streaks, and buying a tier sets off a burst of sparkles.
- **Stealing:**
  - Hold E on an egg incubating in someone's base (1.25s).
  - Hold E on the egg on another player's head (0.6s) to snatch it.
  - Stolen eggs have a 25% chance to hatch shiny (normal: 5%). Shiny = 3x income.
- **Bonk Bat:** swing it (slash animation, sound, "BONK!" pop). Hit an egg carrier and they drop it. An egg stolen from a base flies back to its owner.
- **Base Lock:** the blue pad. Blocks stealing from your base for 60s, then recharges for 90s.
- **Fuse Machine:** the pink pad. 3 identical pets become 1 **Big** pet (4x income), and 3 Big pets become 1 **Huge** pet (16x).
- **Bases:** each base (in its own accent color) has a cottage out back, flagpoles, a striped canopy over the treadmill, a crystal arch over the fuse pad, garden lights along the carpet, flower planters, pet beds, a toy ball, a food trough, a welcome mat, a mailbox and stepping stones. See `base_preview.png`.
- **Pet pen and selling:** every base has one wide open pen (no roof, no slots) that holds 24 eggs and pets. Hold E on your own pet to sell it.
- **Daily rewards:** the orange 🎁 Daily button (it pops open by itself when a reward is waiting). Claim once a day: Day 1 $, Day 2 $$, Day 3 Speed, Day 4 $$$, Day 5 Rare Egg, Day 6 $$$$, Day 7 Epic Egg, then it loops. Cash and Speed rewards grow with your income and Speed. Miss a day and the streak starts over. Days reset at midnight UTC. Tune it in `Config.DailyRewards`. Test it with `!daily` (next day) and `!daily reset`.
- **Pet Index:** the blue 📖 Index button. A collection book of all 499 pets; ones you haven't had yet show as ???. Every new pet pops a message. Finishing a whole rarity row gives **+5% cash from all your pets, forever** (up to +40%). Tune it with `Config.IndexBonusPerRarity`.
- **Revenge:** when someone steals your egg and gets it home, a red timer appears top-right and the thief glows red (only you see it). Steal any egg from them within 5 minutes for bonus cash (5 minutes of your income). A revenge steal can't be revenged back, and after a payout there's a 15-minute cooldown so friends can't farm it. Tune it with the `Config.Revenge...` settings.
- **Pet models:** 499 pets across 75 species. 58 species are built like their real animal (torso, head, legs, neck, ears and tail in the right proportions): dragons have long necks, wings and spiked tails; bunnies sit up with long ears; unicorns and deer have long legs, manes, horns and antlers; birds stand upright with beaks and wings; fish have fins and tails. Round critters (slimes, ghosts, ladybugs, jellies...) stay round. See `pet_preview.png` for every species. The builders are the `ANATOMY` entries in Visuals.
- **Egg designs:** every rarity has 6 egg looks (48 in all), e.g. Polka, Sprinkle, Ladybug, Honeycomb, Seashell, Circuit, Toadstool, Crown Jewel, Clockwork, Aurora, Angel Feather, Static, Void Eye. See `egg_preview.png`. Eggs in your base show a hatch progress bar, crack as they get close to hatching and wobble in the last few seconds. Each egg picks one at random, and its name shows on the egg's label. Add your own in `EGG_VARIANTS` in Visuals.
- **Day and night:** a full day passes every 16 minutes (about 11.5 minutes of daylight, then sunset, a starry night and sunrise). Everyone on a server sees the same time. Street lamps, windows and string lights glow after dark. Each zone has its own lighting: sunbeams in the forest, heat glare in the desert, a sparkly cold look at Frostpeak, a permanent red sunset in Magma Crater and endless night in the Void. Tune it with `Config.DayCycleMinutes` (0 = always afternoon) and each zone's `Mood`. Test it with `!time day`, `!time sunset`, `!time night` and `!time cycle`, or the Admin panel.
- **Sky:** the sky's colors follow the time of day: golden-pink haze and clouds at sunrise and sunset, a deep blue night with thinner clouds so the stars and a bigger moon show, and a bright midday. Hot air balloons drift over town and bird flocks fly across during the day (client-side, so they cost the server nothing).
- **Map scenery:**
  - **Town:** a cobbled main street with string lights, cottages with picket fences, picnic tables and bunting.
  - **Set pieces, 4 per zone:** Forest has a treehouse with a rope swing, a waterfall, a glowing mushroom grove and a campsite. Desert has an oasis, a giant ribcage, a sandstone arch and temple ruins. Frostpeak has a log cabin, frozen waterfalls, a snow fort and a sled hill. Magma Crater has basalt columns, a lava lake with a rope bridge, a forge and geysers. The Void has a rune circle, floating stairs, a portal and an observatory.
  - **Beyond the walls:** mountains, mesas and snowy peaks, smoking volcanoes and floating islands.
  - **Sky:** an aurora over Frostpeak, and a ringed planet, moon and nebula clouds over the Void.
  - **Walls:** vines, carvings, icicles, lava cracks or runes, depending on the zone.
  - **Extra effects:** falling leaves, ash and rising stardust.
- **Market stalls in town** (walk up and press E / hold Ⓧ):
  - **🍦 Treat Shop:** treats make your pets grow faster and earn a bit more for a while. Cookie (1.5x grow, +10%, 3 min), Cupcake (2x, +15%, 5 min), Ice Cream (3x, +20%, 5 min), Golden Cake (5x, +25%, 10 min). Prices scale with your income. One treat at a time; buying the same one adds time (up to 30 min). A timer shows top-left, and treats keep going if you rejoin. Tune them in `Config.Treats`.
  - **🥚 Egg Facts:** every egg rarity in 3D with its hatch time, pet count, income range, which zones it spawns in (and how often), its egg designs and a fun fact, plus shiny and mutation odds.
- **🎟️ Codes** (small button under the side menu): type a code for a free reward. Each code works once per player, and a code isn't used up if your pen is full.

  | Code | Reward |
  |---|---|
  | RELEASE | 10 minutes of your income (at least $2.5K) |
  | EGGSTRA | Free Rare Egg |
  | PETS499 | Free Epic Egg |
  | ZOOM | +15% Speed (at least +50) |
  | SWEETTOOTH | Free 🧁 Sprinkle Cupcake treat |

  Add or change codes in `Config.Codes`. Codes can give `Egg`, `Treat`, `SpeedPercent` or `CashMinutes`.
- **⚙️ Settings** (next to Codes, just for you): turn pet name tags, particle effects (for slower devices), always-daytime and the sky balloons/birds on or off.
- **Screens:**
  - **Title screen** with a Play button when you join.
  - **Hatch reveal:** your new pet spins in 3D with light rays in its rarity color, its stats, and a NEW PET! tag the first time.
  - **Pet cards:** tap any pet in the 📖 Index to see it in 3D, how much it earns and where its eggs spawn. Pets you haven't found yet show as a silhouette.
  - **Top-left badge** with the time of day and the zone you're in.
- **Console / gamepad controls:**

  | Button | Does |
  |---|---|
  | View (Back) | Opens the side menu (Daily, Shop, Index, Admin, Settings, Codes) to move through with the D-pad |
  | Ⓐ | Presses the highlighted button (it has a gold glow) |
  | Ⓨ | Opens Daily Rewards |
  | Ⓑ | Closes whatever is open (menus, pet cards, hatch reveal) or steps off the treadmill |
  | Ⓧ (hold) | Grabs or steals an egg |
  | R2 | Swings the Bonk Bat |
  | Left stick / Ⓐ | Moves / jumps |

  Each menu highlights its main button when it opens, and a button guide shows at the bottom-left while you use a controller.
- 6 bases per server (set Max Players to 6 in your game settings). Cash, Speed, treadmill tier, eggs and pets save automatically.

## Where things live

| Script | Place | Does |
|---|---|---|
| Config | ReplicatedStorage.Shared | **Every number you'd want to tune:** biomes, guardian speeds, egg odds, hatch times, pets, speed curve, prices |
| Util | ReplicatedStorage.Shared | Number/time formatting, weighted random |
| Main | ServerScriptService | Starts everything, loads and saves players |
| MapBuilder | ServerScriptService.Modules | Builds the lighting, terrain, town, bases, biomes, nests and particles |
| Visuals | ReplicatedStorage.Shared | Egg, pet and guardian models (shared so the UI can show pets in 3D) |
| GameService | ServerScriptService.Modules | Core gameplay: nests, guardians, carrying, stealing, hatching, fusing, treadmill |
| DataService | ServerScriptService.Modules | DataStore saving |
| Monetization | ServerScriptService.Modules | Robux purchases |
| DailyRewardService | ServerScriptService.Modules | Daily streak rewards |
| CodesService | ServerScriptService.Modules | Redeems codes (Config.Codes) |
| ClientMain | StarterPlayer.StarterPlayerScripts | HUD, chase warning, biome lighting moods and banners, notifications, shop buttons |

## Turning on Robux purchases

1. On the Creator Dashboard, create three **Developer Products** (Instant Hatch, Egg Rain, +25 Speed) and one **Game Pass** (2x Cash).
2. Paste their IDs into `Config.Products`.
3. The shop buttons appear on the right side of the screen once an ID is not 0.

## Adding pets or biomes

- **New pet:** add a line to a rarity's `Creatures` list in Config, for example
  `{ Name = "Blaze Fox", Style = "Fox", Income = 42, Color = Color3.fromRGB(255, 90, 30), Pattern = "Stripes", Accessory = "Scarf" }`.
  - `Style` is the species model (75 of them, e.g. Pup, Cat, Wolf, Lion, Pony, Pegasus, Giraffe, Koala, Otter, Croc, Flamingo, Peacock, Dolphin, Whale, Griffin, Cerberus, Drake, Unicorn).
  - `Pattern` (optional): Spots, Stripes, Patches, Stars, Hearts, Gems, Swirl, Pixels, Rainbow, Freckles. Add `PatternColor` to recolor it and `PatternGlow = true` to make it glow.
  - `Accessory` (optional): Bow, TopHat, PartyHat, WizardHat, Beanie, Tiara, Halo, Scarf, Bandana, Shades, Glasses, Headphones, Flower, Leaf, Horns, Antenna, Bell, Cape. Add `Accent` to recolor it.
  - `Plain = true` removes the flame tail from Cat pets and the ice crystal from Fish pets.
  Don't rename pets after launch, because saves store them by name.
- **New biome:** add an entry to `Config.Biomes`. The map grows to fit it automatically.

## Good next steps

- Swap the placeholder shapes in `Visuals` for real pet and guardian models.
- Trails that multiply speed, and bear traps that slow guardians.
- Sounds for grabbing, getting caught, bonking and hatching.

## Using Rojo instead

The `src/` folder and `default.project.json` map the same scripts for Rojo users.
