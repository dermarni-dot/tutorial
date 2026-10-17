# Asset hair contract

The format shared by the Blender builders (`tools/hair`), the uploader (`publish.py`) and the game
(`src/shared/HairAssetData.lua`, generated, and the client loader).

## Space

Nominal head space, numerically: studs for a 1.2-stud head, +X the character's right, +Y up,
-Z forward (the face), origin at the Head part's centre (the same space AnatomyHair builds in).
Modelled on the default male skull (`ref/skull.json`).

At runtime every piece is placed by:
1. **Skull fit** (affine, per boxer): from the boxer's own skull field (`Kit.Scalp(look)` / `S.ray`)
   take the half-width W (y 0.15, toward +X), the vertex T (straight up from the skull centre), the
   front Fz (y 0.2, toward -Z) and the back Bz (y 0.1, toward +Z), and the same four on the default
   male skull (`skull.json` `fit0`). Then `ax = W/W0`, `ay = T/T0` (anchored at y = 0),
   `az = (Bz - Fz)/(Bz0 - Fz0)`, `dz = (Bz + Fz)/2 - (Bz0 + Fz0)/2`. Residual is at most 0.015
   nominal, so every scalp-hugging layer sits at least 0.02 nominal above the scalp.
2. **Length / volume** (per style flags, see `length` below), applied in nominal space.
3. **Head size**: `k = Head.Size / 1.2` per axis.

A piece's MeshPart gets `Size = bbox size * fit * k` and is welded to Head at its bbox centre run
through the same transform (Roblox recentres an uploaded mesh on its bounding box).

## Textures (uploaded as Image assets; greyscale albedo, straight alpha)

| key | strips (u ranges) | used for |
|---|---|---|
| `straight` | dense 0-.25, medium .25-.5, wispy .5-.75, wavy .75-1 | long hair, crop tops |
| `coily` | tight 0-.5, loose .5-1 | afro, high top, curly |
| `braid` | plait 0-.5, loc .5-1 (tileable in v) | braids, box braids, locs, twists |
| `cornrow` | row 0-.75 (tileable in v), baby hairs .75-1 | cornrows |
| `short` | tile 0-1 (tileable both ways) | the scalp cap for straight / wavy hair |
| `shortcoil` | tile (tileable) | the scalp cap for curly / kinky / coiled hair |
| `waves` | tile (tileable) | the scalp cap for 360 Waves (`capTile = "waves"`) |
| `crop` | 4 tuft strips, root to tip | crop tops on straight / wavy fades |
| `cap` | (not uploaded) | the boxer's painted cap image: pieces in the cap's polar UV (fur shells) |

UVs: (0,0) is the top-left texel, v grows down. Card strips: roots at v = 0, tips at v = 1.

The game multiplies the greyscale by the hair colour in an EditableImage (dyes by v: Tips, Ombre;
Streaks by u bands) and keeps the alpha. `Config.HairAssets.flipV` flips the image if a client ever
shows them upside down.

## The scalp cap

One shared cap mesh (`cap` style entry) covers the scalp from the forehead to the nape, at 0.012-0.02
nominal above the skull. UV is polar: `u = az / 2pi` (az = 0 at the back, increasing toward +X),
`v = theta / CAP_THETA` (theta from +Y). The game paints its texture per boxer: a tile
(the entry's `capTile`, else `shortcoil` for curly types, else `short`) repeated
`tile = {nu, nv}` times, tinted, with alpha = tile alpha x the style's coverage mask (the same
fade / hairline / growth coverage the generated HairCap uses, `Kit.Cut(...).cov`, evaluated at each
texel's scalp point). So every fade height, hairline kind, line-up and growth stage comes from the
game's own rules. The fade thins the tile's strands by rank (thresholded) rather than making them
uniformly translucent. `out/cap/style.json` carries `thetaMax`, `tile` and `tiles`; pieces with
`tex = "cap"` (fur shells) share the painted image.

## Style entry (`out/<key>/style.json`, then the manifest)

```
{ key, styles = ["Afro", ...],           -- Looks.HairStyles ids this entry draws
  types = ["Kinky", "Coiled"] | null,    -- hair types it is for (null: every type)
  cap = { cut = "style" | "full" | "none", density = 0..1 },  -- how the scalp cap is painted
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
