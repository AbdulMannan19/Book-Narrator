"""Thin wrapper around Chatterbox TTS."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np


@dataclass
class VoiceSettings:
    exaggeration: float
    cfg_weight: float
    temperature: float = 0.8


# Narration: calm and steady. Dialogue: more expressive, slightly faster pacing (lower cfg).
NARRATION = VoiceSettings(exaggeration=0.45, cfg_weight=0.5)
DIALOGUE = VoiceSettings(exaggeration=0.75, cfg_weight=0.35)
TITLE = VoiceSettings(exaggeration=0.5, cfg_weight=0.5)


class Narrator:
    def __init__(self, voice_prompt: Path | None = None, device: str = "cuda"):
        import torch
        from chatterbox.tts import ChatterboxTTS

        if device == "cuda" and not torch.cuda.is_available():
            print("CUDA not available, falling back to CPU (very slow).")
            device = "cpu"
        self.model = ChatterboxTTS.from_pretrained(device=device)
        self.sr: int = self.model.sr
        self.voice_prompt = str(voice_prompt) if voice_prompt else None
        self._torch = torch

    def speak(self, text: str, settings: VoiceSettings) -> np.ndarray:
        """Return mono float32 audio at self.sr."""
        with self._torch.inference_mode():
            wav = self.model.generate(
                text,
                audio_prompt_path=self.voice_prompt,
                exaggeration=settings.exaggeration,
                cfg_weight=settings.cfg_weight,
                temperature=settings.temperature,
            )
        return wav.squeeze().detach().cpu().numpy().astype(np.float32)
