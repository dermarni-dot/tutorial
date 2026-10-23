# v10: the crowd and the stands

Offline Cycles renders (`tools/sim/crowd_scene.luau` -> `tools/sim/crowd_render.py`) of the fight venues as
`Venues.New` builds them, with the client's `CrowdFX` run on the dump (the printed rows and the upper bowl drawn,
every rig posed). Approximate lighting, no Roblox material textures; the heads are the renderer's stand-in for the
classic head mesh. Nothing in the repo was changed to make them.

| File | What it shows |
|---|---|
| `01_stadium_ringside_max.jpg` | Stadium, world title night (packed): from the apron over the ringside chairs, row 1, the printed rows, the VIP boxes, the standing-room rail and the bowl |
| `02_stadium_wide_max.jpg` | Stadium packed, wide: every seat full, the standing room open, the bowl tiers full |
| `03_stadium_wide_low.jpg` | The same stadium at a 0.41 house (`Venues.CrowdFill(0.2, 10)`): the front rows fill first, the back rows and the bowl thin out, no standing room |
| `04_stadium_react.jpg` | 0.9 s into a knockdown of the opponent: the wave has reached ~60 studs out; ringside up out of the chairs, arms up, phones up, the opponent's fans booing, the printed rows' arms swinging up |
| `05_arena_ringside_max.jpg` | Arena packed, the usual venue view |
| `06_arena_stands_max.jpg` | Arena packed, from the ring: ringside chairs, media box, camera platform, sponsor boards, LED fascias |
| `07_arena_stands_low.jpg` | The same at the 0.41 house |
| `08_club_ringside_low.jpg` | Club show at the 0.41 house |
| `09_club_stands_max.jpg` | Club packed, from the ring: the VIP box on the walkway-free side, the photographers' pit |
| `10_community_max.jpg` | The community hall packed: folding chairs, standers by the door |
| `11_arena_react_close.jpg` | Arena, the knockdown wave close up |
| `12_arena_vip_max.jpg` | Arena: the VIP box (glass rail, leather seats, drinks table) and the rows around it; the drawn faces on the heads |
