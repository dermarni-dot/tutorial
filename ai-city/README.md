# AI City — city map

A full city for AI City's citizens to live, work and vote in: 30 places, 132 homes and a sidewalk walking network. Everything is built by code when the server starts.

![The whole city](city_preview.png)
![Downtown](downtown_preview.png)

## Open it

- **Roblox Studio:** open `AICity.rbxlx` and press Play. The city builds itself in a few seconds.
- **Rojo:** `rojo serve` in this folder (see `default.project.json`).
- **Your existing game:** copy `src/MapBuilder.lua` into `ServerScriptService.Modules` and replace your Config with `src/Config.lua`.

## What's in the city

It's a 7×7 grid of city blocks (about 700 × 700 studs) with streets, sidewalks, downtown crosswalks, 196 street lamps that turn on at night, parked cars and a ring of trees.

| Area | Buildings |
|---|---|
| Downtown | ⛲ City Plaza (fountain, **speech stage and podium**, **ballot box**, **city news board**, benches, chess tables, dance floor), 🏛️ Town Hall (columns, steps, clock tower, dome), 🏦 City Bank (vault, ATM) + 🏢 Offices, 🚓 Police (cars, siren), 🥐 Bakery, ☕ Cafe (outdoor tables), 🛒 Market (fruit stalls), 💊 Pharmacy, 📚 Library, 🍝 Restaurant, 🏫 School (playground, bell tower), 🌳 Central Park (pond, gazebo, garden plots, easels, jogging loop) |
| Around downtown | 🏨 Grand Hotel, office towers, 🚒 Fire Station (fire truck, hose tower), 🏥 Hospital (helipad, ambulance), 🎬 Cinema (lit marquee, seats), 🏋️ Gym + basketball court, two shopping streets (👕 Clothing, 🧸 Toys, 📱 Electronics, 💐 Flowers, 🐶 Pet Shop, 📖 Books, 🍦 Ice Cream, 🔨 Hardware), two apartment buildings (Sunset Towers, Maple Court), ⚽ Sports Field |
| Edges | 100 houses with street addresses (e.g. "12 Oak Street"), 🏭 Factory (smoking chimneys), 📦 Warehouse, ⛽ Gas & Garage |

## Using the map from your scripts

```lua
local MapBuilder = require(game.ServerScriptService.Modules.MapBuilder)
local map = MapBuilder.Build() -- builds once; later calls return the same map

local bakery = map.Places.Bakery      -- also map.PlaceList for all of them
bakery.Door, bakery.Inside            -- ground positions for Humanoid:MoveTo
bakery.WorkSpots                      -- at least one per job slot in Config.Jobs
bakery.Kind                           -- "civic", "work", "store" or "fun"

local home = map.Homes[1]             -- .Door, .Inside, .Address, .Capacity, .Kind

-- walking on the sidewalks (shortest path, crosses at the corners)
for _, point in ipairs(map.RouteBetween(home, bakery)) do
	humanoid:MoveTo(point)
	humanoid.MoveToFinished:Wait()
end
map.Route(fromPosition, toPosition)   -- same, between any two positions

map.SpeechSpot, map.StageCFrame       -- where speeches are given
map.BallotBox                         -- the ballot box part
map.HobbySpots["fishing"]             -- spots for the outdoor hobbies
map.BenchSpots                        -- places to sit
map.Places.Hospital.Beds, map.Places.Cinema.Seats, map.Places.TownHall.MayorOffice

MapBuilder.SetNews("Mayor Rosa passed: Build more parks!")  -- the plaza news board
MapBuilder.SetNight(true)             -- lamps and windows (Main does this for you)
```

`Main.server.lua` builds the city and runs the day/night cycle from `Config.DAY_LENGTH`: lamps and windows light up from 18:30 to 6:30, and the Town Hall clock shows the time. If your game already moves `Lighting.ClockTime`, set `RUN_DAY_CYCLE = false` and it just follows your clock.

To change what goes where, edit `PLAN` near the bottom of `MapBuilder.lua`: each block (`"i,j"`, the plaza is `"0,0"`) names what's built on it. Any block not listed gets houses.

## What changed in Config

Every original key is still there with the same shape, so your other scripts keep working.

| Change | Why |
|---|---|
| `POPULATION` 42 → 60 | The city is much bigger; 42 people would feel empty. Lower it if the server struggles. |
| `WALK_SPEED` 10 → 14 | The longest walk across the city is ~1,050 studs. At speed 10 that was over 5 in-game hours. |
| `ELECTION_INTERVAL` 420 → 480 | Exactly one election per in-game day, always at the same hour. |
| `COIN_TICK` comment | It said "coins every minute", which was unclear. It now says 10 coins per player every real minute. Check your script uses it that way. |
| **FreeFestival** now offends safety a little | It appealed to every value with no downside, so it always won. |
| **MorePolice** and **NewFactory** city effects toned down | Both added up to +9 to city stats; now +6 and +5. |
| 5 new stances | Plant Trees, Protect the Old Town, Night Market, Neighborhood Watch, Cheap Bank Loans. Nature and tradition only had one or two ideas each. |
| 15 new jobs | The new buildings need staff: bank teller and manager, firefighter, librarian, chef, waiter, pharmacist, office worker, receptionist, cinema clerk, fitness coach, store clerk, mechanic, warehouse worker. |
| Night Officer job (18:00–24:00) | Nobody watched the city at night, even though crime and curfews happen then. |
| `Config.Places` (+ `PlaceById`) | Every building's id, name, emoji and kind, for the map signs and for your code. |
| `OutdoorHobbies` | Chess, guitar and dancing added (the plaza has spots for them). |

Balance rule used for stances: every stance offends at least one value, and every policy's city effects add up to between +2 and +6.
