# Note-Bank Assets — License

The WAV files in this directory (`pluck_0.wav` … `pluck_7.wav`) are
**procedurally generated** by `scripts/tools/generate_notes.py` using only the
Python standard library.

They are released into the **public domain** under
[CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/).
All copyright and related rights are waived (© waived).

These assets are fully reproducible: running
`python3 scripts/tools/generate_notes.py` (or `make notes`) regenerates them
byte-for-byte from a fixed seed. The repository therefore carries zero
third-party licensing baggage for its in-world sequencer note bank.

The eight plucks are the A-minor pentatonic scale ascending across two octaves
(A3, C4, D4, E4, G4, A4, C5, E5) — short percussive one-shots (~0.55s, mono
16-bit/44100 Hz), fired by Note Blocks in the Phase 6 music sequencer.
