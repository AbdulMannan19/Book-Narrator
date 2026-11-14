"""Turn a PDF / EPUB / TXT file into a list of chapters.

Each chapter is {"title": str, "paragraphs": [str, ...]}.
"""
from __future__ import annotations

import re
import unicodedata
from collections import Counter
from pathlib import Path


def extract_book(path: Path) -> tuple[str, list[dict]]:
    ext = path.suffix.lower()
    if ext == ".epub":
        return _from_epub(path)
    if ext == ".pdf":
        return _from_pdf(path)
    if ext in (".txt", ".md"):
        return _from_text(path.read_text(encoding="utf-8", errors="ignore"), path.stem)
    raise ValueError(f"Unsupported file type: {ext}")


_LIGATURE_FIX = {"Й": "fi", "А": "ff", "Г": "ffi", "М": "fl", "Ж": "ffl"}  # broken PDF font maps


def _clean(text: str) -> str:
    text = unicodedata.normalize("NFKC", text).translate(str.maketrans(_LIGATURE_FIX))
    text = text.replace("­", "")  # soft hyphen
    text = re.sub(r"[ \t ]+", " ", text)
    return text.strip()


# Front/back matter we don't want narrated.
_SKIP_RE = re.compile(
    r"title page|copyright|dedication|contents|also by|praise|about the author|"
    r"acknowledg|^cover|newsletter|discover more|excerpt|reading group|a note on",
    re.I,
)


# ---------- EPUB ----------
def _from_epub(path: Path):
    import ebooklib
    from bs4 import BeautifulSoup
    from ebooklib import epub

    book = epub.read_epub(str(path))
    title = (book.get_metadata("DC", "title") or [[path.stem]])[0][0]
    chapters = []
    for item in book.get_items_of_type(ebooklib.ITEM_DOCUMENT):
        soup = BeautifulSoup(item.get_content(), "lxml")
        heading = soup.find(["h1", "h2", "h3"])
        paras = [_clean(p.get_text(" ")) for p in soup.find_all("p")]
        paras = [p for p in paras if len(p) > 1]
        if sum(len(p) for p in paras) < 200:  # skip covers, toc, copyright stubs
            continue
        ch_title = _clean(heading.get_text(" ")) if heading else f"Section {len(chapters) + 1}"
        if _SKIP_RE.search(ch_title):
            continue
        chapters.append({"title": ch_title, "paragraphs": paras})
    return title, chapters


# ---------- PDF ----------
def _from_pdf(path: Path):
    import pymupdf

    doc = pymupdf.open(str(path))
    title = doc.metadata.get("title") or path.stem
    pages = [page.get_text("text").splitlines() for page in doc]

    # Drop running headers/footers: short lines repeated on many pages, and bare page numbers.
    counts: Counter = Counter()
    for lines in pages:
        for l in {x.strip() for x in lines if x.strip()}:
            if len(l) < 60:
                counts[l] += 1
    repeated = {l for l, c in counts.items() if c >= max(4, len(pages) // 4)}

    def page_text(i: int) -> str:
        lines = [
            l.strip() for l in pages[i]
            if l.strip() and l.strip() not in repeated and not re.fullmatch(r"[0-9ivxlc]{1,5}", l.strip(), re.I)
        ]
        width = max((len(l) for l in lines), default=0)
        out = []
        for l in lines:
            out.append(l)
            # A short line that ends a sentence is the last line of a paragraph.
            if width and len(l) < 0.75 * width and re.search(r"[.!?…”\"]$", l):
                out.append("")
        return "\n".join(out)

    # Preferred: use the PDF's own bookmarks as chapters.
    toc = [(t.strip(), pg - 1) for lvl, t, pg in doc.get_toc() if lvl == 1 and pg > 0]
    if len(toc) >= 3:
        chapters = []
        for i, (ctitle, first) in enumerate(toc):
            last = toc[i + 1][1] if i + 1 < len(toc) else len(pages)
            if _SKIP_RE.search(ctitle):
                continue
            raw = "\n".join(page_text(k) for k in range(first, max(last, first + 1)))
            paras = _paragraphs(raw)
            if sum(len(x) for x in paras) < 200:
                continue
            chapters.append({"title": ctitle, "paragraphs": paras})
        if chapters:
            return title, chapters

    raw = "\n\n".join(page_text(i) for i in range(len(pages)))
    return _from_text(raw, title)


# ---------- TXT ----------
_CHAPTER_RE = re.compile(r"^\s*(chapter|part|book)\s+([0-9]+|[ivxlc]+|[a-z-]+)\b.*$", re.I)


def _paragraphs(raw: str) -> list[str]:
    """Re-join hard-wrapped lines. A blank line is a paragraph break."""
    raw = raw.replace("\r\n", "\n")
    paras: list[str] = []
    for block in re.split(r"\n\s*\n", raw):
        cur = ""
        for ln in (x.strip() for x in block.split("\n")):
            if not ln:
                continue
            if cur.endswith("-") and ln[:1].islower():
                cur = cur[:-1] + ln
            else:
                cur = f"{cur} {ln}".strip()
        if cur:
            paras.append(_clean(cur))
    return paras


def _from_text(raw: str, title: str):
    paras = _paragraphs(raw)
    chapters: list[dict] = []
    current = {"title": "Beginning", "paragraphs": []}
    for p in paras:
        if len(p) < 80 and _CHAPTER_RE.match(p):
            if current["paragraphs"]:
                chapters.append(current)
            current = {"title": p, "paragraphs": []}
        else:
            current["paragraphs"].append(p)
    if current["paragraphs"]:
        chapters.append(current)

    # No chapter markers found: split into ~15k-char sections so output files stay manageable.
    if len(chapters) <= 1:
        allp = chapters[0]["paragraphs"] if chapters else paras
        chapters, buf, size = [], [], 0
        for p in allp:
            buf.append(p)
            size += len(p)
            if size > 15000:
                chapters.append({"title": f"Part {len(chapters) + 1}", "paragraphs": buf})
                buf, size = [], 0
        if buf:
            chapters.append({"title": f"Part {len(chapters) + 1}", "paragraphs": buf})
    return title, chapters
