#!/usr/bin/env python3
"""Synthesises Salazie's placeholder music and sound effects.

    python3 tools/audio/generate_audio.py            # writes audio/music, audio/sfx
    python3 tools/audio/generate_audio.py --check    # fails if a file is missing

Everything is generated from the code below with the standard library only, so
the sounds are original to the project and reproducible byte for byte. They are
placeholders: replace any file with a recorded one of the same name and the
game picks it up (see docs/AUDIO.md).

Format: 22050 Hz, mono, 16-bit PCM WAV. Loops are written so that the last
sample flows into the first: note tails wrap around the end of the buffer.
"""

from __future__ import annotations

import argparse
import math
import random
import struct
import sys
import wave
from pathlib import Path

RATE = 22050
ROOT = Path(__file__).resolve().parents[2]
MUSIC_DIR = ROOT / "audio" / "music"
SFX_DIR = ROOT / "audio" / "sfx"

NOTE_INDEX = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def hz(name: str) -> float:
	"""Frequency of a note such as 'A4' or 'F#3'."""
	letter, rest = name[0], name[1:]
	semitone = NOTE_INDEX[letter]
	if rest.startswith("#"):
		semitone += 1
		rest = rest[1:]
	elif rest.startswith("b"):
		semitone -= 1
		rest = rest[1:]
	octave = int(rest)
	return 440.0 * 2.0 ** ((semitone - 9) / 12.0 + (octave - 4))


class Buffer:
	"""Mono float buffer. `loop=True` wraps writes past the end to the start."""

	def __init__(self, seconds: float, loop: bool = False) -> None:
		self.data = [0.0] * int(seconds * RATE)
		self.loop = loop

	def add(self, index: int, value: float) -> None:
		size = len(self.data)
		if self.loop:
			self.data[index % size] += value
		elif 0 <= index < size:
			self.data[index] += value

	def tone(self, freq: float, start: float, length: float, amp: float,
			shape: str = "sine", attack: float = 0.01, release: float = 0.1,
			end_freq: float | None = None, vibrato: float = 0.0) -> None:
		"""One enveloped note. `end_freq` glides the pitch."""
		first = int(start * RATE)
		count = int((length + release) * RATE)
		attack_n = max(1, int(attack * RATE))
		hold_n = int(length * RATE)
		release_n = max(1, int(release * RATE))
		phase = 0.0
		for i in range(count):
			t = i / RATE
			f = freq if end_freq is None else freq + (end_freq - freq) * (i / count)
			if vibrato:
				f *= 1.0 + vibrato * math.sin(2.0 * math.pi * 5.0 * t)
			phase += 2.0 * math.pi * f / RATE
			if shape == "sine":
				sample = math.sin(phase)
			elif shape == "soft":
				# Sine with a touch of its octave and fifth: a mellow keyboard.
				sample = (math.sin(phase) + 0.35 * math.sin(2.0 * phase)
					+ 0.12 * math.sin(3.0 * phase)) / 1.47
			elif shape == "pluck":
				# Bright start that mellows quickly, like a kalimba tine.
				decay = math.exp(-6.0 * t)
				sample = (math.sin(phase) + decay * 0.6 * math.sin(3.0 * phase)
					+ decay * 0.3 * math.sin(5.0 * phase)) / 1.9
			elif shape == "triangle":
				sample = 2.0 / math.pi * math.asin(math.sin(phase))
			else:
				raise ValueError(shape)
			if i < attack_n:
				envelope = i / attack_n
			elif i < hold_n:
				envelope = 1.0 - 0.3 * (i - attack_n) / max(1, hold_n - attack_n)
			else:
				envelope = 0.7 * max(0.0, 1.0 - (i - hold_n) / release_n)
			self.add(first + i, sample * amp * envelope)

	def noise(self, start: float, length: float, amp: float, rng: random.Random,
			smooth: float = 0.5, attack: float = 0.005, swell: float = 0.0) -> None:
		"""Low-passed noise. `smooth` close to 1 is darker; `swell` adds a slow LFO."""
		first = int(start * RATE)
		count = int(length * RATE)
		attack_n = max(1, int(attack * RATE))
		value = 0.0
		for i in range(count):
			value = smooth * value + (1.0 - smooth) * rng.uniform(-1.0, 1.0)
			envelope = min(1.0, i / attack_n) * min(1.0, (count - i) / attack_n)
			if swell:
				envelope *= 0.65 + 0.35 * math.sin(2.0 * math.pi * swell * i / RATE)
			self.add(first + i, value * amp * envelope)

	def echo(self, delay: float, feedback: float) -> None:
		offset = int(delay * RATE)
		size = len(self.data)
		source = list(self.data)
		for i in range(size):
			target = i + offset
			if self.loop:
				self.data[target % size] += source[i] * feedback
			elif target < size:
				self.data[target] += source[i] * feedback

	def crossfade_ends(self, seconds: float) -> None:
		"""Blends the tail into the head so a noise loop has no click."""
		n = int(seconds * RATE)
		size = len(self.data)
		for i in range(n):
			mix = i / n
			head = self.data[i]
			tail = self.data[size - n + i]
			self.data[i] = head * mix + tail * (1.0 - mix)
		del self.data[size - n:]

	def write(self, path: Path, peak: float = 0.8) -> None:
		loudest = max(1e-9, max(abs(value) for value in self.data))
		scale = peak / loudest
		path.parent.mkdir(parents=True, exist_ok=True)
		with wave.open(str(path), "wb") as handle:
			handle.setnchannels(1)
			handle.setsampwidth(2)
			handle.setframerate(RATE)
			handle.writeframes(b"".join(
				struct.pack("<h", int(max(-1.0, min(1.0, value * scale)) * 32767))
				for value in self.data))


# --- Music -------------------------------------------------------------------

def music(name: str, bpm: float, chords: list[list[str]], melody_scale: list[str],
		seed: int, lead: str, density: float, bass_octave_drop: bool = True,
		swing: bool = False) -> Buffer:
	"""A loop of one bar per chord: pad, bass and a melody walked on the scale.

	The melody is a seeded random walk, so the same seed always gives the same
	tune and neighbouring notes stay close to each other.
	"""
	rng = random.Random(seed)
	beat = 60.0 / bpm
	bar = 4.0 * beat
	buffer = Buffer(bar * len(chords), loop=True)
	scale = [hz(note) for note in melody_scale]
	position = len(scale) // 2
	for index, chord in enumerate(chords):
		start = index * bar
		for note in chord:
			buffer.tone(hz(note), start, bar * 0.95, 0.10, "soft", attack=0.35, release=0.6)
		root = hz(chord[0]) / (2.0 if bass_octave_drop else 1.0)
		for step in (0.0, 2.0) if not swing else (0.0, 1.5, 2.5):
			buffer.tone(root, start + step * beat, beat * 1.2, 0.22, "triangle",
				attack=0.02, release=0.25)
		slots = 8
		for slot in range(slots):
			if rng.random() > density:
				continue
			position = max(0, min(len(scale) - 1, position + rng.choice((-2, -1, -1, 1, 1, 2))))
			offset = slot * beat / 2.0
			if swing and slot % 2 == 1:
				offset += beat / 6.0
			buffer.tone(scale[position], start + offset, beat * 0.45, 0.20, lead,
				attack=0.01, release=0.45)
	buffer.echo(beat * 0.75, 0.22)
	return buffer


def build_music() -> dict[str, Buffer]:
	return {
		# Title screen: open and warm.
		"menu": music("menu", 72, [["D3", "F#3", "A3"], ["B2", "D3", "F#3"],
			["G2", "B2", "D3"], ["A2", "C#3", "E3"]],
			["D4", "E4", "F#4", "A4", "B4", "D5", "E5"], seed=11, lead="soft", density=0.45),
		# Map 1: slow, minor, sparse. The escape should feel watchful.
		"maroon": music("maroon", 60, [["A2", "C3", "E3"], ["F2", "A2", "C3"],
			["D3", "F3", "A3"], ["E2", "G#2", "B2"]],
			["A3", "C4", "D4", "E4", "G4", "A4", "C5"], seed=23, lead="pluck", density=0.30),
		# Map 2: brighter and bouncing, a working day.
		"farm": music("farm", 96, [["G2", "B2", "D3"], ["E2", "G2", "B2"],
			["C3", "E3", "G3"], ["D3", "F#3", "A3"], ["G2", "B2", "D3"], ["C3", "E3", "G3"],
			["A2", "C3", "E3"], ["D3", "F#3", "A3"]],
			["G4", "A4", "B4", "D5", "E5", "G5"], seed=37, lead="pluck", density=0.55,
			swing=True),
		# Map 3: modern and calm, with a raised fourth for an unsettled future.
		"heir": music("heir", 84, [["F2", "A2", "C3", "E3"], ["G2", "B2", "D3"],
			["A2", "C3", "E3"], ["C3", "E3", "G3"]],
			["F4", "G4", "A4", "B4", "C5", "E5", "F5"], seed=41, lead="soft", density=0.40),
		# Epilogue: the title key again, slower.
		"ending": music("ending", 60, [["D3", "F#3", "A3"], ["G2", "B2", "D3"],
			["B2", "D3", "F#3"], ["A2", "C#3", "E3"]],
			["D4", "F#4", "A4", "B4", "D5"], seed=53, lead="soft", density=0.28),
	}


# --- Sound effects -------------------------------------------------------------

def build_sfx() -> dict[str, Buffer]:
	rng = random.Random(7)
	sounds: dict[str, Buffer] = {}

	step = Buffer(0.09)
	step.noise(0.0, 0.07, 0.8, rng, smooth=0.86, attack=0.004)
	step.tone(110.0, 0.0, 0.03, 0.4, "sine", attack=0.002, release=0.04, end_freq=70.0)
	sounds["step"] = step

	pickup = Buffer(0.32)
	pickup.tone(hz("E5"), 0.0, 0.06, 0.6, "pluck", release=0.08)
	pickup.tone(hz("A5"), 0.08, 0.08, 0.6, "pluck", release=0.14)
	sounds["pickup"] = pickup

	drink = Buffer(0.5)
	for index, note in enumerate(("G4", "E4", "G4", "D4")):
		drink.tone(hz(note), index * 0.1, 0.05, 0.5, "sine", attack=0.01, release=0.07,
			end_freq=hz(note) * 0.8)
	drink.noise(0.0, 0.42, 0.12, rng, smooth=0.6, attack=0.05)
	sounds["drink"] = drink

	alert = Buffer(0.45)
	alert.tone(hz("A4"), 0.0, 0.09, 0.6, "triangle", release=0.04)
	alert.tone(hz("E5"), 0.13, 0.16, 0.7, "triangle", release=0.12)
	sounds["alert"] = alert

	caught = Buffer(0.8)
	caught.tone(hz("A3"), 0.0, 0.3, 0.7, "triangle", release=0.35, end_freq=hz("D3"))
	caught.noise(0.0, 0.25, 0.3, rng, smooth=0.7)
	sounds["caught"] = caught

	plant = Buffer(0.35)
	plant.noise(0.0, 0.08, 0.5, rng, smooth=0.9)
	plant.tone(hz("C4"), 0.07, 0.07, 0.5, "soft", release=0.14, end_freq=hz("E4"))
	sounds["plant"] = plant

	harvest = Buffer(0.4)
	harvest.tone(hz("G4"), 0.0, 0.05, 0.6, "pluck", release=0.1)
	harvest.tone(hz("B4"), 0.07, 0.05, 0.6, "pluck", release=0.1)
	harvest.tone(hz("D5"), 0.14, 0.08, 0.6, "pluck", release=0.16)
	sounds["harvest"] = harvest

	coin = Buffer(0.4)
	coin.tone(hz("B5"), 0.0, 0.04, 0.6, "sine", release=0.1)
	coin.tone(hz("E6"), 0.06, 0.09, 0.6, "sine", release=0.22)
	sounds["coin"] = coin

	task_done = Buffer(0.9)
	for index, note in enumerate(("D5", "F#5", "A5", "D6")):
		task_done.tone(hz(note), index * 0.1, 0.1, 0.5, "soft", release=0.35)
	sounds["task_done"] = task_done

	ui_move = Buffer(0.07)
	ui_move.tone(hz("A5"), 0.0, 0.015, 0.4, "sine", attack=0.002, release=0.04)
	sounds["ui_move"] = ui_move

	ui_accept = Buffer(0.2)
	ui_accept.tone(hz("D5"), 0.0, 0.03, 0.5, "soft", release=0.04)
	ui_accept.tone(hz("A5"), 0.05, 0.05, 0.5, "soft", release=0.09)
	sounds["ui_accept"] = ui_accept

	ui_cancel = Buffer(0.2)
	ui_cancel.tone(hz("A4"), 0.0, 0.03, 0.5, "soft", release=0.04)
	ui_cancel.tone(hz("D4"), 0.05, 0.05, 0.5, "soft", release=0.09)
	sounds["ui_cancel"] = ui_cancel

	# Ambience loops: built longer, then the tail is folded into the head.
	river = Buffer(4.6)
	river.noise(0.0, 4.6, 0.6, rng, smooth=0.72, swell=0.37)
	river.noise(0.0, 4.6, 0.25, rng, smooth=0.3, swell=0.9)
	river.crossfade_ends(0.6)
	sounds["river"] = river

	wind = Buffer(4.6)
	wind.noise(0.0, 4.6, 0.8, rng, smooth=0.965, swell=0.23)
	wind.noise(0.0, 4.6, 0.3, rng, smooth=0.88, swell=0.61)
	wind.crossfade_ends(0.6)
	sounds["wind"] = wind
	return sounds


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
	parser.add_argument("--check", action="store_true",
		help="only verify that every generated file exists")
	args = parser.parse_args()
	targets = [(MUSIC_DIR, build_music, 0.55), (SFX_DIR, build_sfx, 0.8)]
	if args.check:
		missing = [directory / (name + ".wav")
			for directory, builder, _peak in targets for name in builder()
			if not (directory / (name + ".wav")).is_file()]
		for path in missing:
			print("missing: %s" % path.relative_to(ROOT), file=sys.stderr)
		return 1 if missing else 0
	for directory, builder, peak in targets:
		for name, buffer in builder().items():
			path = directory / (name + ".wav")
			buffer.write(path, peak)
			print("%-28s %6.2f s" % (path.relative_to(ROOT), len(buffer.data) / RATE))
	return 0


if __name__ == "__main__":
	sys.exit(main())
