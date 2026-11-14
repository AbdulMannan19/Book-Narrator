"""CLI: python narrate.py book.epub [--voice voices/narrator.wav] [--out output]"""
import argparse
from pathlib import Path

from narrator.build import build_book


def main():
    ap = argparse.ArgumentParser(description="Narrate a book with Chatterbox TTS.")
    ap.add_argument("book", type=Path, help=".epub, .pdf or .txt")
    ap.add_argument("--out", type=Path, default=Path("output"))
    ap.add_argument("--voice", type=Path, default=None, help="~10s wav of the narrator voice to clone (optional)")
    ap.add_argument("--max-chapters", type=int, default=None, help="only do the first N chapters")
    ap.add_argument("--max-chars", type=int, default=None, help="test mode: only narrate ~N chars per chapter")
    ap.add_argument("--device", default="cuda")
    a = ap.parse_args()
    build_book(a.book, a.out, a.voice, a.max_chapters, a.max_chars, a.device)


if __name__ == "__main__":
    main()
