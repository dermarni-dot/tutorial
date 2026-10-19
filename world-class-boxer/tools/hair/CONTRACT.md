# Asset hair contract

The format shared by the Blender builders (`tools/hair`), the uploader (`publish.py`) and the game
(`src/shared/HairAssetData.lua`, generated, and the client loader).

## Space

Nominal head space, numerically: studs for a 1.2-stud head, +X the character's right, +Y up,
-Z forward (the face), origin at the Head part's centre (the same space AnatomyHair builds in).

**v9: modelled on the classic head** (`ref/classic/`, written by `tools/sim/export_classic.luau` and
`classic_ref.py`): every boxer has the classic Roblox head now (a Part with the Head SpecialMesh,
`BuilderHead.classicHead`, sized by HeadScale: 0.927 studs at Athletic, nominal 1.2). Its shape is the game's
`AnatomyHairKit.CLASSIC` (a vertical cylinder of radius 0.6 filling its 1.2 box, top and bottom edges rounded by
0.24; `Kit.Scalp` of a look with `headShape = "classic"` is this field, centre (0, 0.05, 0)). `ref/classic` holds its
radial table, the game's hairline lines on it (`Kit.ClassicKeys`: the front at 0.421 at the default face, the line
round the ear on the ellipse `Kit.CLASSIC_HAIR.ear`, the nape at -0.3), the `Kit.Cut` coverage grids (fade weight
lines lifted by `Kit.CLASSIC_HAIR.fadeSide` at the side, the burst round the ear), the ears (the built face's
shell + helix, AABBs at earSize +0.5), the brows (`face`: centre y 0.276 at the default face, top 0.305, the highest
the creator makes 0.371) and the head mesh with the face (`head_m.obj`, the collider "Head" = head + ears).
`hairlib.REF` is `ref/classic` (`HAIR_REF=organic`: the retired organic skull `ref/skull.json`, the v7 reference).
The builders' zone tests written for the organic skull read `hairlib.org(p)` (a piecewise-linear map of the classic
head's landmarks onto the organic ones); geometry is always built on the classic head itself.

At runtime every piece is placed by:
1. **Skull fit** (affine, per boxer): from the boxer's own skull field (`Kit.Scalp(look)` / `S.ray`)
   take the half-width W (y 0.15, toward +X), the vertex T (straight up from the skull centre), the
   front Fz (y 0.2, toward -Z) and the back Bz (y 0.1, toward +Z), and the same four on the reference
   (`data.fit0`, from the reference's `skull.json` `fit0`). Then `ax = W/W0`, `ay = T/T0` (anchored at y = 0),
   `az = (Bz - Fz)/(Bz0 - Fz0)`, `dz = (Bz + Fz)/2 - (Bz0 + Fz0)/2`.
   * v9: `fit0 = { W = 0.6, T = 0.6, Fz = -0.6, Bz = 0.6, shape = "classic" }` (`HK.FIT0_CLASSIC`). Every classic
     head measures exactly that, so the fit is the identity: the meshes sit on the head as modelled (the cap
     0.020 above it everywhere, the corners of the rounded box included; `check_classic_fit.py`).
   * v7 manifests (`fit0` without `shape`, the organic default male W 0.383, T 0.591, Fz -0.460, Bz 0.520): on a
     classic head `HK.CLASSIC_FIT` goes on top (x 1.06 / 1.2 / 1.2, 0.06 down), the stopgap the v7 meshes need there.
2. **Length / volume** (per style flags, see `length` below), applied in nominal space.
3. **Head size**: `k = Head.Size / 1.2` per axis.

A piece's MeshPart gets `Size = bbox size * fit * k` and is welded to Head at its bbox centre run
through the same transform (Roblox recentres an uploaded mesh on its bounding box).

The cap's painted texels (`HK.CapGrid`) are read on the reference head the cap was modelled on (`fit0.shape`:
the classic head's rays from (0, 0.05, 0), else the organic skull's), through the fit, onto the boxer's scalp.

## Textures (uploaded as Image assets; greyscale albedo, straight alpha)

| key | strips (u ranges) | used for |
|---|---|---|
| `straight` | dense 0-.25, medium .25-.5, wispy .5-.75, wavy .75-1 | long hair, crop tops |
| `coily` | tight 0-.5, loose .5-1 | afro, high top, curly |
| `braid` | plait strips (see build_braids.py) | braids, box braids, cornrow tails |
| `loc` | loc 0-.375 (core .031-.344, two u-periods), twist .375-.75 (core .406-.719), frizz .75-1; v root to tip, NOT tiled | dreadlocks, short dreads, twists |
| `cornrow` | row 0-.75 (tileable in v), baby hairs .75-1 | cornrows |
| `short` | tile 0-1 (tileable both ways) | the scalp cap for straight / wavy hair |
| `shortcoil` | tile (tileable) | the scalp cap for curly / kinky / coiled hair |
| `waves` | one whole-cap image on the polar UV (not tileable) | the scalp cap for 360 Waves (`capTile = "waves"`, `capTileRepeat = {1, 1}`) |
| `crop` | 4 tuft strips, root to tip | crop tops on straight / wavy fades |
| `clump` | one tileable fibre mottle, v root (0) to tip (1) across a piece (not a strip atlas) | the v10 stylised clumps (build_stylised.py): curly fade tops, afros, twists, locs, cornrow plaits |
| `cap` | (not uploaded) | the boxer's painted cap image: pieces in the cap's polar UV (fur shells) |

UVs: (0,0) is the top-left texel, v grows down. Card strips: roots at v = 0, tips at v = 1.

The game multiplies the greyscale by the hair colour in an EditableImage (dyes by v: Tips, Ombre;
Streaks by u bands) and keeps the alpha. `Config.HairAssets.flipV` flips the image if a client ever
shows them upside down.

## The scalp cap

One shared cap mesh (`cap` style entry) covers the scalp from the forehead to the nape, at 0.012-0.02
nominal above the skull (v9: 0.020 above the classic head, `thetaMax` 130 degrees from its centre; the v7 cap
reached 148 degrees on the organic skull). UV is polar: `u = az / 2pi` (az = 0 at the back, increasing toward +X),
`v = theta / CAP_THETA` (theta from +Y). The game paints its texture per boxer: a tile
(the entry's `capTile`, else `shortcoil` for curly types, else `short`) repeated
`tile = {nu, nv}` times, tinted, with alpha = tile alpha x the style's coverage mask (the same
fade / hairline / growth coverage the generated HairCap uses, `Kit.Cut(...).cov`, evaluated at each
texel's scalp point). So every fade height, hairline kind, line-up and growth stage comes from the
game's own rules. The fade thins the tile's strands by rank (thresholded) rather than making them
uniformly translucent. `out/cap/style.json` carries `thetaMax`, `tile` and `tiles`; pieces with
`tex = "cap"` (fur shells) share the painted image; a shell's `capShell = {rank, cov}` paints it a
sparser variant (its strands give way first as coverage drops). `pole = {theta0, theta1, su, sv}` makes
the crown sample the tile from a flat projection (no 8-fold star where the polar repeats meet).

## Style entry (`out/<key>/style.json`, then the manifest)

```
{ key, styles = ["Afro", ...],           -- Looks.HairStyles ids this entry draws
  types = ["Kinky", "Coiled"] | null,    -- hair types it is for (null: every type)
  cap = { cut = "style" | "full" | "none", density = 0..1 },  -- how the scalp cap is painted
  capTile = "waves" | ...,               -- optional: the cap's tile texture (default by hair type)
  capTileRepeat = { nu, nv },            -- optional: the tile's repeats ({1, 1}: a whole-cap image)
  capFade = "fade" | ...,                -- optional: a Kit.FADES gradient on a natural hairline
  pieces = { Name = {
      mesh_file, tex,                    -- texture key (above)
      bbox = [cx, cy, cz, sx, sy, sz],   -- nominal
      nv, nt, points = [x, y, z, ...],   -- nominal point cloud for HairFX's body tests
      hairfx = { kind = "swing"|"bounce", chain, seg, parent, stiff, mass, pivot = [x,y,z], tip = [x,y,z] },
      hideUnder = { headgear = false, hood = true },
      length = "hang" | "volume" | null, -- hang: stretched in y about hairfx.pivot (or the bbox top) by
                                         -- the look's length; volume: scaled about the skull centre
      material = "SmoothPlastic", castShadow = true } } }
```

Piece names follow AnatomyHair (`HairCap`, `HairTop`, `HairLocNN` / `HairLocNNb`, `HairBraidNN`,
`HairClumpNN`, `HairTail01` ...), at most 16 pieces per style (full detail).
