# Your Life as an NBA Player (Animated)

Generates a ~16 minute cartoon video told in second person ("you") for the **Courtside Stories** YouTube channel, with text-to-speech narration, subtitles, chapter titles, background music and crowd noise.

- `story.py` – the script (chapters, narration lines, actions per scene)
- `render.py` – draws every frame with Pillow, makes TTS with espeak-ng/MBROLA, mixes audio, encodes with ffmpeg
- `thumbnail.py` – YouTube thumbnail

```bash
sudo apt-get install -y espeak-ng mbrola mbrola-us2 ffmpeg
pip install pillow numpy
python3 render.py build      # -> build/your_life_as_an_nba_player.mp4
python3 thumbnail.py thumbnail.png
```

Edit `story.py` to change the story; set `TTS_SPEED` (default 165) to make the narration faster or slower.

## YouTube Short

`shorts.py` makes a vertical 1080x1920, 60 fps, under-60-second Short from the same art: a "watch till the end" hook, 10 quick levels, and a "Level 11" ending that unlocks with an animated like + subscribe button.

```bash
python3 shorts.py build_shorts   # -> build_shorts/your_life_as_an_nba_player_short.mp4
```

### Natural voice (Kokoro) and sound effects

The Short uses the free [Kokoro](https://github.com/thewh1teagle/kokoro-onnx) voice instead of espeak, and adds sound effects synced to the animation (dribbles, swish, dunk slam, crowd cheers, applause and camera shutters at the draft, sad trombone, level-up chime, like/subscribe clicks and bell).

```bash
pip install kokoro-onnx soundfile
mkdir -p models/kokoro && cd models/kokoro
curl -LO https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx
curl -LO https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin
cd ../..
KOKORO_DIR=models/kokoro KOKORO_SPEED=1.3 python3 shorts.py build_shorts
```

`KOKORO_VOICE` picks the voice (default `am_michael`; try `af_heart`, `am_fenrir`, `am_puck`). Leave `KOKORO_DIR` unset to fall back to espeak. The same variables work for `render.py`.
