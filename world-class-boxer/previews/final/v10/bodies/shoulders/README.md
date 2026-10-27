# The shoulder junction (v17)

`shoulders_<front,side,back,34,guard_front,guard_34>_t<1,5>.png`: Lean / Muscular / Power Build / Heavyweight Build,
the right shoulder close up. Top row: the v16 build that shipped before this change. Bottom row: the uploaded v17
build.

What changed:

* **Shoulder caps.** The UpperTorso now owns a cap on each side that runs from the trapezius out over the deltoid.
  * The arm's dome turns under the cap at rest, through pitch -30..90 and abduction -10..60, and in the guard pose.
  * The cap's interior is a smooth envelope of the dome's furthest reach over those poses.
  * Toward the edge, the cap tucks 0.012 studs under the arm and the torso, so the edge never shows.
  * Near the edge, the shading takes the normals of the surface underneath.
* **Body shape tweaks.** These were in the previous round and are now exported:
  * the armpit hollow, moved just under the widest ring so the body's width stays the same as v16;
  * the coracobrachialis toward the armpit;
  * the lat's sweep;
  * the forearm's top matched to the upper arm's radius at the elbow.

## Fighting numbers

The caps widen the UpperTorso mesh box in X only, which changes `MeshPart.Size.X`.

* **Hit detection and spacing:**
  * The body's own box is recorded as `core` in BodyAssetData.
  * BuilderTiers turns it into the `BodyCoreSize` attribute.
  * HitGeometry and every other reader that means the body's width read that attribute instead of `Size`.
* **Mass:** the density is scaled by core volume / box volume, so the UpperTorso weighs the same as before.
* **Ragdoll:** the UpperTorso's ragdoll collider is sized from the core box.
* **Proof:** on rigs assembled from BodyAssetData, HEAD vs now, the worst `HitGeometry.Frame` field difference over
  25 frame/tier rigs is 0.00025. The worst `MinSep` difference over all 625 pairings is 0.0005.

## Shape check

`build_body.py --check-shape` gates the junction:

| Check | Limit | Result |
| --- | --- | --- |
| Armpit gap at the top of the armpit | 0.06 | -0.036 to -0.114 (closed) |
| Elbow radius ratio, distance from 1 | 0.015 | 1.000 |
| Dome poke through the cap | 0.004 | all negative |
| Cap edge exposed | 0.010 | -0.012 everywhere |
| Poke where the cap is clamped to the box's top | 0.015 | Power Build T5 pitched 90°: 0.0115 |

## Gear

* The referee shirt and coach polo cover every visible cap vertex.
* The sports top's straps stay medial of the caps (x 0.75 at most; the caps start at x 0.80), never under them.

## Skin maps

The skin maps cover the caps through the UV strip v > 0.86 of the UpperTorso map, which is flat smooth skin.
