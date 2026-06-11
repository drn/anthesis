## FPS player controller for Anthesis.
##
## Handles movement, mouse-look, and input — emitting dig_requested /
## place_requested signals so the command layer can own mutation logic.
## No voxel terrain writes happen here (architecture rule).
class_name Player
extends CharacterBody3D

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted when the player requests to dig at a world position.
signal dig_requested(world_pos: Vector3, radius: float)

## Emitted when the player requests to place voxels at a world position.
signal place_requested(world_pos: Vector3, radius: float)

## Emitted when the player interacts with a harvestable prop.
## target is the prop's root Node; drops is its Array[ItemAmount].
signal harvest_requested(target: Node, drops: Array[ItemAmount])

## Emitted when the player activates a magic ability slot.
## slot is 1-indexed (1, 2, or 3); target_pos is the world-space hit point
## from the raycast, or a point 6 m along the camera forward when no surface
## is hit (abilities like Skyward do not require a surface target).
signal cast_requested(slot: int, target_pos: Vector3)

## Emitted when the player presses the strike key (F) and the raycast hits
## an umbral (CharacterBody3D in group "umbrals") within STRIKE_REACH metres.
## target_id is the collider's instance ID; hit_point is the collision point.
signal strike_requested(target_id: int, hit_point: Vector3)

## Emitted when the player presses N (place_core) and the raycast hits a surface.
## item_id is &"sequencer_core"; position is the hit point offset by the normal.
signal place_block_requested(item_id: StringName, position: Vector3)

## Emitted when the player presses E (interact) on a node in group "note_blocks".
## target is the note block's root Node.
signal block_interact_requested(target: Node)

## Emitted when the player presses F (strike) on a node in group "note_blocks"
## or "sequencer_cores".  target is the block's root Node.
signal block_remove_requested(target: Node)

## Emitted when the player toggles a burning channel (Phase 8): G -> &"vigor"
## (pewter), T -> &"keensight" (tin). World routes it through a ToggleChannelCommand.
signal channel_toggle_requested(channel_id: StringName)

## Emitted on flare key (Shift) press and release: active is true while held.
## Echo-guarded so auto-repeat does not re-fire it. Drives the flare multiplier.
signal flare_changed(active: bool)

## Emitted when the player throws a ferric coin (Q). origin is just ahead of the
## camera; velocity is the camera forward * FerricCoin.THROW_SPEED.
signal throw_coin_requested(origin: Vector3, velocity: Vector3)

## Emitted when the player presses R to inhale a charged gem (Phase 9). World
## routes it through an InhaleCommand; the TempestLight handles the exchange.
signal inhale_requested

## Emitted when the player presses E (interact) on a node in group
## "storm_catchers" (Phase 9). target is the catcher's root Node. World routes
## it through an InteractCatcherCommand (deposit dun gems / collect charged ones).
signal catcher_interact_requested(target: Node)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const WALK_SPEED := 5.5
const JUMP_VELOCITY := 5.0
const MOUSE_SENSITIVITY := 0.002
const DIG_RADIUS := 1.6
const PLACE_RADIUS := 1.4
## Maximum distance in metres at which a melee strike connects.
const STRIKE_REACH := 2.8

## User-adjustable mouse-look multiplier on top of MOUSE_SENSITIVITY.
## World pushes GameSettings.mouse_sensitivity into this.
var sensitivity_scale := 1.0

## Movement-speed multiplier driven by status effects (Phase 8): Vigor (pewter)
## raises it to 1.4, the pewter-drag crash drops it to 0.6, otherwise 1.0. World
## sets this through the StatusEffectSystem's apply/expire callables.
var speed_scale := 1.0

## Direction "down" gravity pulls the player (Phase 9 Skylash). Defaults to
## [constant Vector3.DOWN]; Skylash snaps it to a cardinal axis for a window,
## then restores it. Always paired with [member up_direction] = -gravity_dir so
## [method CharacterBody3D.is_on_floor] resolves against the active gravity.
var gravity_dir := Vector3.DOWN

# ---------------------------------------------------------------------------
# Node references (assigned in _ready)
# ---------------------------------------------------------------------------

var _camera: Camera3D
var _raycast: RayCast3D
var _mouse_captured := false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------


func _ready() -> void:
	_camera = $Camera3D
	_raycast = $Camera3D/RayCast3D
	# up_direction must track gravity_dir from the first frame so is_on_floor()
	# resolves correctly under the default downward gravity.
	up_direction = -gravity_dir
	_capture_mouse()


## Set the player's personal gravity direction (Phase 9 Skylash).
##
## [param dir] is normalized; a zero / near-zero vector falls back to
## [constant Vector3.DOWN] (normal gravity). [member up_direction] is kept as
## [code]-gravity_dir[/code] so floor detection and slide stay consistent.
func set_gravity_dir(dir: Vector3) -> void:
	if dir.length() < 0.0001:
		gravity_dir = Vector3.DOWN
	else:
		gravity_dir = dir.normalized()
	up_direction = -gravity_dir


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	# Mouse-look only while captured
	if event is InputEventMouseMotion and _mouse_captured:
		var sensitivity := MOUSE_SENSITIVITY * sensitivity_scale
		rotation.y -= event.relative.x * sensitivity
		_camera.rotation.x -= event.relative.y * sensitivity
		_camera.rotation.x = clamp(_camera.rotation.x, -PI * 0.45, PI * 0.45)
		return

	if event is InputEventMouseButton and event.pressed:
		if not _mouse_captured:
			_capture_mouse()
			return

		var action_dig := "dig"
		var action_place := "place"
		if InputMap.has_action(action_dig) and event.is_action(action_dig):
			_try_dig()
		elif InputMap.has_action(action_place) and event.is_action(action_place):
			_try_place()

	if event is InputEventKey and event.pressed:
		var action_interact := "interact"
		if InputMap.has_action(action_interact) and event.is_action_pressed(action_interact):
			_try_interact()

		var action_strike := "strike"
		if InputMap.has_action(action_strike) and event.is_action_pressed(action_strike):
			_try_strike()

		var action_place_core := "place_core"
		if InputMap.has_action(action_place_core) and event.is_action_pressed(action_place_core):
			_try_place_block(&"sequencer_core")

		var action_place_note := "place_note"
		if InputMap.has_action(action_place_note) and event.is_action_pressed(action_place_note):
			_try_place_block(&"note_block")

		var action_vigor := "burn_vigor"
		if InputMap.has_action(action_vigor) and event.is_action_pressed(action_vigor):
			channel_toggle_requested.emit(&"vigor")

		var action_keensight := "burn_keensight"
		if InputMap.has_action(action_keensight) and event.is_action_pressed(action_keensight):
			channel_toggle_requested.emit(&"keensight")

		var action_throw := "throw_coin"
		if InputMap.has_action(action_throw) and event.is_action_pressed(action_throw):
			_try_throw_coin()

		var action_inhale := "inhale"
		if InputMap.has_action(action_inhale) and event.is_action_pressed(action_inhale):
			inhale_requested.emit()

		var action_place_catcher := "place_catcher"
		if (
			InputMap.has_action(action_place_catcher)
			and event.is_action_pressed(action_place_catcher)
		):
			_try_place_block(&"storm_catcher")

		for slot in [1, 2, 3, 4, 5, 6, 7]:
			var action_cast := "cast_%d" % slot
			if InputMap.has_action(action_cast) and event.is_action_pressed(action_cast):
				cast_requested.emit(slot, _cast_target())

	# Flare (Shift) is a hold: emit on press and on release, echo-guarded so
	# keyboard auto-repeat does not re-fire it.
	if event is InputEventKey and not event.echo and InputMap.has_action("flare"):
		if event.is_action_pressed("flare"):
			flare_changed.emit(true)
		elif event.is_action_released("flare"):
			flare_changed.emit(false)


func _input(event: InputEvent) -> void:
	# Dig / place can also come from action-mapped buttons (keyboard, gamepad)
	# when the mouse is captured.  Mouse-button dig/place is handled in
	# _unhandled_input above; here we catch any other device events.
	if not _mouse_captured:
		return
	if event is InputEventMouseButton:
		return  # already handled above

	var action_dig := "dig"
	var action_place := "place"
	if InputMap.has_action(action_dig) and event.is_action_pressed(action_dig):
		_try_dig()
	elif InputMap.has_action(action_place) and event.is_action_pressed(action_place):
		_try_place()


# ---------------------------------------------------------------------------
# Physics
# ---------------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

	# Gravity pulls along gravity_dir (Phase 9 Skylash redirects it off DOWN).
	if not is_on_floor():
		velocity += gravity_dir * gravity * delta

	# Jump: launch along -gravity_dir. Zero the along-gravity component first so a
	# jump from a sideways-gravity wall gives a clean, full-strength push-off.
	var action_jump := "jump"
	if InputMap.has_action(action_jump) and Input.is_action_just_pressed(action_jump):
		if is_on_floor():
			velocity -= velocity.project(gravity_dir)
			velocity += -gravity_dir * JUMP_VELOCITY

	# Horizontal movement
	var input_dir := Vector2.ZERO
	var fwd := "move_forward"
	var bck := "move_back"
	var lft := "move_left"
	var rgt := "move_right"
	if InputMap.has_action(fwd):
		input_dir.y -= Input.get_action_strength(fwd)
	if InputMap.has_action(bck):
		input_dir.y += Input.get_action_strength(bck)
	if InputMap.has_action(lft):
		input_dir.x -= Input.get_action_strength(lft)
	if InputMap.has_action(rgt):
		input_dir.x += Input.get_action_strength(rgt)

	var direction := Vector3.ZERO
	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		# Transform input relative to player yaw (not camera pitch)
		direction = (transform.basis.x * input_dir.x + transform.basis.z * input_dir.y)

	# Smooth acceleration toward target horizontal speed. speed_scale carries the
	# Vigor boost / pewter-drag slow (Phase 8); default 1.0 is the base walk.
	var target_xz := direction * WALK_SPEED * speed_scale
	velocity.x = move_toward(velocity.x, target_xz.x, WALK_SPEED * delta * 10.0)
	velocity.z = move_toward(velocity.z, target_xz.z, WALK_SPEED * delta * 10.0)

	move_and_slide()


# ---------------------------------------------------------------------------
# Dig / place helpers
# ---------------------------------------------------------------------------


func _try_dig() -> void:
	if _raycast == null or not _raycast.is_colliding():
		return
	var hit := _raycast.get_collision_point()
	dig_requested.emit(hit, DIG_RADIUS)


func _try_place() -> void:
	if _raycast == null or not _raycast.is_colliding():
		return
	var hit := _raycast.get_collision_point()
	var normal := _raycast.get_collision_normal()
	# Build outward from the hit face so the new voxel sits outside the surface.
	place_requested.emit(hit + normal * 0.5, PLACE_RADIUS)


## Place a block item at the raycast hit surface (offset outward by the normal).
## item_id must be &"sequencer_core" or &"note_block".
func _try_place_block(item_id: StringName) -> void:
	if _raycast == null or not _raycast.is_colliding():
		return
	var hit := _raycast.get_collision_point()
	var normal := _raycast.get_collision_normal()
	place_block_requested.emit(item_id, hit + normal * 0.3)


## Walk the owner chain from collider toward the scene root and return the
## first node that is in the given group, or null if none is found.
func _root_in_group(collider: Node, group: StringName) -> Node:
	var candidate: Node = collider
	while candidate != null:
		if candidate.is_in_group(group):
			return candidate
		candidate = candidate.get_parent()
	return null


## Interact (E): if the hit prop is a note block, cycle its pitch via signal;
## otherwise fall through to harvest logic as before.
func _try_interact() -> void:
	if _raycast == null or not _raycast.is_colliding():
		return
	var collider := _raycast.get_collider()

	# Check for note_block first — interact cycles pitch.
	var note_block_root := _root_in_group(collider, &"note_blocks")
	if note_block_root != null:
		block_interact_requested.emit(note_block_root)
		return

	# Storm catcher (Phase 9): interact deposits dun gems / collects charged ones.
	var catcher_root := _root_in_group(collider, &"storm_catchers")
	if catcher_root != null:
		catcher_interact_requested.emit(catcher_root)
		return

	# Fall through to harvest logic.
	var candidate: Node = collider
	while candidate != null:
		var harvestable := candidate.get_node_or_null("Harvestable")
		if harvestable != null and harvestable is Harvestable:
			harvest_requested.emit(candidate, harvestable.drops)
			return
		candidate = candidate.get_parent()


func _try_strike() -> void:
	if _raycast == null or not _raycast.is_colliding():
		return
	var collider := _raycast.get_collider()
	var hit := _raycast.get_collision_point()
	var dist := global_transform.origin.distance_to(hit)

	# Block removal: F on a note_block or sequencer_core emits block_remove_requested.
	var block_root := _root_in_group(collider, &"note_blocks")
	if block_root == null:
		block_root = _root_in_group(collider, &"sequencer_cores")
	if block_root != null:
		if dist <= STRIKE_REACH:
			block_remove_requested.emit(block_root)
		return

	# Umbral melee strike — original behaviour.
	if not (collider is CharacterBody3D and collider.is_in_group("umbrals")):
		return
	if dist > STRIKE_REACH:
		return
	strike_requested.emit(collider.get_instance_id(), hit)


## Throw a ferric coin (Q): spawn it just ahead of the camera, hurled along the
## camera forward at [constant FerricCoin.THROW_SPEED]. World consumes one coin
## from the inventory before spawning, so an empty pouch makes this a no-op.
func _try_throw_coin() -> void:
	if _camera == null:
		return
	var forward := -_camera.global_transform.basis.z
	var origin := _camera.global_transform.origin + forward * 0.6
	throw_coin_requested.emit(origin, forward * FerricCoin.THROW_SPEED)


## Returns the raycast hit point when colliding, otherwise a point 6 m along
## the camera forward.  Used as the target for ability casts.
func _cast_target() -> Vector3:
	if _raycast != null and _raycast.is_colliding():
		return _raycast.get_collision_point()
	if _camera != null:
		return _camera.global_transform.origin + (-_camera.global_transform.basis.z) * 6.0
	return global_transform.origin


# ---------------------------------------------------------------------------
# Mouse capture helpers
# ---------------------------------------------------------------------------


func _capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_mouse_captured = true
