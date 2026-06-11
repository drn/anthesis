## A ferric coin — a throwable RigidBody3D that participates in the metal-source
## protocol and damages Umbrals on high-speed impact.
##
## FerricCoin joins [code]metal_sources[/code] and [code]umbrals[/code]-targeting
## collision monitoring in [method _ready]. Anchor state follows the physics rest
## rule: sleeping OR velocity below 0.5 m/s. It self-destructs after 60 seconds
## and emits [signal struck] when it contacts an Umbral at speed.
class_name FerricCoin
extends RigidBody3D

## Emitted when the coin strikes an Umbral; damage routing happens in World.
signal struck(target_id: int, speed: float)

## Speed (m/s) used by the throw command to set initial linear_velocity.
const THROW_SPEED := 18.0

## Seconds before an untouched coin despawns.
const DESPAWN_TIME := 60.0

## Minimum velocity magnitude to consider the coin at rest.
const REST_SPEED := 0.5

## Metal-source protocol (#7).
var metal_mass := 0.4


func _ready() -> void:
	add_to_group(&"metal_sources")
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_start_despawn_timer()
	_build_visuals()


## Metal-source protocol (#7): coin is anchored when sleeping or nearly still.
func is_metal_anchored() -> bool:
	return sleeping or linear_velocity.length() < REST_SPEED


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	if not body.is_in_group("umbrals"):
		return
	var spd := linear_velocity.length()
	struck.emit(body.get_instance_id(), spd)


func _start_despawn_timer() -> void:
	var timer := Timer.new()
	timer.name = "DespawnTimer"
	timer.wait_time = DESPAWN_TIME
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(queue_free)
	add_child(timer)


func _build_visuals() -> void:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "CoinMesh"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.07
	cyl.height = 0.015
	mesh_inst.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.62, 0.28, 1)
	mat.metallic = 0.85
	mat.roughness = 0.2
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.48, 0.1, 1)
	mat.emission_energy_multiplier = 0.6
	mesh_inst.set_surface_override_material(0, mat)
	add_child(mesh_inst)

	var light := OmniLight3D.new()
	light.name = "CoinLight"
	light.light_color = Color(0.9, 0.75, 0.3, 1)
	light.light_energy = 0.5
	light.omni_range = 2.5
	light.shadow_enabled = false
	add_child(light)

	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var sph := SphereShape3D.new()
	sph.radius = 0.08
	col.shape = sph
	add_child(col)
