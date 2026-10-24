# The shoulder junction (v17, NOT shipped: needs a decision)

`shoulders_<front,side,back,34,guard_front,guard_34>_t<1,5>.png`: Lean / Muscular / Power Build / Heavyweight Build,
the right shoulder close up, the uploaded build ("before") over the current build_body.py ("after": the armpit hollow,
the coracobrachialis toward the armpit, the lat's sweep further down, the forearm's top matched to the upper arm's
radius at the elbow in game space). Not exported or uploaded: the change is small and the main fix is blocked.

Why the arm still reads as hung on: the deltoid dome overhangs the ribcage (Lean's torso ends at x 0.75, its shoulder
pivot is at 0.90) and rises 0.1-0.2 studs above the torso's top there. A real shoulder needs the UpperTorso to own the
acromion / trapezius out over the dome (a cap the dome tucks under). That widens the UpperTorso mesh's bounding box =
its MeshPart Size, and HitGeometry reads `UpperTorso.Size.X` as the torso's width (`torsoHalfW`, `shoulderHalf`), so
it would change hit detection. A cap kept inside the current box only reaches the trapezius and its crossing with the
dome shows as a crack (tried, removed). Options: (a) HitGeometry reads a core width (an attribute BuilderTiers would set
from BodyAssetData) and the cap goes in; (b) accept the wider torso in HitGeometry and re-fit it.
