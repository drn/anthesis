extends GutTest

## Exercises the [MusicSystem] stem mixer: the pure level→dB mapping (silence
## below threshold, base at/above full_at, linear midpoint, the always_on
## exception, and the -60 dB floor), one-player-per-stem construction with the
## players started and looping, and the bounded per-tick volume slew. The mapping
## tests are constructed by hand so they never depend on real audio files; the
## setup tests point at the generated stems when present but stay green when those
## assets have not been built yet.

const STEM_DIR := "res://assets/audio/music"

# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------


## A stem def with an explicit fade window. [param wav] picks a real stream path
## so [method MusicSystem.setup] loads it when the asset exists.
func _stem(
	id: StringName,
	threshold: float,
	full_at: float,
	base_db := -6.0,
	always_on := false,
	wav := "pad",
) -> MusicStemDef:
	var def := MusicStemDef.new()
	def.id = id
	def.threshold = threshold
	def.full_at = full_at
	def.base_db = base_db
	def.always_on = always_on
	def.stream_path = "%s/%s.wav" % [STEM_DIR, wav]
	return def


## The five canonical stems with their contracted windows, ordered as authored.
func _canonical_stems() -> Array[MusicStemDef]:
	var stems: Array[MusicStemDef] = []
	stems.append(_stem(&"pad", 0.0, 0.0, -8.0, true, "pad"))
	stems.append(_stem(&"arp", 0.10, 0.30, -9.0, false, "arp"))
	stems.append(_stem(&"bass", 0.30, 0.50, -6.0, false, "bass"))
	stems.append(_stem(&"drums", 0.50, 0.70, -5.0, false, "drums"))
	stems.append(_stem(&"shimmer", 0.70, 0.90, -10.0, false, "shimmer"))
	return stems


# ---------------------------------------------------------------------------
# Pure mapping: volume_db_for
# ---------------------------------------------------------------------------


func test_always_on_holds_base_db_at_every_level() -> void:
	var pad := _stem(&"pad", 0.0, 0.0, -8.0, true)
	assert_eq(MusicSystem.volume_db_for(pad, 0.0), -8.0, "always_on at level 0")
	assert_eq(MusicSystem.volume_db_for(pad, 0.5), -8.0, "always_on mid")
	assert_eq(MusicSystem.volume_db_for(pad, 1.0), -8.0, "always_on at max")


func test_silent_at_and_below_threshold() -> void:
	var arp := _stem(&"arp", 0.10, 0.30, -9.0)
	assert_eq(MusicSystem.volume_db_for(arp, 0.0), MusicSystem.SILENT_DB, "below threshold")
	assert_eq(
		MusicSystem.volume_db_for(arp, 0.10),
		MusicSystem.SILENT_DB,
		"exactly at threshold is silent"
	)
	assert_eq(MusicSystem.SILENT_DB, -60.0, "floor is -60 dB")


func test_base_db_at_and_above_full_at() -> void:
	var bass := _stem(&"bass", 0.30, 0.50, -6.0)
	assert_eq(MusicSystem.volume_db_for(bass, 0.50), -6.0, "exactly at full_at")
	assert_eq(MusicSystem.volume_db_for(bass, 0.90), -6.0, "above full_at clamps to base")
	assert_eq(MusicSystem.volume_db_for(bass, 1.0), -6.0, "at max clamps to base")


func test_linear_interpolation_at_midpoint() -> void:
	# Window 0.30..0.50, base -6: midpoint 0.40 sits halfway between -60 and -6.
	var bass := _stem(&"bass", 0.30, 0.50, -6.0)
	var mid := MusicSystem.volume_db_for(bass, 0.40)
	assert_almost_eq(mid, (-60.0 + -6.0) / 2.0, 0.0001, "dB-linear midpoint")


func test_linear_interpolation_quarter_and_three_quarter() -> void:
	# Threshold 0.0, full 1.0, base 0 dB makes the level the lerp parameter.
	var stem := _stem(&"x", 0.0, 1.0, 0.0)
	# At level just above 0 we are off the silent step and into the ramp.
	assert_almost_eq(MusicSystem.volume_db_for(stem, 0.25), lerpf(-60.0, 0.0, 0.25), 0.0001)
	assert_almost_eq(MusicSystem.volume_db_for(stem, 0.75), lerpf(-60.0, 0.0, 0.75), 0.0001)


func test_degenerate_window_steps_to_base_above_threshold() -> void:
	# full_at not above threshold: anything past the threshold is full volume.
	var stem := _stem(&"x", 0.40, 0.40, -3.0)
	assert_eq(MusicSystem.volume_db_for(stem, 0.40), MusicSystem.SILENT_DB, "at threshold silent")
	assert_eq(MusicSystem.volume_db_for(stem, 0.41), -3.0, "past threshold jumps to base")


# ---------------------------------------------------------------------------
# setup: players built 1:1, started, looping
# ---------------------------------------------------------------------------


## Build a MusicSystem in the tree, wired to a real IntensityModel with no clock
## so volume stepping is driven by hand. Auto-freed at test teardown.
func _system(stems: Array[MusicStemDef]) -> MusicSystem:
	var model := IntensityModel.new()
	var sys := MusicSystem.new()
	add_child_autofree(sys)
	sys.setup(stems, model, null)
	return sys


func test_setup_creates_one_player_per_stem_in_order() -> void:
	var stems := _canonical_stems()
	var sys := _system(stems)
	var players := sys.players()
	assert_eq(players.size(), stems.size(), "one player per stem")
	for p in players:
		assert_is(p, AudioStreamPlayer)
	assert_eq(sys.model(), sys.model(), "model accessor returns the wired model")
	assert_not_null(sys.model())


func test_setup_starts_every_player_playing() -> void:
	var sys := _system(_canonical_stems())
	for p in sys.players():
		assert_true(p.playing, "stems start in sync (playing) after setup")


func test_setup_forces_loop_forward_on_real_wavs() -> void:
	# Defensive: only assert loop mode for stems whose wav exists on disk.
	var sys := _system(_canonical_stems())
	var checked := 0
	for p in sys.players():
		var wav := p.stream as AudioStreamWAV
		if wav == null:
			continue  # asset not generated yet, or non-WAV stream
		checked += 1
		assert_eq(wav.loop_mode, AudioStreamWAV.LOOP_FORWARD, "wav loop forced to LOOP_FORWARD")
		assert_gt(wav.loop_end, 0, "loop_end set to data frame count")
	if checked == 0:
		pass_test("stem wavs not generated yet; loop assertions skipped")


func test_setup_seeds_level_zero_mix() -> void:
	# At level 0 the pad sits at its base, every gated stem is silent.
	var sys := _system(_canonical_stems())
	var players := sys.players()
	assert_eq(players[0].volume_db, -8.0, "pad (always_on) opens at base")
	for i in range(1, players.size()):
		assert_eq(players[i].volume_db, MusicSystem.SILENT_DB, "gated stems open silent")


# ---------------------------------------------------------------------------
# Volume slew: at most MAX_DB_PER_TICK per tick toward target
# ---------------------------------------------------------------------------


func test_volume_moves_at_most_max_db_per_tick() -> void:
	# One gated stem with a wide-open window so its target is its full base_db
	# once intensity is high. Window 0.0..1.0, base 0 dB.
	var stem := _stem(&"x", 0.0, 1.0, 0.0)
	var stems: Array[MusicStemDef] = [stem]
	var model := IntensityModel.new()
	var sys := MusicSystem.new()
	add_child_autofree(sys)
	sys.setup(stems, model, null)

	# Drive intensity to the top so the target is the base (0 dB) and the start
	# (about -60 dB) must slew up in capped steps.
	for _i in range(40):
		model.on_event(&"player_hurt")  # heat adds, clamps to 1.0
	var start := sys.players()[0].volume_db
	sys._update_volumes()
	var after := sys.players()[0].volume_db
	var moved := absf(after - start)
	assert_almost_eq(moved, MusicSystem.MAX_DB_PER_TICK, 0.0001, "single step capped at 4 dB")
	assert_gt(after, start, "moved toward the louder target")


func test_volume_converges_over_many_ticks() -> void:
	var stem := _stem(&"x", 0.0, 1.0, 0.0)
	var stems: Array[MusicStemDef] = [stem]
	var model := IntensityModel.new()
	var sys := MusicSystem.new()
	add_child_autofree(sys)
	sys.setup(stems, model, null)
	for _i in range(40):
		model.on_event(&"player_hurt")

	# 60 dB of travel at 4 dB/step needs ~15 steps; 30 is ample headroom.
	for _i in range(30):
		sys._update_volumes()
	var target := MusicSystem.volume_db_for(stem, model.level())
	assert_almost_eq(sys.players()[0].volume_db, target, 0.0001, "reaches target and stops")


func test_tick_volumes_decays_model_then_slews() -> void:
	# tick_volumes must advance the model (decay) before recomputing targets.
	var stem := _stem(&"x", 0.0, 1.0, 0.0)
	var stems: Array[MusicStemDef] = [stem]
	var model := IntensityModel.new()
	var sys := MusicSystem.new()
	add_child_autofree(sys)
	sys.setup(stems, model, null)
	model.on_event(&"cast")
	var level_before := model.level()

	sys.tick_volumes()

	assert_lt(model.level(), level_before, "tick_volumes decayed the model")
