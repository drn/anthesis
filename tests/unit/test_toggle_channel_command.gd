extends GutTest

## Covers [ToggleChannelCommand] and [SetFlareCommand]: routing through the
## channel system, null-context safety, and the command-bus execution path.


## Lightweight channel-system fake that records calls without a real scene tree.
class ChannelStub:
	extends RefCounted

	var toggles: Array = []
	var flares: Array = []
	var _active: Dictionary = {}

	func toggle(channel_id: StringName) -> bool:
		toggles.append(channel_id)
		_active[channel_id] = not _active.get(channel_id, false)
		return _active[channel_id]

	func is_active(channel_id: StringName) -> bool:
		return _active.get(channel_id, false)

	func set_flare(active: bool) -> void:
		flares.append(active)


# ---------------------------------------------------------------------------
# ToggleChannelCommand
# ---------------------------------------------------------------------------


func test_toggle_routes_to_channel_system() -> void:
	var stub := ChannelStub.new()
	var ctx := WorldContext.new()
	ctx.channels = stub
	ToggleChannelCommand.new(&"vigor").apply(ctx)
	assert_eq(stub.toggles.size(), 1)
	assert_eq(stub.toggles[0], &"vigor")


func test_toggle_second_call_toggles_off() -> void:
	var stub := ChannelStub.new()
	var ctx := WorldContext.new()
	ctx.channels = stub
	ToggleChannelCommand.new(&"vigor").apply(ctx)
	ToggleChannelCommand.new(&"vigor").apply(ctx)
	assert_eq(stub.toggles.size(), 2)
	assert_false(stub.is_active(&"vigor"))


func test_toggle_different_channels_are_independent() -> void:
	var stub := ChannelStub.new()
	var ctx := WorldContext.new()
	ctx.channels = stub
	ToggleChannelCommand.new(&"vigor").apply(ctx)
	ToggleChannelCommand.new(&"keensight").apply(ctx)
	assert_eq(stub.toggles.size(), 2)
	assert_true(stub.is_active(&"vigor"))
	assert_true(stub.is_active(&"keensight"))


func test_toggle_noop_when_channels_null() -> void:
	var ctx := WorldContext.new()  # channels not wired
	# Must not crash.
	ToggleChannelCommand.new(&"vigor").apply(ctx)
	assert_true(true)


func test_toggle_routes_through_command_bus() -> void:
	var stub := ChannelStub.new()
	var ctx := WorldContext.new()
	ctx.channels = stub
	var bus := CommandBus.new(ctx)
	bus.execute(ToggleChannelCommand.new(&"keensight"))
	assert_eq(stub.toggles.size(), 1)
	assert_eq(stub.toggles[0], &"keensight")


# ---------------------------------------------------------------------------
# SetFlareCommand
# ---------------------------------------------------------------------------


func test_set_flare_true_routes_to_channel_system() -> void:
	var stub := ChannelStub.new()
	var ctx := WorldContext.new()
	ctx.channels = stub
	SetFlareCommand.new(true).apply(ctx)
	assert_eq(stub.flares.size(), 1)
	assert_true(stub.flares[0])


func test_set_flare_false_routes_to_channel_system() -> void:
	var stub := ChannelStub.new()
	var ctx := WorldContext.new()
	ctx.channels = stub
	SetFlareCommand.new(false).apply(ctx)
	assert_eq(stub.flares.size(), 1)
	assert_false(stub.flares[0])


func test_set_flare_noop_when_channels_null() -> void:
	var ctx := WorldContext.new()  # channels not wired
	# Must not crash.
	SetFlareCommand.new(true).apply(ctx)
	assert_true(true)


func test_set_flare_routes_through_command_bus() -> void:
	var stub := ChannelStub.new()
	var ctx := WorldContext.new()
	ctx.channels = stub
	var bus := CommandBus.new(ctx)
	bus.execute(SetFlareCommand.new(true))
	assert_eq(stub.flares.size(), 1)
	assert_true(stub.flares[0])
