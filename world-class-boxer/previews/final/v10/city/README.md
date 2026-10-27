# v10 city previews: the town rebuilt at real-world scale

Offline Cycles renders of the server city (CityMap / CityKit / CityShops), the client's local city and the
WorldDetail layer as `tools/sim/world_scene.luau --only city` dumps them, through `tools/world/render_city_v10.py`
(the same scene builder as `tools/sim/world_render.py`; day sky, the night shots switch the NightLight lights on).
Scale: 1 stud = 0.28 m (Config.City). The boxer in the scale shots is the real tier-3 rig exported by
`tools/sim/v8_scene.luau` (6.2 studs tall).

| File | What it shows |
|---|---|
| `01_overview_aerial.jpg` | The whole map: gym campus inside the loop, downtown south, Oak Street and the hills west, the park, river and far bank east, the arena north |
| `02_downtown_aerial.jpg` | Main Street's two rows, 2nd Street's towers, the campus, the arena and the industrial quarter behind |
| `03_main_street_day.jpg` | Street level on Main Street's south sidewalk (12.5-stud lanes, parking lanes, shop fronts, signals) |
| `04_main_street_night.jpg` | The same view after dark: street lights, neon, shop windows |
| `05_champion_ave.jpg` | Champion Ave from Main Street towards the gym: the Walk of Fame, the loop crossing, the forecourt |
| `06_gym_forecourt.jpg` | The entrance plaza in front of the gym: planters, benches, lamps, the welcome board |
| `07_scale_car.jpg` | SCALE: a boxer beside a 16 x 5.7 x 5.4-stud sedan in the member lot (2.7 x 5 m bays) |
| `08_scale_door.jpg` | SCALE: a boxer at Champ's Diner (door 7.5 studs = 2.1 m, 14-stud ground floor) |
| `09_scale_streetlight.jpg` | SCALE: a boxer under a 30-stud (8.4 m) street light on Main Street |
| `10_park_fountain.jpg` | Riverside Park: the fountain plaza, paths, lamps, benches and the trees |
| `11_arena_plaza.jpg` | The Grand Arena (R 120, 70 tall) from its plaza: flags, barriers, ticket booths |
| `12_oak_street.jpg` | Oak Street: two-storey houses with garages and drives, 22-stud residential lights |
| `13_waterfront.jpg` | The promenade, boardwalk, pier and the river with the Foundry Street bridge and the far bank |
| `14_elite_industrial.jpg` | The Elite Performance Center, Elite Way, the warehouses and the construction crane |
| `15_estates.jpg` | Hillcrest Estates' gate at the top of Oak Street |
| `16_plan_campus.jpg` | Plan of the campus (north is down): loop road, forecourt, parking, plaza, yard, training field |
