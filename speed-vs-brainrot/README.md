# Speed vs Brainrot: HUD

`src/SpeedVsBrainrot_HUD.client.lua` is a LocalScript for **StarterPlayer > StarterPlayerScripts**, next to the game's `SpeedVsBrainrot_Client`. It works with the existing server script (no server changes needed).

- **Stat tiles** (left): 👟 Speed, 💵 Cash, 🏆 Trophies on studded brick tiles; numbers count up and the tile bounces when they rise.
- **Buttons**: 🌀 Teleport (spawn / speed pad / eggs), 🦇 3x Cash gamepass with its live Robux price ("ONLY ⏣9!"), 👥 Invite ("Play with friends!"), 🐶 Pets (your pets, their cash bonus, Fuse 3 → Golden → Rainbow).
- **Collecting cash**: a cash brick with "+545" pops up on screen, wiggles and flies into the Cash tile, and a green swirl spins around the player who grabbed it (everyone sees it).
- **Trophies**: a gold "🏆 +3" banner slides down at the top.

If the old client already draws stat boxes, remove them so they don't show twice.
