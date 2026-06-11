## Lumen Bloom mote — a short-lived, pulsing orb of living light.
##
## Spawned by the lumen_bloom ability effect.  The mote emits magenta-white
## light into the world and self-destructs after [member lifetime_s] seconds.
## All animation is presentation-only (sine on light energy); no simulation
## state lives here.
class_name LumenBloomMote
extends Node3D

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

## How long the mote lives before freeing itself.
@export var lifetime_s := 25.0

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

var _light: OmniLight3D
var _mesh: MeshInstance3D

## Base energy restored each frame via sine pulse.
var _base_energy := 2.5
var _pulse_time := 0.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------


func _ready() -> void:
	_light = get_node_or_null("OmniLight3D")
	_mesh = get_node_or_null("MeshInstance3D")
	get_tree().create_timer(lifetime_s).timeout.connect(_on_lifetime_expired)


func _process(delta: float) -> void:
	_pulse_time += delta
	if _light != null:
		_light.light_energy = _base_energy + sin(_pulse_time * 2.5) * 0.6


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------


## Configure the mote's light radius and scale.
## Called by the ability effect immediately after spawning.
func configure(radius: float) -> void:
	if _light != null:
		_light.omni_range = radius
	if _mesh != null:
		var scale_factor := clampf(radius / 6.0, 0.5, 2.0)
		_mesh.scale = Vector3.ONE * scale_factor


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


func _on_lifetime_expired() -> void:
	queue_free()
