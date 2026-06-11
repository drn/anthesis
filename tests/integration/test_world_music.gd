extends GutTest

# ---------------------------------------------------------------------------
# Integration test — adaptive music wiring (Phase 5, contract #6).
#
# Boots world.tscn and asserts the soundtrack is composed: a MusicSystem with
# one playing player per stem, a shared IntensityModel exposed for introspection,
# and the command_executed -> on_event event source feeding heat into that model.
# Kept in its own file (mirroring test_world_combat.gd) so test_world_boot.gd
# stays under the 20-public-method lint cap.
# ---------------------------------------------------------------------------

const WORLD_SCENE := "res://scenes/world/world.tscn"


func _boot() -> World:
	var world: World = load(WORLD_SCENE).instantiate()
	add_child_autofree(world)
	return world


func test_music_system_present_with_five_stems() -> void:
	var world := _boot()
	var mus := world.music()
	assert_not_null(mus, "music() must return a MusicSystem")
	assert_true(mus is MusicSystem, "music() must be a MusicSystem")
	assert_true(mus.is_inside_tree(), "the MusicSystem must be in the scene tree")
	var stem_players := mus.players()
	assert_eq(stem_players.size(), 5, "the mixer must build one player per stem (5)")
	for player in stem_players:
		assert_true(player.playing, "every stem player must be playing after setup")


func test_intensity_model_wired() -> void:
	var world := _boot()
	var model := world.intensity()
	assert_not_null(model, "intensity() must return an IntensityModel")
	assert_true(model is IntensityModel, "intensity() must be an IntensityModel")
	assert_eq(model.level(), 0.0, "intensity must start at zero")
	assert_eq(world.music().model(), model, "the mixer must read the same IntensityModel")


func test_command_through_bus_raises_intensity() -> void:
	# A gameplay intent flowing through the bus must feed heat into the model the
	# soundtrack reads, proving the command_executed -> on_event wiring is live.
	# We route a HarvestCommand (with a null target) rather than a DigCommand:
	# both share the identical command_executed path, but a live dig calls the
	# voxel tool whose chunks have not streamed in headless ("Area not editable"),
	# which GUT would flag as an unexpected engine error. Harvest is side-effect
	# free here (loot is empty, no target to free), so it isolates the wiring.
	var world := _boot()
	var model := world.intensity()
	assert_eq(model.level(), 0.0, "precondition: intensity starts at zero")
	var no_drops: Array[ItemAmount] = []
	world.command_bus().execute(HarvestCommand.new(null, no_drops))
	assert_gt(model.level(), 0.0, "a command through the bus must raise the intensity level")
