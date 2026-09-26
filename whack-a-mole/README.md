# Whack-a-Mole

A tiny browser game in one HTML file with no dependencies.

## Play

Open `index.html` in any browser. Or serve it locally:

```sh
python3 -m http.server -d whack-a-mole 8000
# then visit http://localhost:8000
```

## How it works

- Rounds last 30 seconds. Press **Start** or hit **Space**.
- Click a mole, or press keys **1–9** (numpad layout: 7 8 9 is the top row).
- A hit is +1, a miss is −1 (never below 0).
- Moles pop up more often and hide sooner as the clock runs down.
- Your best score is stored in the browser's `localStorage`.

## Ideas to extend it

- Add a golden mole worth 5 points, or a bomb that costs points.
- Play a sound on hit with the Web Audio API.
- Add difficulty levels that change `ROUND_SECONDS` and the speed curve.
