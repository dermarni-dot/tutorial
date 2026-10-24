# Wiring the 14 new drawn Boxer faces

The art, the upload and the data are done; this is what is left to wire, in the files the face-removal agent owns
(`src/shared/BodyTiers.lua`, `src/client/modules/FaceFX.lua`, `src/shared/BuilderHead.lua`, and their sim tests).

* PNGs: `tools/body/out/faces/face_wcb_<key>.png` (1254 x 1254 RGBA, the user's canvas, ink and eye registration),
  drawn by `tools/body/wcb_faces_draw.py` (re-run it to redraw; it rewrites `faces.json` through `faces.write_json`).
* Registered in `tools/body/out/faces/faces.json` (`faces.py` `pack_entries()` lists them after the user's four),
  uploaded by `tools/body/publish_body.py` (group 524947123), all 14 **Approved / Active**.
* `src/shared/BodyAssetData.lua` regenerated: the diff only adds 14 `faces` entries (with `creator`).
* Ids also in `tools/body/wcb_faces_manifest.json` (with `features_px` per face).
* Previews: `previews/final/v9/wcb_faces2/` (the lineup is `00_lineup.jpg`).

## The faces

| key | name | image id | role | moderation |
|---|---|---|---|---|
| `wcb_confident` | Boxer Confident | 128064263185676 | creator | Approved |
| `wcb_grin` | Boxer Grin | 122901636746556 | creator | Approved |
| `wcb_cool` | Boxer Cool | 101616530546336 | creator | Approved |
| `wcb_wink` | Boxer Wink | 90728048091208 | creator | Approved |
| `wcb_stern` | Boxer Stern | 101255929551842 | creator | Approved |
| `wcb_determined` | Boxer Determined | 78331766537954 | creator | Approved |
| `wcb_toothy` | Boxer Toothy Grin | 139013764083343 | creator | Approved |
| `wcb_scarred` | Boxer Scarred | 116046602465581 | creator | Approved |
| `wcb_shout` | Boxer Shout | 93250063512830 | mood only | Approved |
| `wcb_hurt` | Boxer Hurt | 126463125778150 | mood only | Approved |
| `wcb_dazed` | Boxer Dazed | 132872399750334 | mood only | Approved |
| `wcb_ko` | Boxer KO | 122518228264182 | mood only | Approved |
| `wcb_tired` | Boxer Tired | 70932305441688 | mood only | Approved |
| `wcb_surprised` | Boxer Surprised | 70510565356748 | mood only | Approved |

What each one is:

* `wcb_confident`: neutral eyes; viewer-left brow level, viewer-right brow (character's left, -X) raised and arched; small closed smile rising to the viewer's right.
* `wcb_grin`: neutral eyes, brows a little raised; wide open D smile (solid ink).
* `wcb_cool`: half-lidded eyes (oval cut flat at y 566 px + a 28 px lid line), low flat brows; slight smile off to the viewer's right.
* `wcb_wink`: viewer-left eye open; viewer-right eye (character's left, -X) shut as a 30 px lid arc, its brow pulled down; closed smile.
* `wcb_stern`: heavy (38 px) flat low brows, eye tops cut flat; straight mouth line.
* `wcb_determined`: brows down at the nose, eyes cut by a slanted lid; short tight line.
* `wcb_toothy`: neutral eyes, raised brows; open smile with an ink border, white teeth and a line between the rows (grit's teeth style).
* `wcb_scarred`: neutral, plus a scar through the viewer-right brow (character's left, -X): a gap with a thin slash.
* `wcb_shout`: steep angry brows, slanted lids; wide open roaring mouth (rounded box), top teeth white.
* `wcb_hurt`: eyes squeezed shut as > < chevrons, worried brows; lopsided clenched-teeth wince.
* `wcb_dazed`: spiral eyes (20 px stroke, r ~60 px), uneven brows; wavy mouth.
* `wcb_ko`: X eyes (30 px strokes, +-42 px), raised brows; slack open frown (solid ink).
* `wcb_tired`: droopy heavy lids (outer ends lower) + lid lines, drooping brows; small open panting mouth.
* `wcb_surprised`: larger round-ish eyes (88 x 128 px), high arched brows; small o mouth (solid).

## 0. Land the data and the wiring together

With the new `BodyAssetData.lua` but today's `BodyTiers`, the eight new resting faces (`creator = true`, not yet in
`STYLE_INDEX`) leak into `BodyTiers.Pickable` (the classic face.key picker), and `tools/sim/test_bodytiers.luau`
fails exactly one check: `10 creator faces, smile first` (it lists `... stern,wcb_confident,...,wcb_scarred`).
Adding all 14 keys to `STYLE_INDEX` (sections 1 and 2) fixes it; then update the test's style list
(`styles: the 4 Boxer faces ...`) to the 12 offered faces.

## 1. BodyTiers.STYLE_KEYS (the faces the Creator offers, in order)

The user's four first (unchanged), then the eight new resting faces:

```lua
BodyTiers.STYLE_KEYS = {
	"wcb_neutral", "wcb_focused", "wcb_smirk", "wcb_grit",
	"wcb_confident", "wcb_grin", "wcb_cool", "wcb_wink", "wcb_stern", "wcb_determined", "wcb_toothy", "wcb_scarred",
}
```

## 2. The mood-only faces (not offered; FaceFX swaps to them)

```lua
BodyTiers.STYLE_MOOD_KEYS = { "wcb_shout", "wcb_hurt", "wcb_dazed", "wcb_ko", "wcb_tired", "wcb_surprised" }
```

**This needs a small code change, not only data:** today `BodyTiers.IsDrawnStyle(k)` (and so `StyleMoodFace`) only
accepts keys in `STYLE_INDEX`, which is built from `STYLE_KEYS`. A mood face that is not in the index is rejected and
the boxer keeps the chosen face. Suggested:

* build `STYLE_INDEX` from `STYLE_KEYS` **and** `STYLE_MOOD_KEYS` (so `IsDrawnStyle`, `StyleMoodFace`, and the
  `Pickable` exclusion of drawn keys see them all);
* keep `FaceStyles()` (the Creator list) and `DefaultStyle()` iterating `STYLE_KEYS` only;
* where a saved `look.face.style` is validated (Looks sanitizer / `IsDrawnStyle` callers on the server), accept only
  `STYLE_KEYS`, so a mood-only face can never be saved as a player's chosen face (e.g. an `IsOfferedStyle(k)` that
  checks `STYLE_KEYS` membership + uploaded id).

`faces.json` / `BodyAssetData.faces` already carry `creator = false` for the six, so a data-driven check
(`f.creator`) works as well as the hard-coded list.

## 3. Proposed BodyTiers.STYLE_MOODS

Mood names are `BodyTiers.MOODS` / `expressions` names plus FaceFX's `guard` / `train` (FaceFX `decalMood`: down ->
`ko` / `stunned`, pain -> `hurt`, a shout -> `angry`, effort -> `effort`).

```lua
BodyTiers.STYLE_MOODS = {
	neutral = nil, rest = nil,                               -- the boxer's own chosen face
	guard = "wcb_focused", block = "wcb_focused",
	attack = "wcb_determined", train = "wcb_determined",
	effort = "wcb_grit",
	hurt = "wcb_hurt",                                       -- a big hit (FaceFX: pain > 0.3; shows at once)
	angry = "wcb_shout",                                     -- FaceFX's shout layer, anger
	taunt = "wcb_smirk",
	confident = "wcb_confident",                             -- walkout, faceoff, a confident exchange
	happy = "wcb_grin",                                      -- win, level up, new gear
	celebrate = "wcb_toothy",                                -- belt, KO win
	ko = "wcb_ko",
	stunned = "wcb_dazed", dazed = "wcb_dazed",              -- knocked down / counting / wobbled
	tired = "wcb_tired", lose = "wcb_tired",
	surprised = "wcb_surprised",                             -- (MOODS: fear -> surprised)
}
```

Optional refinement: when the chosen face already *is* the mood's family (a player whose resting face is
`wcb_grin` going `happy`), `StyleMoodFace` could return the chosen face; with this map it simply shows the mapped face,
which is fine since every mapped face exists.

## 4. Eye / brow / mouth positions (Head.DecalLayout, damage and sweat placement)

All 14 keep the pack's registration: **eye sockets at canvas x 443 / 807, y 575** (head-local eyeX +-0.145,
eyeY +0.0415), so `Head.DECAL` (`eyeX 0.145, eyeY 0.0415, eyeW 0.1, eyeH 0.1, browY 0.15, mouthY -0.175,
mouthW 0.2`) stays valid for every face, and **every face's ink is inside the existing `DECAL_INK` boxes**
(eyes |x| 0.085..0.205, y -0.05..0.11; brows |x| 0.02..0.285, y 0.065..0.21; mouth |x| 0..0.2, y -0.235..-0.105),
so `DecalInkHit` keeps skin spots / sweat / cuts off all of them unchanged. No per-face layout is required.

Head-local fractions below (x = 0.5 - u, y = 0.5 - v; +x = the canvas's left = the character's right; "L" = the
canvas-left feature). Centres are alpha-weighted ink centres; boxes are the alpha >= 128 ink.

| face | eye ink centres L / R | eye ink L / R | brows L / R | mouth ink | mouth centre |
|---|---|---|---|---|---|
| `wcb_neutral` | (+0.1470, +0.0415) / (-0.1439, +0.0415) | |x| 0.119..0.175, y -0.009..+0.092 / |x| 0.116..0.172, y -0.009..+0.092 | |x| 0.082..0.214, y +0.137..+0.166 / |x| 0.081..0.212, y +0.137..+0.166 | |x| 0.000..0.072, y -0.194..-0.170 | (+0.0003, -0.1819) |
| `wcb_focused` | (+0.1455, +0.0427) / (-0.1429, +0.0428) | |x| 0.089..0.171, y -0.002..+0.097 / |x| 0.087..0.169, y -0.002..+0.097 | |x| 0.077..0.236, y +0.098..+0.174 / |x| 0.076..0.234, y +0.098..+0.174 | |x| 0.000..0.075, y -0.195..-0.160 | (-0.0012, -0.1759) |
| `wcb_smirk` | (+0.1470, +0.0417) / (-0.1442, +0.0413) | |x| 0.120..0.174, y -0.007..+0.091 / |x| 0.117..0.171, y -0.007..+0.090 | |x| 0.078..0.235, y +0.116..+0.176 / |x| 0.085..0.234, y +0.116..+0.153 | |x| 0.000..0.121, y -0.196..-0.119 | (-0.0246, -0.1709) |
| `wcb_grit` | (+0.1466, +0.0418) / (-0.1442, +0.0416) | |x| 0.089..0.175, y -0.012..+0.097 / |x| 0.088..0.172, y -0.012..+0.097 | |x| 0.081..0.215, y +0.098..+0.177 / |x| 0.079..0.213, y +0.098..+0.177 | |x| 0.000..0.108, y -0.220..-0.124 | (+0.0004, -0.1727) |
| `wcb_confident` | (+0.1471, +0.0419) / (-0.1431, +0.0419) | |x| 0.119..0.175, y -0.008..+0.092 / |x| 0.115..0.171, y -0.008..+0.092 | |x| 0.081..0.211, y +0.132..+0.159 / |x| 0.077..0.207, y +0.141..+0.183 | |x| 0.000..0.082, y -0.199..-0.144 | (-0.0052, -0.1763) |
| `wcb_grin` | (+0.1471, +0.0419) / (-0.1431, +0.0419) | |x| 0.119..0.175, y -0.008..+0.092 / |x| 0.115..0.171, y -0.008..+0.092 | |x| 0.081..0.211, y +0.140..+0.171 / |x| 0.077..0.207, y +0.140..+0.171 | |x| 0.000..0.093, y -0.224..-0.140 | (+0.0012, -0.1791) |
| `wcb_cool` | (+0.1471, +0.0334) / (-0.1431, +0.0334) | |x| 0.100..0.194, y -0.008..+0.060 / |x| 0.096..0.190, y -0.008..+0.060 | |x| 0.081..0.211, y +0.124..+0.152 / |x| 0.077..0.207, y +0.124..+0.152 | |x| 0.000..0.079, y -0.197..-0.153 | (-0.0104, -0.1792) |
| `wcb_wink` | (+0.1471, +0.0419) / (-0.1431, +0.0390) | |x| 0.119..0.175, y -0.008..+0.092 / |x| 0.091..0.195, y +0.017..+0.062 | |x| 0.081..0.211, y +0.144..+0.179 / |x| 0.077..0.207, y +0.122..+0.152 | |x| 0.000..0.079, y -0.202..-0.150 | (-0.0022, -0.1781) |
| `wcb_stern` | (+0.1471, +0.0400) / (-0.1431, +0.0400) | |x| 0.119..0.175, y -0.008..+0.085 / |x| 0.115..0.171, y -0.008..+0.085 | |x| 0.068..0.224, y +0.111..+0.148 / |x| 0.064..0.220, y +0.111..+0.148 | |x| 0.000..0.077, y -0.195..-0.172 | (+0.0012, -0.1838) |
| `wcb_determined` | (+0.1474, +0.0351) / (-0.1435, +0.0351) | |x| 0.119..0.175, y -0.008..+0.074 / |x| 0.115..0.171, y -0.008..+0.074 | |x| 0.079..0.214, y +0.101..+0.169 / |x| 0.075..0.210, y +0.101..+0.169 | |x| 0.000..0.060, y -0.198..-0.171 | (+0.0012, -0.1846) |
| `wcb_toothy` | (+0.1471, +0.0419) / (-0.1431, +0.0419) | |x| 0.119..0.175, y -0.008..+0.092 / |x| 0.115..0.171, y -0.008..+0.092 | |x| 0.081..0.211, y +0.141..+0.174 / |x| 0.077..0.207, y +0.141..+0.174 | |x| 0.000..0.096, y -0.220..-0.138 | (+0.0012, -0.1754) |
| `wcb_scarred` | (+0.1471, +0.0419) / (-0.1431, +0.0419) | |x| 0.119..0.175, y -0.008..+0.092 / |x| 0.115..0.171, y -0.008..+0.092 | |x| 0.081..0.211, y +0.135..+0.163 / |x| 0.077..0.207, y +0.113..+0.179 | |x| 0.000..0.084, y -0.193..-0.170 | (+0.0008, -0.1814) |
| `wcb_shout` | (+0.1455, +0.0356) / (-0.1415, +0.0356) | |x| 0.081..0.175, y -0.008..+0.097 / |x| 0.077..0.171, y -0.008..+0.097 | |x| 0.081..0.212, y +0.098..+0.175 / |x| 0.077..0.208, y +0.098..+0.175 | |x| 0.000..0.076, y -0.231..-0.125 | (+0.0012, -0.1782) |
| `wcb_hurt` | (+0.1522, +0.0419) / (-0.1482, +0.0419) | |x| 0.108..0.188, y +0.001..+0.083 / |x| 0.104..0.184, y +0.001..+0.083 | |x| 0.081..0.211, y +0.125..+0.170 / |x| 0.077..0.207, y +0.125..+0.170 | |x| 0.000..0.069, y -0.215..-0.140 | (+0.0004, -0.1774) |
| `wcb_dazed` | (+0.1498, +0.0486) / (-0.1405, +0.0349) | |x| 0.100..0.194, y -0.003..+0.097 / |x| 0.096..0.190, y -0.015..+0.087 | |x| 0.081..0.211, y +0.098..+0.174 / |x| 0.077..0.207, y +0.119..+0.152 | |x| 0.000..0.074, y -0.201..-0.159 | (-0.0003, -0.1808) |
| `wcb_ko` | (+0.1471, +0.0419) / (-0.1431, +0.0419) | |x| 0.102..0.192, y -0.003..+0.087 / |x| 0.098..0.188, y -0.003..+0.087 | |x| 0.081..0.211, y +0.135..+0.173 / |x| 0.077..0.207, y +0.135..+0.173 | |x| 0.000..0.062, y -0.210..-0.142 | (+0.0012, -0.1788) |
| `wcb_tired` | (+0.1467, +0.0267) / (-0.1427, +0.0267) | |x| 0.100..0.194, y -0.008..+0.053 / |x| 0.096..0.190, y -0.008..+0.053 | |x| 0.081..0.211, y +0.119..+0.163 / |x| 0.077..0.207, y +0.119..+0.163 | |x| 0.000..0.042, y -0.212..-0.152 | (+0.0012, -0.1822) |
| `wcb_surprised` | (+0.1471, +0.0419) / (-0.1431, +0.0419) | |x| 0.112..0.182, y -0.009..+0.093 / |x| 0.108..0.178, y -0.009..+0.093 | |x| 0.081..0.211, y +0.146..+0.183 / |x| 0.077..0.207, y +0.146..+0.183 | |x| 0.000..0.026, y -0.215..-0.149 | (+0.0012, -0.1822) |

Where a face differs from the four in a way placement code may care about:

* **Lidded eyes** (`wcb_cool`, `wcb_stern`, `wcb_determined`, `wcb_shout`, `wcb_tired`): the socket is unchanged but
  the visible ink is the lower part of the oval (tired: ink top at y +0.053, centre +0.027; cool +0.06 / +0.033). A
  black-eye / swelling mark centred on the socket still sits right; nothing to change.
* **Shut / non-oval eyes** (`wcb_wink` canvas-right eye = the character's left, -X: a lid arc at y +0.017..+0.062;
  `wcb_hurt` chevrons; `wcb_ko` X's; `wcb_dazed` spirals up to r ~0.05, i.e. |x| 0.096..0.194, y -0.015..+0.097):
  all inside the eye ink box. If SetDamage draws its own drawn-eye marks (BuilderHead's note), they will overlay
  these shapes; consider skipping the "eye opening" part of a black eye on `wcb_ko` / `wcb_hurt` / the wink side.
* **Brows**: `wcb_confident` / `wcb_surprised` brows reach y +0.183 (neutral +0.166), `wcb_stern` brows are 38 px
  thick and reach |x| 0.224. Still inside the brow box; sweat placed above y 0.21 stays clear.
* **Scar** (`wcb_scarred`): a gap + slash in the -X (character's left) brow at |x| ~0.15..0.17, y +0.113..+0.179.
  A brow cut from SetDamage on that side lands on the drawn scar; prefer `cutSide = +1` or accept the overlap.
* **Open mouths** reach lower than the four's closed mouths (neutral bottom -0.194): `wcb_shout` -0.231,
  `wcb_grin` -0.224, `wcb_toothy` -0.220, `wcb_hurt` -0.215, `wcb_surprised` -0.215, `wcb_tired` -0.212,
  `wcb_ko` -0.210 (grit -0.220). The moustache / lip-cut placement keyed on `mouthY -0.175` is still centred; if the
  moustache sits on the upper lip it is unaffected, but a chin/lip mark below the mouth should start below -0.235
  (the `DECAL_INK` mouth box already does).

## Tools touched (not game code)

* `tools/body/wcb_faces_draw.py` (new): the drawing (style constants measured from the user's PNGs).
* `tools/body/faces.py`: `pack_entries()` also lists `wcb_faces_draw.DRAWN`.
* `tools/sim/v9_faces.luau`: `--set wcb2` (all 18 drawn faces x light / mid / dark skin, bald; built with the style
  `wcb_neutral` so it works on any src, the exported decal file swapped to each face's PNG).
