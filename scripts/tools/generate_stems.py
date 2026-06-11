#!/usr/bin/env python3
"""Procedural adaptive-music stem synthesizer for Anthesis (Phase 5).

Generates five seamless, loopable mono 16-bit/44100 Hz WAV stems in
``assets/audio/music/``. Each loop is EXACTLY 8 bars of 4/4 at 110 BPM in
A minor (32 beats). The output is deterministic and idempotent: same bytes
every run (fixed RNG seed, no wall-clock, no time-of-day input).

Stems (No Man's Sky-style intensity layering):
  pad.wav      warm slow-attack chord drone (Am-F-C-G, detuned saw/sine)
  bass.wav     sub sine pulse on roots with per-beat sidechain duck
  arp.wav      plucky 16th-note arpeggio with a 3/16 delay echo
  drums.wav    four-on-floor kick, offbeat hats, clap/snare on 2 & 4
  shimmer.wav  high pentatonic plinks with long shimmer tails + noise swell

Stdlib only (wave, math, struct, random). Run:
    python3 scripts/tools/generate_stems.py            # write all stems
    python3 scripts/tools/generate_stems.py --verify    # print per-file stats
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
BPM = 110.0
BEATS = 32  # 8 bars * 4 beats
BEATS_PER_BAR = 4
BARS = BEATS // BEATS_PER_BAR

# Exact seamless loop length: 32 beats * (60 / BPM) seconds * SAMPLE_RATE.
# = round(44100 * 32 * 60 / 110). Computed as an integer for reproducibility.
N_FRAMES = round(SAMPLE_RATE * BEATS * 60.0 / BPM)  # 769745

SAMPLES_PER_BEAT = N_FRAMES / BEATS  # fractional, used for phase math
SAMPLES_PER_BAR = N_FRAMES / BARS

# Deterministic seed for every stochastic choice in the whole script.
SEED = 20260610

TARGET_PEAK_DBFS = -3.0  # normalize each stem so its peak sits at -3 dBFS

# ---------------------------------------------------------------------------
# Pitch helpers (A minor). A4 = 440 Hz reference.
# ---------------------------------------------------------------------------

A4 = 440.0


def note(semitones_from_a4: float) -> float:
	"""Frequency for a note given semitone offset from A4."""
	return A4 * (2.0 ** (semitones_from_a4 / 12.0))


# MIDI-ish offsets (relative to A4) for the chord roots and chord tones we use.
# A2 = -24, A1 = -36, etc. Chord progression: Am - F - C - G (2 bars each).
# Each chord stored as (root_offset, [triad offsets relative to A4]).
# Am  = A  C  E
# F   = F  A  C
# C   = C  E  G
# G   = G  B  D
CHORDS = [
	{"root": -12, "tones": [0, 3, 7]},  # Am: A3 C4 E4
	{"root": -16, "tones": [-4, 0, 3]},  # F:  F3 A3 C4
	{"root": -21, "tones": [-9, -5, -2]},  # C:  C3 E3 G3
	{"root": -14, "tones": [-2, 2, 5]},  # G:  G3 B3 D4
]

# A minor pentatonic offsets from A4 for the shimmer plinks (2 octaves up).
PENTATONIC = [0, 3, 5, 7, 10]  # A C D E G


# ---------------------------------------------------------------------------
# DSP primitives
# ---------------------------------------------------------------------------


class OnePoleLowpass:
	"""Simple one-pole lowpass filter (state preserved across calls)."""

	def __init__(self, cutoff_hz: float, sample_rate: int = SAMPLE_RATE) -> None:
		# Standard one-pole coefficient.
		dt = 1.0 / sample_rate
		rc = 1.0 / (2.0 * math.pi * cutoff_hz)
		self.alpha = dt / (rc + dt)
		self.y = 0.0

	def process(self, x: float) -> float:
		self.y += self.alpha * (x - self.y)
		return self.y


class OnePoleHighpass:
	"""One-pole highpass (used to remove DC / rumble from noise bursts)."""

	def __init__(self, cutoff_hz: float, sample_rate: int = SAMPLE_RATE) -> None:
		dt = 1.0 / sample_rate
		rc = 1.0 / (2.0 * math.pi * cutoff_hz)
		self.alpha = rc / (rc + dt)
		self.prev_x = 0.0
		self.prev_y = 0.0

	def process(self, x: float) -> float:
		y = self.alpha * (self.prev_y + x - self.prev_x)
		self.prev_x = x
		self.prev_y = y
		return y


def saw(phase: float) -> float:
	"""Naive sawtooth from a 0..1 phase."""
	return 2.0 * (phase - math.floor(phase + 0.5))


def sine(phase: float) -> float:
	return math.sin(2.0 * math.pi * phase)


def beat_to_sample(beat: float) -> int:
	return int(round(beat * SAMPLES_PER_BEAT))


def chord_at_beat(beat: float) -> dict:
	"""Return the chord active at a given beat (2 bars / 8 beats each)."""
	bar = int(beat // BEATS_PER_BAR)
	idx = (bar // 2) % len(CHORDS)
	return CHORDS[idx]


def adsr(
	pos: int, length: int, attack: int, decay: int, sustain: float, release: int
) -> float:
	"""Sample-accurate ADSR envelope value at position ``pos`` in a note of
	total ``length`` samples."""
	if pos < 0 or pos >= length:
		return 0.0
	if pos < attack:
		return pos / max(1, attack)
	if pos < attack + decay:
		t = (pos - attack) / max(1, decay)
		return 1.0 + t * (sustain - 1.0)
	rel_start = length - release
	if pos >= rel_start:
		t = (pos - rel_start) / max(1, release)
		return sustain * (1.0 - t)
	return sustain


# ---------------------------------------------------------------------------
# Buffer helpers
# ---------------------------------------------------------------------------


def new_buffer() -> list:
	return [0.0] * N_FRAMES


def add_wrapped(buf: list, start: int, samples: list, gain: float = 1.0) -> None:
	"""Add a sample list into the buffer starting at ``start``, wrapping around
	the loop boundary so tails that spill past the end fold back to the start
	(keeps loops seamless)."""
	n = len(buf)
	for i, s in enumerate(samples):
		buf[(start + i) % n] += s * gain


def normalize(buf: list, target_dbfs: float = TARGET_PEAK_DBFS) -> list:
	"""Remove DC offset, then scale so the peak sits at target dBFS."""
	# DC removal.
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
# Stem generators
# ---------------------------------------------------------------------------


def gen_pad(rng: random.Random) -> list:
	"""Warm slow-attack chord drone: detuned saw + sine blend per chord tone,
	lowpassed, with a gentle bar-length swell. One sustained chord per 2 bars."""
	buf = new_buffer()
	lp = OnePoleLowpass(900.0)
	# Small fixed detune set (cents) per voice for width; deterministic.
	detunes = [-7.0, -3.0, 3.0, 7.0]
	for chord_idx in range(BARS // 2):
		start_beat = chord_idx * 8
		chord = CHORDS[chord_idx % len(CHORDS)]
		seg_start = beat_to_sample(start_beat)
		seg_len = int(round(8 * SAMPLES_PER_BEAT))
		# Build the raw (pre-filter) chord segment.
		seg = [0.0] * seg_len
		for tone in chord["tones"]:
			base_f = note(tone)
			for d in detunes:
				f = base_f * (2.0 ** (d / 1200.0))
				phase = rng.random()  # random start phase per voice (seeded)
				inc = f / SAMPLE_RATE
				# blend: 60% saw, 40% sine for warmth
				for i in range(seg_len):
					ph = phase + inc * i
					seg[i] += 0.6 * saw(ph) + 0.4 * sine(ph)
		# Normalize voice count and apply slow attack + gentle swell envelope.
		n_voices = len(chord["tones"]) * len(detunes)
		attack = int(0.9 * SAMPLE_RATE)
		release = int(0.6 * SAMPLE_RATE)
		for i in range(seg_len):
			env = adsr(i, seg_len, attack, int(0.2 * SAMPLE_RATE), 0.85, release)
			# subtle swell over the segment (cosine bump, peaks mid-segment)
			swell = 0.85 + 0.15 * (0.5 - 0.5 * math.cos(2 * math.pi * i / seg_len))
			seg[i] = lp.process(seg[i] / n_voices) * env * swell
		add_wrapped(buf, seg_start, seg, gain=1.0)
	return buf


def gen_bass(rng: random.Random) -> list:
	"""Sub sine pulse on chord roots, alternating A1/A2-style octaves, with a
	per-beat sidechain-style volume duck (ducks hard right on each beat)."""
	buf = new_buffer()
	lp = OnePoleLowpass(220.0)
	# One bass note per beat on the current chord root; alternate octaves.
	for beat in range(BEATS):
		chord = chord_at_beat(beat)
		root = chord["root"]
		# Alternate down an octave on even beats for an A1/A2 feel.
		octave = -12 if (beat % 2 == 0) else 0
		f = note(root + octave)
		start = beat_to_sample(beat)
		note_len = int(round(SAMPLES_PER_BEAT))
		phase = 0.0
		inc = f / SAMPLE_RATE
		seg = [0.0] * note_len
		attack = int(0.004 * SAMPLE_RATE)
		release = int(0.08 * SAMPLE_RATE)
		for i in range(note_len):
			ph = phase + inc * i
			# soft second harmonic for body
			val = sine(ph) + 0.18 * sine(2 * ph)
			env = adsr(i, note_len, attack, int(0.05 * SAMPLE_RATE), 0.9, release)
			seg[i] = lp.process(val) * env
		add_wrapped(buf, start, seg, gain=1.0)
	# Sidechain duck: volume dips at each beat then recovers (classic pump).
	for beat in range(BEATS):
		start = beat_to_sample(beat)
		duck_len = int(round(SAMPLES_PER_BEAT * 0.85))
		for i in range(duck_len):
			idx = (start + i) % N_FRAMES
			t = i / duck_len
			# starts at 0.35 (ducked), recovers to 1.0
			gain = 0.35 + 0.65 * t
			buf[idx] *= gain
	return buf


def gen_arp(rng: random.Random) -> list:
	"""Plucky 16th-note arpeggio over the chord tones (triad + octave pattern),
	short decay, plus a 3/16 delayed echo copy at 0.35 gain."""
	dry = new_buffer()
	sixteenth = SAMPLES_PER_BEAT / 4.0
	total_sixteenths = BEATS * 4
	for s16 in range(total_sixteenths):
		beat = s16 / 4.0
		chord = chord_at_beat(beat)
		tones = chord["tones"]
		# Pattern: root, third, fifth, octave, fifth, third (cycled).
		pattern = [tones[0], tones[1], tones[2], tones[0] + 12, tones[2], tones[1]]
		tone = pattern[s16 % len(pattern)]
		f = note(tone + 12)  # one octave up for pluck brightness
		start = int(round(s16 * sixteenth))
		note_len = int(round(sixteenth * 1.4))  # slight overlap
		phase = 0.0
		inc = f / SAMPLE_RATE
		seg = [0.0] * note_len
		attack = int(0.002 * SAMPLE_RATE)
		for i in range(note_len):
			ph = phase + inc * i
			# bright pluck: saw + sine, fast exponential-ish decay
			val = 0.5 * saw(ph) + 0.5 * sine(ph)
			env = adsr(i, note_len, attack, int(0.04 * SAMPLE_RATE), 0.0, 1)
			seg[i] = val * env
		add_wrapped(dry, start, seg, gain=0.8)
	# 3/16 delayed echo at 0.35 gain (wrapped to keep loop seamless).
	delay_samples = int(round(sixteenth * 3.0))
	out = list(dry)
	for i in range(N_FRAMES):
		out[(i + delay_samples) % N_FRAMES] += dry[i] * 0.35
	return out


def gen_drums(rng: random.Random) -> list:
	"""Four-on-floor kick (pitch-drop sine + click), offbeat filtered-noise
	hats, and a clap/snare body on beats 2 & 4 (EDM groove)."""
	buf = new_buffer()
	# --- Kick on every beat ---
	for beat in range(BEATS):
		start = beat_to_sample(beat)
		klen = int(0.22 * SAMPLE_RATE)
		seg = [0.0] * klen
		for i in range(klen):
			t = i / SAMPLE_RATE
			# pitch drop 90 -> 40 Hz over ~80 ms
			fdrop = 40.0 + (90.0 - 40.0) * math.exp(-t / 0.04)
			# accumulate phase from instantaneous freq
			# (approx via integral: use running phase)
			seg[i] = math.sin(2 * math.pi * fdrop * t)
		# amplitude env + click transient
		for i in range(klen):
			t = i / SAMPLE_RATE
			env = math.exp(-t / 0.10)
			click = math.exp(-t / 0.002) * 0.6
			seg[i] = seg[i] * env + click
		add_wrapped(buf, start, seg, gain=0.95)
	# --- Offbeat hats on the "and" of each beat (eighth offset) ---
	hat_hp = OnePoleHighpass(6000.0)
	for beat in range(BEATS):
		start = beat_to_sample(beat + 0.5)
		hlen = int(0.05 * SAMPLE_RATE)
		seg = [0.0] * hlen
		for i in range(hlen):
			t = i / SAMPLE_RATE
			n = rng.uniform(-1.0, 1.0)
			env = math.exp(-t / 0.012)
			seg[i] = hat_hp.process(n) * env
		add_wrapped(buf, start, seg, gain=0.32)
	# --- Clap/snare on beats 2 and 4 of every bar ---
	clap_hp = OnePoleHighpass(1200.0)
	clap_lp = OnePoleLowpass(7000.0)
	for bar in range(BARS):
		for beat_in_bar in (1, 3):  # beats 2 and 4 (0-indexed 1,3)
			beat = bar * BEATS_PER_BAR + beat_in_bar
			start = beat_to_sample(beat)
			clen = int(0.18 * SAMPLE_RATE)
			seg = [0.0] * clen
			# 3 quick noise bursts (clap texture) + tonal body
			burst_offsets = [0, int(0.008 * SAMPLE_RATE), int(0.016 * SAMPLE_RATE)]
			for i in range(clen):
				t = i / SAMPLE_RATE
				n = rng.uniform(-1.0, 1.0)
				body = math.sin(2 * math.pi * 190.0 * t) * math.exp(-t / 0.06)
				amp = 0.0
				for bo in burst_offsets:
					if i >= bo:
						amp += math.exp(-(i - bo) / (0.02 * SAMPLE_RATE))
				noise = clap_lp.process(clap_hp.process(n)) * amp * 0.5
				seg[i] = noise + body * 0.4
			add_wrapped(buf, start, seg, gain=0.6)
	return buf


def gen_shimmer(rng: random.Random) -> list:
	"""High sparkly texture: deterministic-random pentatonic plinks two octaves
	up with long shimmer tails, plus a soft filtered-noise swell building into
	bar 5 (the midpoint, for an 8-bar loop arc)."""
	buf = new_buffer()
	# Plinks: roughly one per beat, but with seeded random timing jitter and
	# pitch selection from the A-minor pentatonic, two octaves up.
	for beat in range(BEATS):
		# 70% chance of a plink on each beat (seeded), plus occasional doubles.
		hits = []
		if rng.random() < 0.7:
			hits.append(beat + rng.uniform(-0.05, 0.05))
		if rng.random() < 0.25:
			hits.append(beat + 0.5 + rng.uniform(-0.05, 0.05))
		for hb in hits:
			pent = PENTATONIC[rng.randrange(len(PENTATONIC))]
			f = note(pent + 24)  # two octaves up
			start = beat_to_sample(hb)
			plen = int(rng.uniform(0.6, 1.1) * SAMPLE_RATE)  # long tail
			seg = [0.0] * plen
			inc = f / SAMPLE_RATE
			inc2 = (f * 2.003) / SAMPLE_RATE  # detuned shimmer partial
			attack = int(0.004 * SAMPLE_RATE)
			for i in range(plen):
				val = sine(inc * i) + 0.4 * sine(inc2 * i)
				env = adsr(i, plen, attack, int(0.05 * SAMPLE_RATE), 0.5, plen - attack)
				# slow tremolo shimmer
				trem = 0.85 + 0.15 * math.sin(2 * math.pi * 5.5 * i / SAMPLE_RATE)
				seg[i] = val * env * trem
			add_wrapped(buf, start, seg, gain=0.3)
	# Soft noise swell building into bar 5 (sample index at 4 bars in).
	swell_peak = int(4 * SAMPLES_PER_BAR)
	swell_start = int(2 * SAMPLES_PER_BAR)
	swell_lp = OnePoleLowpass(2500.0)
	swell_hp = OnePoleHighpass(800.0)
	for i in range(swell_start, swell_peak):
		t = (i - swell_start) / (swell_peak - swell_start)
		amp = (t * t) * 0.25  # quadratic rise to the downbeat of bar 5
		n = rng.uniform(-1.0, 1.0)
		buf[i] += swell_lp.process(swell_hp.process(n)) * amp
	return buf


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

STEMS = {
	"pad": gen_pad,
	"bass": gen_bass,
	"arp": gen_arp,
	"drums": gen_drums,
	"shimmer": gen_shimmer,
}


def out_dir() -> str:
	here = os.path.dirname(os.path.abspath(__file__))
	root = os.path.abspath(os.path.join(here, "..", ".."))
	return os.path.join(root, "assets", "audio", "music")


def generate_all() -> dict:
	"""Generate every stem and write the WAV files. Returns {name: path}."""
	target = out_dir()
	os.makedirs(target, exist_ok=True)
	written = {}
	# Each stem draws from its own independent RNG stream derived from SEED so
	# that adding/reordering stems never changes any other stem's bytes.
	for offset, (name, fn) in enumerate(STEMS.items()):
		rng = random.Random(SEED + offset)
		buf = fn(rng)
		buf = normalize(buf)
		path = os.path.join(target, name + ".wav")
		write_wav(path, buf)
		written[name] = path
	return written


def _peak_dbfs_from_path(path: str) -> tuple:
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
	expected_frames = N_FRAMES
	ok = True
	frame_counts = []
	print("Anthesis stem verification")
	print("  expected frames: %d  (~%.4fs @ %d Hz)" % (
		expected_frames, expected_frames / SAMPLE_RATE, SAMPLE_RATE
	))
	print("  %-9s %8s %3s %5s %7s %9s %9s" % (
		"stem", "frames", "ch", "bits", "rate", "peak_dB", "dc"
	))
	for name in STEMS:
		path = os.path.join(target, name + ".wav")
		if not os.path.exists(path):
			print("  %-9s MISSING (%s)" % (name, path))
			ok = False
			continue
		n, ch, bits, rate, peak_db, dc = _peak_dbfs_from_path(path)
		frame_counts.append(n)
		line_ok = (
			ch == 1 and bits == 16 and rate == SAMPLE_RATE
			and n == expected_frames and peak_db <= TARGET_PEAK_DBFS + 0.01
		)
		ok = ok and line_ok
		flag = "" if line_ok else "  <-- FAIL"
		print("  %-9s %8d %3d %5d %7d %9.2f %9.5f%s" % (
			name, n, ch, bits, rate, peak_db, dc, flag
		))
	if len(set(frame_counts)) > 1:
		print("  ERROR: frame counts differ across stems: %s" % frame_counts)
		ok = False
	elif frame_counts:
		print("  all frame counts identical: %d" % frame_counts[0])
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
