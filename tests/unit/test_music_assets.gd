## Tests that the five procedurally generated music stem WAVs satisfy the
## Phase 5 audio-asset contract.
##
## Validates: each stem loads via load() as an AudioStreamWAV, is mono 16-bit
## 44100 Hz, all five share the same frame length, and the loop duration is
## ~17.45s (8 bars @ 110 BPM in A minor).
extends GutTest

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const MUSIC_DIR := "res://assets/audio/music"

const STEM_IDS: Array = [
	&"pad",
	&"bass",
	&"arp",
	&"drums",
	&"shimmer",
]

const EXPECTED_RATE := 44100
const EXPECTED_DURATION_S := 17.4545  # 32 beats * 60/110 s
const DURATION_TOLERANCE_S := 0.1

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## Load a stem WAV by id and assert it is a valid AudioStreamWAV.
func _load_stem(id: StringName) -> AudioStreamWAV:
	var path := "%s/%s.wav" % [MUSIC_DIR, id]
	var res := load(path)
	assert_not_null(res, "%s must load" % path)
	assert_true(res is AudioStreamWAV, "%s must be AudioStreamWAV" % path)
	return res


## Compute the frame count of an AudioStreamWAV from its PCM byte buffer.
func _frame_count(wav: AudioStreamWAV) -> int:
	var bytes_per_frame := 2  # 16-bit
	if wav.format == AudioStreamWAV.FORMAT_8_BITS:
		bytes_per_frame = 1
	var channels := 2 if wav.stereo else 1
	return wav.data.size() / (bytes_per_frame * channels)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


func test_all_stems_load_as_audio_stream_wav() -> void:
	for id in STEM_IDS:
		var wav := _load_stem(id)
		assert_not_null(wav, "stem %s should load" % id)


func test_all_stems_are_mono() -> void:
	for id in STEM_IDS:
		var wav := _load_stem(id)
		assert_false(wav.stereo, "stem %s must be mono" % id)


func test_all_stems_are_16_bit() -> void:
	for id in STEM_IDS:
		var wav := _load_stem(id)
		assert_eq(wav.format, AudioStreamWAV.FORMAT_16_BITS, "stem %s must be 16-bit PCM" % id)


func test_all_stems_are_44100_hz() -> void:
	for id in STEM_IDS:
		var wav := _load_stem(id)
		assert_eq(wav.mix_rate, EXPECTED_RATE, "stem %s must be 44100 Hz" % id)


func test_all_stems_share_same_length() -> void:
	var counts: Array = []
	for id in STEM_IDS:
		var wav := _load_stem(id)
		counts.append(_frame_count(wav))
	for i in range(1, counts.size()):
		assert_eq(
			counts[i],
			counts[0],
			(
				"stem %s frame count (%d) must match %s (%d)"
				% [STEM_IDS[i], counts[i], STEM_IDS[0], counts[0]]
			)
		)


func test_all_stems_have_expected_duration() -> void:
	for id in STEM_IDS:
		var wav := _load_stem(id)
		var frames := _frame_count(wav)
		var duration := float(frames) / float(EXPECTED_RATE)
		assert_almost_eq(
			duration,
			EXPECTED_DURATION_S,
			DURATION_TOLERANCE_S,
			"stem %s duration %.4fs must be ~%.4fs" % [id, duration, EXPECTED_DURATION_S]
		)
