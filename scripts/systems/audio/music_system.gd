## Adaptive stem mixer for the cosmic-EDM soundtrack.
##
## MusicSystem realizes the No Man's Sky stem/intensity model on Godot's built-in
## audio: every [MusicStemDef] gets one [AudioStreamPlayer] looping the same
## 8-bar bed, all started in the same frame so the stems stay phase-locked. An
## [IntensityModel] supplies a single 0..1 game-intensity level; each stem fades
## itself in or out as that level crosses the stem's [member MusicStemDef.threshold]
## and [member MusicStemDef.full_at] window. The pad (always_on) is the only stem
## that ignores intensity and holds its base volume.
##
## The level→dB rule lives in [method volume_db_for] as a pure function so it can
## be tested in isolation and so presentation never re-derives it. Per tick the
## model decays, targets are recomputed, and each player's volume is nudged toward
## its target by at most [constant MAX_DB_PER_TICK] to avoid zipper noise.
##
## Headless-safe: players are created and configured even with no audio device,
## so [method players] introspection and the volume math work in tests.
class_name MusicSystem
extends Node

## Silence floor in decibels. A stem at or below its threshold sits here, which
## Godot treats as effectively muted.
const SILENT_DB := -60.0

## Maximum decibels a player's volume may move in a single tick. Caps the slew
## rate so fades are smooth rather than stepping audibly (zipper noise).
const MAX_DB_PER_TICK := 4.0

var _model: IntensityModel = null
var _clock: SimulationClock = null
var _players: Array[AudioStreamPlayer] = []
## Parallel to [member _players]; the [MusicStemDef] each player renders.
var _defs: Array[MusicStemDef] = []


## Wire up the mixer: build one looping player per stem, start them in sync, and
## subscribe to the clock so the model decays and volumes track intensity.
##
## [param stems] are the stem definitions (order preserved). [param model] is the
## shared intensity source. [param clock] drives per-tick decay and volume slew;
## pass [code]null[/code] in tests to drive [method tick_volumes] by hand.
func setup(stems: Array[MusicStemDef], model: IntensityModel, clock: SimulationClock) -> void:
	_model = model
	_clock = clock
	_build_players(stems)
	_start_in_sync()
	# Seed each player at its level-0 target (no slew on the first frame) so the
	# bed opens at the right mix instead of ramping up from silence.
	for i in _players.size():
		_players[i].volume_db = volume_db_for(_defs[i], _level())
	if _clock != null:
		_clock.ticked.connect(_on_tick)


## The pure level→dB mapping for one stem (see class docs).
##
## always_on stems return [member MusicStemDef.base_db] regardless of level. For
## the rest: at or below [member MusicStemDef.threshold] the stem is [constant
## SILENT_DB]; at or above [member MusicStemDef.full_at] it is its base_db; in
## between it interpolates linearly in decibels. A non-positive window (full_at
## not above threshold) collapses to a step at the threshold.
static func volume_db_for(stem: MusicStemDef, level: float) -> float:
	if stem.always_on:
		return stem.base_db
	if level <= stem.threshold:
		return SILENT_DB
	if level >= stem.full_at:
		return stem.base_db
	var span := stem.full_at - stem.threshold
	if span <= 0.0:
		return stem.base_db
	var t := (level - stem.threshold) / span
	return lerpf(SILENT_DB, stem.base_db, t)


## Advance the model one tick, recompute targets, and slew every player toward
## its target by at most [constant MAX_DB_PER_TICK]. Exposed (and decoupled from
## the clock signal) so tests can step the mixer deterministically.
func tick_volumes() -> void:
	if _model != null:
		_model.tick()
	_update_volumes()


## Recompute and slew volumes toward the current intensity targets without
## advancing the model. Used internally; safe to call directly in tests.
func _update_volumes() -> void:
	var level := _level()
	for i in _players.size():
		var target := volume_db_for(_defs[i], level)
		_players[i].volume_db = _approach(_players[i].volume_db, target, MAX_DB_PER_TICK)


## The players, one per stem, in setup order. Introspection for tests and wiring.
func players() -> Array[AudioStreamPlayer]:
	return _players


## The intensity model this mixer reads, or [code]null[/code] before setup.
func model() -> IntensityModel:
	return _model


func _on_tick(_tick_index: int) -> void:
	tick_volumes()


func _level() -> float:
	return _model.level() if _model != null else 0.0


## Move [param current] toward [param target] by at most [param max_step].
static func _approach(current: float, target: float, max_step: float) -> float:
	var delta := target - current
	if absf(delta) <= max_step:
		return target
	return current + signf(delta) * max_step


func _build_players(stems: Array[MusicStemDef]) -> void:
	_players.clear()
	_defs.clear()
	for stem in stems:
		var player := AudioStreamPlayer.new()
		player.name = "Stem_%s" % stem.id
		var stream := _load_loop(stem.stream_path)
		if stream != null:
			player.stream = stream
		add_child(player)
		_players.append(player)
		_defs.append(stem)


## Load a stem's stream and force seamless looping. Returns [code]null[/code]
## when the file is absent (tests run before stems are generated) so the player
## is still created, just streamless.
func _load_loop(stream_path: String) -> AudioStream:
	if not FileAccess.file_exists(stream_path):
		return null
	var stream := load(stream_path) as AudioStream
	var wav := stream as AudioStreamWAV
	if wav != null and wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		# The .import may not have flagged the loop; force it so the bed cycles
		# without a gap. loop_end == 0 means "to end of data".
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		var frames := wav.data.size() / _bytes_per_frame(wav)
		wav.loop_end = frames
	return stream


## Bytes per sample-frame for a mono [AudioStreamWAV], used to derive the loop
## end frame from the raw byte buffer.
static func _bytes_per_frame(wav: AudioStreamWAV) -> int:
	var bytes := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
	if wav.stereo:
		bytes *= 2
	return maxi(bytes, 1)


## Start every player in the same frame so the stems share a phase origin.
func _start_in_sync() -> void:
	for player in _players:
		player.play()
