## Unit tests for [PlayerSync] — the co-op position-broadcast system.
##
## All tests drive the pure-logic method [method PlayerSync._apply_remote_state]
## directly; no live multiplayer peer is needed.  The [NetworkSession] is
## intentionally NOT set up — [PlayerSync.setup] is called with a null session
## so only the container-management logic is exercised.
extends GutTest

var _sync: PlayerSync
var _container: Node3D


func before_each() -> void:
	_container = Node3D.new()
	add_child_autofree(_container)

	_sync = PlayerSync.new()
	add_child_autofree(_sync)
	# Wire with a null session so no rpc machinery is touched in tests.
	_sync.setup(null, null, _container)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _avatar_count() -> int:
	return _container.get_child_count()


func _avatar_for(peer_id: int) -> RemotePlayer:
	return _sync._avatars.get(peer_id, null) as RemotePlayer


# ---------------------------------------------------------------------------
# _apply_remote_state — spawn on demand
# ---------------------------------------------------------------------------


func test_first_state_spawns_avatar() -> void:
	_sync._apply_remote_state(11, Vector3(1.0, 0.0, 0.0), 0.0)
	assert_eq(_avatar_count(), 1, "first packet must spawn one avatar in the container")


func test_spawned_avatar_is_remote_player() -> void:
	_sync._apply_remote_state(12, Vector3.ZERO, 0.0)
	var avatar := _avatar_for(12)
	assert_not_null(avatar, "avatar must be stored in _avatars keyed by peer_id")
	assert_true(avatar is RemotePlayer, "spawned avatar must be a RemotePlayer")


func test_spawned_avatar_has_correct_peer_id() -> void:
	_sync._apply_remote_state(55, Vector3.ZERO, 0.0)
	var avatar := _avatar_for(55)
	assert_eq(avatar.peer_id, 55, "spawned avatar must carry the correct peer_id")


func test_spawned_avatar_is_child_of_container() -> void:
	_sync._apply_remote_state(99, Vector3.ZERO, 0.0)
	var avatar := _avatar_for(99)
	assert_eq(avatar.get_parent(), _container, "avatar must be parented to the avatar_container")


# ---------------------------------------------------------------------------
# _apply_remote_state — updates existing avatar
# ---------------------------------------------------------------------------


func test_second_packet_does_not_spawn_another_avatar() -> void:
	_sync._apply_remote_state(20, Vector3.ZERO, 0.0)
	_sync._apply_remote_state(20, Vector3(5.0, 0.0, 0.0), 0.5)
	assert_eq(_avatar_count(), 1, "second packet for same peer must not spawn a second avatar")


func test_second_packet_updates_target_position() -> void:
	_sync._apply_remote_state(21, Vector3.ZERO, 0.0)
	var new_pos := Vector3(7.0, 0.0, 3.0)
	_sync._apply_remote_state(21, new_pos, 0.0)
	var avatar := _avatar_for(21)
	# Drive _process so the avatar moves toward the new target.
	avatar._process(0.016)
	var dist_to_new := avatar.global_position.distance_to(new_pos)
	assert_true(dist_to_new < 7.0, "avatar must have moved toward the updated target")


func test_multiple_peers_spawn_multiple_avatars() -> void:
	_sync._apply_remote_state(30, Vector3.ZERO, 0.0)
	_sync._apply_remote_state(31, Vector3(1.0, 0.0, 0.0), 0.0)
	_sync._apply_remote_state(32, Vector3(2.0, 0.0, 0.0), 0.0)
	assert_eq(_avatar_count(), 3, "one avatar per unique peer must be spawned")


# ---------------------------------------------------------------------------
# peer_left — frees avatar
# ---------------------------------------------------------------------------


func test_peer_left_frees_avatar() -> void:
	_sync._apply_remote_state(40, Vector3.ZERO, 0.0)
	assert_eq(_avatar_count(), 1, "pre-condition: avatar exists")
	_sync._on_peer_left(40)
	# queue_free schedules deletion; avatar must no longer be in _avatars dict.
	assert_false(_sync._avatars.has(40), "peer_left must remove avatar from _avatars dict")


func test_peer_left_unknown_peer_is_safe() -> void:
	# Should not crash when a peer_left arrives for an unknown id.
	_sync._on_peer_left(999)
	assert_eq(_avatar_count(), 0, "no avatar must exist for unknown peer after peer_left")


func test_peer_left_leaves_other_avatars_intact() -> void:
	_sync._apply_remote_state(50, Vector3.ZERO, 0.0)
	_sync._apply_remote_state(51, Vector3(1.0, 0.0, 0.0), 0.0)
	_sync._on_peer_left(50)
	assert_false(_sync._avatars.has(50), "departed peer avatar must be removed")
	assert_true(_sync._avatars.has(51), "remaining peer avatar must be kept")


# ---------------------------------------------------------------------------
# session_ended — clears all avatars
# ---------------------------------------------------------------------------


func test_session_ended_clears_all_avatars() -> void:
	_sync._apply_remote_state(60, Vector3.ZERO, 0.0)
	_sync._apply_remote_state(61, Vector3(1.0, 0.0, 0.0), 0.0)
	assert_eq(_avatar_count(), 2, "pre-condition: two avatars exist")
	_sync._on_session_ended()
	assert_eq(_sync._avatars.size(), 0, "session_ended must clear _avatars dict")


func test_session_ended_with_no_avatars_is_safe() -> void:
	_sync._on_session_ended()
	assert_eq(_sync._avatars.size(), 0, "session_ended on empty state must not crash")
