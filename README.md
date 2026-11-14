# Book-Narrator

Free, open-source audiobook maker. A monorepo with two parts:

- **`generator/`** (Python, runs on your PC): turns an EPUB/PDF/TXT into chaptered, expressively narrated audio using [Chatterbox TTS](https://github.com/resemble-ai/chatterbox), plus a `book.json` with sentence-level timestamps.
- **`app/`** (Flutter, Android/Windows): a player that imports that folder, highlights the sentence being read, lets you tap to seek, bookmark sentences, and resumes where you left off.

## Generator setup (Windows, NVIDIA GPU)

RTX 50-series (Blackwell) needs PyTorch built for CUDA 12.8+, so install torch *after* chatterbox:

```bash
cd generator
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
pip install --upgrade torch torchaudio --index-url https://download.pytorch.org/whl/cu128
```

Needs `ffmpeg` on PATH.

## Make an audiobook

```bash
python narrate.py path\to\book.epub                     # default voice
python narrate.py book.pdf --voice voices\narrator.wav  # clone a ~10s reference voice
python narrate.py book.epub --max-chapters 1 --max-chars 600   # quick test
```

Output goes to `generator/output/<book-title>/` (`book.json`, one `.m4a` + `.json` per chapter). Re-running resumes: finished chapters are skipped.

Dialogue (quoted text) is read with more expressiveness than narration; tune this in `narrator/tts.py`.

## Player app

```bash
cd app
flutter run -d windows      # or an Android device
```

Copy the whole output folder to your phone, tap **Import book**, and select all its files.
Tap a sentence to jump there, long-press to bookmark.
