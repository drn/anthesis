#!/usr/bin/env python3
"""Procedural pluck-note bank synthesizer for Anthesis (Phase 6 sequencer).

Generates eight short percussive pluck one-shots in ``assets/audio/notes/``,
one per pitch of the A-minor pentatonic scale (ascending across two octaves).
These feed the in-world music sequencer: each Note Block fires the pluck for
its current pitch index when its step is crossed by the Sequencer Core.

The output is deterministic and idempotent: same bytes every run (fixed RNG
seed, no wall-clock input). Mirrors the style of ``generate_stems.py`` — same
DSP primitives (one-pole filters, ``saw``/``sine``, ADSR-ish envelopes) and the
same mono 16-bit/44100 Hz PCM WAV writer.

Notes (A minor pentatonic, ascending):
  pluck_0  A3  220.00 Hz
  pluck_1  C4  261.63 Hz
  pluck_2  D4  293.66 Hz
  pluck_3  E4  329.63 Hz
  pluck_4  G4  392.00 Hz
  pluck_5  A4  440.00 Hz
  pluck_6  C5  523.25 Hz
  pluck_7  E5  659.26 Hz

Each note is ~0.55s, mono 16-bit 44100 Hz, a percussive pluck (saw+sine blend,
fast attack, exponential decay, one-pole lowpass sweep), peaks at -6 dBFS, with
a tiny shimmer tail. One-shots: NOT looped (the .wav.import sidecars set
``edit/loop_mode=0``).

Stdlib only (wave, math, struct, random). Run:
    python3 scripts/tools/generate_notes.py            # write all notes
    python3 scripts/tools/generate_notes.py --verify    # print per-file stats
"""

from __future__ import annotations

import math
import os
import random
import struct
import sys
import wave

# ---------------------------------------------------------------------------
# Musical / format constants
# ---------------------------------------------------------------------------

SAMPLE_RATE = 44100

NOTE_DURATION_S = 0.55
N_FRAMES = round(SAMPLE_RATE * NOTE_DURATION_S)  # ~24255

# Deterministic seed for every stochastic choice in the whole script.
SEED = 20260611

TARGET_PEAK_DBFS = -6.0  # normalize each pluck so its peak sits at -6 dBFS

# A-minor pentatonic, ascending across two octaves (Hz). pluck_<i> -> NOTES[i].
NOTES = [
	("A3", 220.00),
	("C4", 261.63),
	("D4", 293.66),
	("E4", 329.63),
	("G4", 392.00),
	("A4", 440.00),
	("C5", 523.25),
	("E5", 659.26),
]


# ---------------------------------------------------------------------------
# DSP primitives (mirrors generate_stems.py)
# ---------------------------------------------------------------------------


class OnePoleLowpass:
	"""Simple one-pole lowpass filter (state preserved across calls)."""

	def __init__(self, cutoff_hz: float, sample_rate: int = SAMPLE_RATE) -> None:
		dt = 1.0 / sample_rate
		rc = 1.0 / (2.0 * math.pi * cutoff_hz)
		self.alpha = dt / (rc + dt)
		self.y = 0.0

	def set_cutoff(self, cutoff_hz: float, sample_rate: int = SAMPLE_RATE) -> None:
		dt = 1.0 / sample_rate
		rc = 1.0 / (2.0 * math.pi * cutoff_hz)
		self.alpha = dt / (rc + dt)

	def process(self, x: float) -> float:
		self.y += self.alpha * (x - self.y)
		return self.y


def saw(phase: float) -> float:
	"""Naive sawtooth from a 0..1 phase."""
	return 2.0 * (phase - math.floor(phase + 0.5))


def sine(phase: float) -> float:
	return math.sin(2.0 * math.pi * phase)


# ---------------------------------------------------------------------------
# Buffer helpers
# ---------------------------------------------------------------------------


def normalize(buf: list, target_dbfs: float = TARGET_PEAK_DBFS) -> list:
	"""Remove DC offset, then scale so the peak sits at target dBFS."""
	mean = sum(buf) / len(buf)
	buf = [s - mean for s in buf]
	peak = max((abs(s) for s in buf), default=0.0)
	if peak <= 0.0:
		return buf
	target_lin = 10.0 ** (target_dbfs / 20.0)
	scale = target_lin / peak
	return [s * scale for s in buf]


def write_wav(path: str, buf: list) -> None:
	"""Write a mono 16-bit PCM WAV. Values clamped to [-1, 1]."""
	with wave.open(path, "wb") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(SAMPLE_RATE)
		frames = bytearray()
		for s in buf:
			v = max(-1.0, min(1.0, s))
			frames += struct.pack("<h", int(round(v * 32767.0)))
		w.writeframes(bytes(frames))


# ---------------------------------------------------------------------------
# Pluck synthesizer
# ---------------------------------------------------------------------------


def gen_pluck(freq: float, rng: random.Random) -> list:
	"""A percussive pluck at ``freq``: a saw+sine blend through a one-pole
	lowpass whose cutoff sweeps downward over the note, shaped by a fast attack
	and an exponential amplitude decay, with a tiny detuned shimmer tail."""
	buf = [0.0] * N_FRAMES
	lp = OnePoleLowpass(freq * 8.0)
	inc = freq / SAMPLE_RATE
	# Detuned shimmer partial (slightly sharp octave) for a glassy tail.
	shimmer_inc = (freq * 2.004) / SAMPLE_RATE
	# Random start phases (seeded) so each note keeps its own character but is
	# fully reproducible.
	phase = rng.random()
	shimmer_phase = rng.random()
	attack = int(0.004 * SAMPLE_RATE)
	# Decay time constant (seconds): the body rings out over the note length.
	decay_tau = 0.18
	for i in range(N_FRAMES):
		t = i / SAMPLE_RATE
		# Lowpass cutoff sweep: bright at the attack, mellowing toward the tail.
		sweep = freq * (8.0 * math.exp(-t / 0.12) + 1.5)
		lp.set_cutoff(sweep)
		ph = phase + inc * i
		raw = 0.55 * saw(ph) + 0.45 * sine(ph)
		body = lp.process(raw)
		# Amplitude envelope: fast linear attack, exponential decay.
		if i < attack:
			amp = i / max(1, attack)
		else:
			amp = math.exp(-(t - attack / SAMPLE_RATE) / decay_tau)
		# Tiny shimmer tail: a quiet detuned sine that lingers a touch longer.
		shimmer = 0.12 * sine(shimmer_phase + shimmer_inc * i) * math.exp(-t / 0.28)
		buf[i] = body * amp + shimmer * amp
	return buf


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------


def out_dir() -> str:
	here = os.path.dirname(os.path.abspath(__file__))
	root = os.path.abspath(os.path.join(here, "..", ".."))
	return os.path.join(root, "assets", "audio", "notes")


def generate_all() -> dict:
	"""Generate every pluck and write the WAV files. Returns {name: path}."""
	target = out_dir()
	os.makedirs(target, exist_ok=True)
	written = {}
	# Each note draws from its own independent RNG stream derived from SEED so
	# that adding/reordering notes never changes any other note's bytes.
	for idx, (_label, freq) in enumerate(NOTES):
		rng = random.Random(SEED + idx)
		buf = gen_pluck(freq, rng)
		buf = normalize(buf)
		path = os.path.join(target, "pluck_%d.wav" % idx)
		write_wav(path, buf)
		written["pluck_%d" % idx] = path
	return written


def _stats_from_path(path: str) -> tuple:
	"""Return (n_frames, channels, sampwidth_bits, rate, peak_dbfs, dc)."""
	with wave.open(path, "rb") as w:
		n = w.getnframes()
		ch = w.getnchannels()
		sw = w.getsampwidth()
		rate = w.getframerate()
		raw = w.readframes(n)
	count = len(raw) // 2
	vals = struct.unpack("<%dh" % count, raw)
	peak = max((abs(v) for v in vals), default=0)
	mean = (sum(vals) / count) if count else 0.0
	peak_dbfs = (20.0 * math.log10(peak / 32768.0)) if peak > 0 else -math.inf
	return (n, ch, sw * 8, rate, peak_dbfs, mean / 32768.0)


def verify() -> int:
	"""Print per-file stats and validate the contract. Returns process code."""
	target = out_dir()
	ok = True
	print("Anthesis note-bank verification")
	print("  expected frames: %d  (~%.4fs @ %d Hz)" % (
		N_FRAMES, N_FRAMES / SAMPLE_RATE, SAMPLE_RATE
	))
	print("  %-9s %5s %8s %3s %5s %7s %9s %9s" % (
		"note", "pitch", "frames", "ch", "bits", "rate", "peak_dB", "dc"
	))
	for idx, (label, _freq) in enumerate(NOTES):
		name = "pluck_%d" % idx
		path = os.path.join(target, name + ".wav")
		if not os.path.exists(path):
			print("  %-9s MISSING (%s)" % (name, path))
			ok = False
			continue
		n, ch, bits, rate, peak_db, dc = _stats_from_path(path)
		dur = n / SAMPLE_RATE
		line_ok = (
			ch == 1 and bits == 16 and rate == SAMPLE_RATE
			and n == N_FRAMES and peak_db <= TARGET_PEAK_DBFS + 0.01
			and abs(dur - NOTE_DURATION_S) <= 0.01
		)
		ok = ok and line_ok
		flag = "" if line_ok else "  <-- FAIL"
		print("  %-9s %5s %8d %3d %5d %7d %9.2f %9.5f%s" % (
			name, label, n, ch, bits, rate, peak_db, dc, flag
		))
	print("  RESULT: %s" % ("OK" if ok else "FAIL"))
	return 0 if ok else 1


def main(argv: list) -> int:
	if "--verify" in argv:
		return verify()
	written = generate_all()
	for name, path in written.items():
		print("wrote %s" % path)
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))
