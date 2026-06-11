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

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const WALK_SPEED := 5.5
const JUMP_VELOCITY := 5.0
const MOUSE_SENSITIVITY := 0.002
const DIG_RADIUS := 1.6
const PLACE_RADIUS := 1.4

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


# ---------------------------------------------------------------------------
# Mouse capture helpers
# ---------------------------------------------------------------------------


func _capture_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_mouse_captured = true


func _release_mouse() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_mouse_captured = false
