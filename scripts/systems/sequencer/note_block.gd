## Note Block — a small placeable crystal in the Phase 6 in-world sequencer.
##
## Players place Note Blocks around a [SequencerCore]. The block's angular
## position around the core decides which of the core's 16 steps it occupies
## (see [SequencerCore.register_block]); when the core's transport crosses that
## step, it calls [method fire] and the block plays its pluck note.
##
## Each block carries a pentatonic [member pitch_index] (0..7) that maps to one
## of the eight generated pluck one-shots in ``assets/audio/notes/``.
## Interacting with the block cycles the pitch (and previews the new note).
## The crystal's emissive colour shifts along a cyan->magenta gradient with the
## pitch so the spatial arrangement reads as a visible melody.
##
## All world mutation (placement, removal, pitch cycling) routes through the
## command layer; this node only owns its own presentation + audio playback.
class_name NoteBlock
extends Node3D

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Number of distinct pitches (A-minor pentatonic across two octaves).
const PITCH_COUNT := 8

const NOTES_DIR := "res://assets/audio/notes"

## Preloaded pluck bank, indexed by pitch_index. Loaded once, shared by every
## Note Block instance (static so the disk hit happens a single time).
static var _bank: Array[AudioStream] = []

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

## Which pentatonic pluck this block plays (0..PITCH_COUNT-1).
@export var pitch_index := 0:
	set(value):
		pitch_index = posmod(value, PITCH_COUNT)
		_apply_pitch_visuals()

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## The step (0..15) this block is assigned to within its core's loop, or -1 if
## the block is dormant (placed out of range of any core).
var assigned_step := -1

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _player: AudioStreamPlayer3D
var _base_energy := 3.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------


func _ready() -> void:
	add_to_group(&"note_blocks")
	_mesh = get_node_or_null("Crystal")
	_player = get_node_or_null("AudioStreamPlayer3D")
	_ensure_bank_loaded()
	_resolve_material()
	_apply_pitch_visuals()


# ---------------------------------------------------------------------------
# Playback / interaction
# ---------------------------------------------------------------------------


## Play this block's pluck note and flash. Called by the SequencerCore when the
## block's step boundary is crossed, and by [method cycle_pitch] as a preview.
func fire() -> void:
	_play_current_note()
	_flash()


## Advance to the next pentatonic pitch (wraps at PITCH_COUNT), recolour the
## crystal, and preview the new note. Routed via CycleNoteCommand.
func cycle_pitch() -> void:
	pitch_index = (pitch_index + 1) % PITCH_COUNT
	fire()


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


## Lazily preload the eight pluck WAVs into the shared static bank.
func _ensure_bank_loaded() -> void:
	if not _bank.is_empty():
		return
	for i in range(PITCH_COUNT):
		var stream: AudioStream = load("%s/pluck_%d.wav" % [NOTES_DIR, i])
		_bank.append(stream)


func _play_current_note() -> void:
	if _player == null:
		return
	_ensure_bank_loaded()
	if pitch_index < 0 or pitch_index >= _bank.size():
		return
	var stream := _bank[pitch_index]
	if stream == null:
		return
	_player.stream = stream
	_player.play()


## Resolve the crystal's StandardMaterial3D (override first, then mesh surface),
## duplicating it so per-instance colour changes don't mutate the shared scene
## resource.
func _resolve_material() -> void:
	if _mesh == null:
		return
	var mat := _mesh.get_active_material(0)
	if mat is StandardMaterial3D:
		_material = (mat as StandardMaterial3D).duplicate()
		_mesh.set_surface_override_material(0, _material)


## Pitch -> colour: a cyan (low) to magenta (high) gradient across 0..7.
func _color_for_pitch(index: int) -> Color:
	var t := float(posmod(index, PITCH_COUNT)) / float(PITCH_COUNT - 1)
	var low := Color(0.1, 0.9, 1.0)  # cyan
	var high := Color(1.0, 0.15, 0.9)  # magenta
	return low.lerp(high, t)


func _apply_pitch_visuals() -> void:
	if _material == null:
		return
	var color := _color_for_pitch(pitch_index)
	_material.albedo_color = color
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = _base_energy


## Brief emission spike + scale pop on fire (presentation only).
func _flash() -> void:
	if not is_inside_tree():
		return
	if _material != null:
		var tween := create_tween()
		tween.tween_property(_material, "emission_energy_multiplier", _base_energy * 3.0, 0.04)
		tween.tween_property(_material, "emission_energy_multiplier", _base_energy, 0.30)
	if _mesh != null:
		var pop := create_tween()
		pop.tween_property(_mesh, "scale", Vector3.ONE * 1.25, 0.04)
		pop.tween_property(_mesh, "scale", Vector3.ONE, 0.22)
