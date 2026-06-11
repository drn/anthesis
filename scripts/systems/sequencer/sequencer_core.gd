## The beating heart of the in-world music sequencer (Phase 6 contract #4).
##
## A SequencerCore is a slowly rotating glowing prism the player crafts and
## places in the world. It locks to the live adaptive-music transport (the synced
## stem players' playback position, supplied as a [Callable] by [World]) and owns
## a [StepTimeline] at 110 BPM / 16 steps. Each frame it asks the timeline which
## step boundaries the transport crossed and fires every Note Block registered to
## those steps, so player compositions ride the same grid as the soundtrack.
##
## A ring of 16 tiny marker spheres (built in code) visualises the loop; the
## marker for the current step brightens as the playhead sweeps past. Note Blocks
## are assigned a step by their ANGLE around the core (see [SectorMath]) — the
## registry is keyed by step so firing a step is an O(1) lookup. Freed blocks are
## tolerated everywhere via [method @GlobalScope.is_instance_valid] guards.
class_name SequencerCore
extends Node3D

## Emitted after the playhead advances onto [param step] (one per crossed step,
## in order). Presentation/tests can observe the live playhead.
signal step_advanced(step: int)

## Group every core joins so the player's raycast / placement service can find
## cores generically.
const GROUP := &"sequencer_cores"

## Radius (metres) within which a Note Block may join this core. The placement
## service enforces this; the core only stores what it is handed.
const RADIUS := 10.0

## Radius of the visual step-marker ring, in metres.
const RING_RADIUS := 1.2
## Y position of the marker ring relative to the core origin.
const RING_HEIGHT := 0.0
## Radians per second the prism spins about its Y axis.
const SPIN_SPEED := 0.6
## Emission energy of an idle (unlit) step marker.
const MARKER_DIM := 0.4
## Emission energy a marker spikes to when its step is the active playhead.
const MARKER_BRIGHT := 6.0
## How quickly a brightened marker decays back toward [constant MARKER_DIM]
## (energy units per second).
const MARKER_DECAY := 14.0

var _timeline: StepTimeline = StepTimeline.new(110.0, 16, 4)
var _playback_pos: Callable = Callable()
## step index -> Array of registered Note Block nodes.
var _registry: Dictionary = {}
## Marker MeshInstance3D nodes, indexed by step.
var _markers: Array[MeshInstance3D] = []
## Live emission energy of each marker (decays toward MARKER_DIM each frame).
var _marker_energy: Array[float] = []
## Last sampled transport position, in seconds; -1 means "not yet sampled".
var _last_pos := -1.0


func _ready() -> void:
	add_to_group(GROUP)
	_build_ring()


## Lock this core to the transport. [param playback_pos] is a Callable returning
## the current playback position in seconds (in [World], the music pad player's
## get_playback_position()). Resets the sampling origin so the first frame does
## not fire a spurious burst of steps.
func setup(playback_pos: Callable) -> void:
	_playback_pos = playback_pos
	_last_pos = -1.0


func _process(delta: float) -> void:
	rotate_y(SPIN_SPEED * delta)
	_decay_markers(delta)
	if not _playback_pos.is_valid():
		return
	var now := float(_playback_pos.call())
	if _last_pos < 0.0:
		# First sample: seed the origin, light the current step, fire nothing.
		_last_pos = now
		_highlight(_timeline.step_at(now))
		return
	for step in _timeline.steps_crossed(_last_pos, now):
		_advance_to(step)
	_last_pos = now


## The timeline this core drives (110/16/4). Exposed for tests/introspection.
func timeline() -> StepTimeline:
	return _timeline


## Register a Note Block with this core: compute its step from its angle around
## the core (via [SectorMath]) and file it under that step. If the block exposes
## an [code]assigned_step[/code] property it is set so the block can colour /
## tag itself. Re-registering a block first drops any stale entry.
func register_block(block: Node) -> void:
	if not is_instance_valid(block):
		return
	unregister_block(block)
	var offset := Vector3.ZERO
	if block is Node3D:
		offset = (block as Node3D).global_position - global_position
	var step := SectorMath.step_for_offset(offset, _timeline.steps)
	if not _registry.has(step):
		_registry[step] = []
	(_registry[step] as Array).append(block)
	if "assigned_step" in block:
		block.set("assigned_step", step)


## Remove [param block] from every step bucket it appears in. Safe to call with
## an already-freed or never-registered block. Empty buckets are pruned.
func unregister_block(block: Node) -> void:
	for step in _registry.keys():
		var bucket := _registry[step] as Array
		bucket.erase(block)
		if bucket.is_empty():
			_registry.erase(step)


## All registered blocks across every step, in no particular order. Skips any
## entries that have since been freed.
func blocks() -> Array:
	var out: Array = []
	for step in _registry.keys():
		for block in _registry[step]:
			if is_instance_valid(block):
				out.append(block)
	return out


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


## Fire every live block at [param step], brighten its marker, and announce it.
## Freed blocks are pruned from the bucket as they are encountered.
func _advance_to(step: int) -> void:
	_highlight(step)
	if _registry.has(step):
		var bucket := _registry[step] as Array
		var survivors: Array = []
		for block in bucket:
			if not is_instance_valid(block):
				continue
			survivors.append(block)
			if block.has_method("fire"):
				block.call("fire")
		if survivors.is_empty():
			_registry.erase(step)
		else:
			_registry[step] = survivors
	step_advanced.emit(step)


## Spike the marker for [param step] to full brightness.
func _highlight(step: int) -> void:
	if step >= 0 and step < _marker_energy.size():
		_marker_energy[step] = MARKER_BRIGHT
		_apply_marker_energy(step)


## Ease every marker's emission back toward the idle level.
func _decay_markers(delta: float) -> void:
	for i in _marker_energy.size():
		if _marker_energy[i] > MARKER_DIM:
			_marker_energy[i] = maxf(MARKER_DIM, _marker_energy[i] - MARKER_DECAY * delta)
			_apply_marker_energy(i)


func _apply_marker_energy(i: int) -> void:
	if i < 0 or i >= _markers.size():
		return
	var marker := _markers[i]
	if not is_instance_valid(marker):
		return
	var mat := marker.get_surface_override_material(0)
	if mat is StandardMaterial3D:
		(mat as StandardMaterial3D).emission_energy_multiplier = _marker_energy[i]


## Build the 16 step-marker spheres in a ring around the core. Each gets its own
## material instance so a single marker can brighten independently.
func _build_ring() -> void:
	_markers.clear()
	_marker_energy.clear()
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 8
	mesh.rings = 4
	for i in _timeline.steps:
		var marker := MeshInstance3D.new()
		marker.name = "StepMarker_%d" % i
		marker.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.92, 0.7)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.86, 0.55)
		mat.emission_energy_multiplier = MARKER_DIM
		marker.set_surface_override_material(0, mat)
		# Step 0 sits due north (-Z); angle increases clockwise toward +X.
		var angle := TAU * float(i) / float(_timeline.steps)
		marker.position = Vector3(sin(angle) * RING_RADIUS, RING_HEIGHT, -cos(angle) * RING_RADIUS)
		add_child(marker)
		_markers.append(marker)
		_marker_energy.append(MARKER_DIM)
