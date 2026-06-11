## Tests that the eight procedurally generated pluck note WAVs satisfy the
## Phase 6 note-bank contract.
##
## Validates: each pluck loads via load() as an AudioStreamWAV, is mono 16-bit
## 44100 Hz, ~0.55s long, and is NOT flagged as looping (one-shots).
extends GutTest

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const NOTES_DIR := "res://assets/audio/notes"
const PLUCK_COUNT := 8

const EXPECTED_RATE := 44100
const EXPECTED_DURATION_S := 0.55
const DURATION_TOLERANCE_S := 0.02

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _load_pluck(index: int) -> AudioStreamWAV:
	var path := "%s/pluck_%d.wav" % [NOTES_DIR, index]
	var res := load(path)
	assert_not_null(res, "%s must load" % path)
	assert_true(res is AudioStreamWAV, "%s must be AudioStreamWAV" % path)
	return res


func _frame_count(wav: AudioStreamWAV) -> int:
	var bytes_per_frame := 2  # 16-bit
	if wav.format == AudioStreamWAV.FORMAT_8_BITS:
		bytes_per_frame = 1
	var channels := 2 if wav.stereo else 1
	return wav.data.size() / (bytes_per_frame * channels)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


func test_all_plucks_load_as_audio_stream_wav() -> void:
	for i in range(PLUCK_COUNT):
		var wav := _load_pluck(i)
		assert_not_null(wav, "pluck_%d should load" % i)


func test_all_plucks_are_mono() -> void:
	for i in range(PLUCK_COUNT):
		var wav := _load_pluck(i)
		assert_false(wav.stereo, "pluck_%d must be mono" % i)


func test_all_plucks_are_16_bit() -> void:
	for i in range(PLUCK_COUNT):
		var wav := _load_pluck(i)
		assert_eq(wav.format, AudioStreamWAV.FORMAT_16_BITS, "pluck_%d must be 16-bit PCM" % i)


func test_all_plucks_are_44100_hz() -> void:
	for i in range(PLUCK_COUNT):
		var wav := _load_pluck(i)
		assert_eq(wav.mix_rate, EXPECTED_RATE, "pluck_%d must be 44100 Hz" % i)


func test_all_plucks_have_expected_duration() -> void:
	for i in range(PLUCK_COUNT):
		var wav := _load_pluck(i)
		var frames := _frame_count(wav)
		var duration := float(frames) / float(EXPECTED_RATE)
		assert_almost_eq(
			duration,
			EXPECTED_DURATION_S,
			DURATION_TOLERANCE_S,
			"pluck_%d duration %.4fs must be ~%.4fs" % [i, duration, EXPECTED_DURATION_S]
		)


func test_all_plucks_are_one_shots_not_looped() -> void:
	for i in range(PLUCK_COUNT):
		var wav := _load_pluck(i)
		assert_eq(
			wav.loop_mode,
			AudioStreamWAV.LOOP_DISABLED,
			"pluck_%d must be a one-shot (loop disabled)" % i
		)
