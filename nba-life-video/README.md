# My Life as an NBA Player (Animated)

Generates a ~16 minute cartoon video for the **Courtside Stories** YouTube channel, with text-to-speech narration, subtitles, chapter titles, background music and crowd noise.

- `story.py` – the script (chapters, narration lines, actions per scene)
- `render.py` – draws every frame with Pillow, makes TTS with espeak-ng/MBROLA, mixes audio, encodes with ffmpeg
- `thumbnail.py` – YouTube thumbnail

```bash
sudo apt-get install -y espeak-ng mbrola mbrola-us2 ffmpeg
pip install pillow numpy
python3 render.py build      # -> build/my_life_as_an_nba_player.mp4
python3 thumbnail.py thumbnail.png
```

Edit `story.py` to change the story; set `TTS_SPEED` (default 165) to make the narration faster or slower.
