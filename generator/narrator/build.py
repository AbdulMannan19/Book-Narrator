"""Generate chaptered audio + a book.json with sentence-level timestamps."""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

import numpy as np
from tqdm import tqdm

from .extract import extract_book
from .segment import segment_paragraphs
from .tts import DIALOGUE, NARRATION, TITLE, Narrator

SENTENCE_PAUSE = 0.30
PARAGRAPH_PAUSE = 0.75
TITLE_PAUSE = 1.2


def _slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")[:40] or "chapter"


def _encode_m4a(audio: np.ndarray, sr: int, out: Path) -> None:
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "f32le", "-ar", str(sr), "-ac", "1", "-i", "pipe:0",
        "-c:a", "aac", "-b:a", "64k", "-movflags", "+faststart", str(out),
    ]
    subprocess.run(cmd, input=audio.tobytes(), check=True)


def build_book(src: Path, out_root: Path, voice: Path | None, max_chapters: int | None,
               max_chars: int | None, device: str) -> Path:
    title, chapters = extract_book(src)
    if max_chapters:
        chapters = chapters[:max_chapters]
    out = out_root / _slug(title)
    out.mkdir(parents=True, exist_ok=True)
    print(f"'{title}': {len(chapters)} chapters -> {out}")

    narrator = Narrator(voice_prompt=voice, device=device)
    sr = narrator.sr
    manifest = {"title": title, "sample_rate": sr, "chapters": []}

    for ci, ch in enumerate(chapters, 1):
        stem = f"{ci:03d}-{_slug(ch['title'])}"
        audio_name, json_name = f"{stem}.m4a", f"{stem}.json"
        cached = out / json_name
        if cached.exists() and (out / audio_name).exists():  # resume support
            manifest["chapters"].append(json.loads(cached.read_text(encoding="utf-8"))["meta"])
            print(f"[{ci}/{len(chapters)}] {ch['title']}: already done, skipping")
            continue

        paragraphs = ch["paragraphs"]
        if max_chars:  # quick test mode
            paragraphs, total = [], 0
            for p in ch["paragraphs"]:
                paragraphs.append(p)
                total += len(p)
                if total >= max_chars:
                    break

        segs = segment_paragraphs(paragraphs)
        pieces: list[np.ndarray] = []
        sentences: list[dict] = []
        t = 0.0

        def add(wav: np.ndarray, pause: float, text: str, kind: str):
            nonlocal t
            start = t
            pieces.append(wav)
            t += len(wav) / sr
            sentences.append({"text": text, "start": round(start, 3), "end": round(t, 3), "kind": kind})
            gap = np.zeros(int(pause * sr), dtype=np.float32)
            pieces.append(gap)
            t += pause

        add(narrator.speak(ch["title"], TITLE), TITLE_PAUSE, ch["title"], "title")
        for seg in tqdm(segs, desc=f"[{ci}/{len(chapters)}] {ch['title'][:40]}", unit="sent"):
            settings = DIALOGUE if seg.kind == "dialogue" else NARRATION
            wav = narrator.speak(seg.text, settings)
            add(wav, PARAGRAPH_PAUSE if seg.para_end else SENTENCE_PAUSE, seg.text, seg.kind)

        _encode_m4a(np.concatenate(pieces), sr, out / audio_name)
        meta = {"title": ch["title"], "audio": audio_name, "data": json_name, "duration": round(t, 3)}
        cached.write_text(json.dumps({"meta": meta, "sentences": sentences}, ensure_ascii=False), encoding="utf-8")
        manifest["chapters"].append(meta)
        (out / "book.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    (out / "book.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Done. Copy the folder to your phone: {out}")
    return out
