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
	_capture_mouse()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	# Mouse-look only while captured
	if event is InputEventMouseMotion and _mouse_captured:
		rotation.y -= event.relative.x * MOUSE_SENSITIVITY
		_camera.rotation.x -= event.relative.y * MOUSE_SENSITIVITY
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
		var action_toggle := "toggle_mouse_capture"
		if InputMap.has_action(action_toggle) and event.is_action_pressed(action_toggle):
			_release_mouse()

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

		for slot in [1, 2, 3]:
			var action_cast := "cast_%d" % slot
			if InputMap.has_action(action_cast) and event.is_action_pressed(action_cast):
				cast_requested.emit(slot, _cast_target())


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

	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump
	var action_jump := "jump"
	if InputMap.has_action(action_jump) and Input.is_action_just_pressed(action_jump):
		if is_on_floor():
			velocity.y = JUMP_VELOCITY

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

	# Smooth acceleration toward target horizontal speed
	var target_xz := direction * WALK_SPEED
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


func _release_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_mouse_captured = false
