"""Split paragraphs into sentences and label each as narration or dialogue.

Dialogue gets different Chatterbox settings (more expressive) than narration.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

import pysbd

_seg = pysbd.Segmenter(language="en", clean=False)

# Straight and curly double quotes.
_QUOTES = '"“”'
MAX_CHARS = 280  # Chatterbox degrades on very long inputs
MIN_CHARS = 25  # ...and on very short ones, so merge them into a neighbour


@dataclass
class Segment:
    text: str
    kind: str  # "narration" | "dialogue"
    para_end: bool  # True if this is the last segment of its paragraph


def _kind(text: str) -> str:
    stripped = text.strip()
    if stripped and stripped[0] in _QUOTES:
        return "dialogue"
    # Dialogue continuing across a sentence: opening quote with no closing one.
    if sum(stripped.count(q) for q in _QUOTES) % 2 == 1:
        return "dialogue"
    return "narration"


def _split_long(sentence: str) -> list[str]:
    if len(sentence) <= MAX_CHARS:
        return [sentence]
    parts = re.split(r"(?<=[,;:—])\s+", sentence)
    out, cur = [], ""
    for p in parts:
        if cur and len(cur) + len(p) + 1 > MAX_CHARS:
            out.append(cur)
            cur = p
        else:
            cur = f"{cur} {p}".strip()
    if cur:
        out.append(cur)
    return out


def segment_paragraphs(paragraphs: list[str]) -> list[Segment]:
    segs: list[Segment] = []
    for para in paragraphs:
        sentences = [s.strip() for s in _seg.segment(para) if s.strip()]
        pieces: list[str] = []
        for s in sentences:
            pieces.extend(_split_long(s))
        # Merge tiny pieces into the next one (e.g. '"No." ' , 'He sighed.').
        merged: list[str] = []
        carry = ""
        for p in pieces:
            p = f"{carry} {p}".strip() if carry else p
            carry = ""
            if len(p) < MIN_CHARS:
                carry = p
            else:
                merged.append(p)
        if carry:
            if merged:
                merged[-1] = f"{merged[-1]} {carry}"
            else:
                merged.append(carry)
        for i, text in enumerate(merged):
            segs.append(Segment(text=text, kind=_kind(text), para_end=(i == len(merged) - 1)))
    return segs
