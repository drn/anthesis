extends GutTest


## A [TerrainEditService] subclass that records calls instead of editing.
class RecordingEditService:
	extends TerrainEditService

	var calls: Array = []

	func dig_sphere(center: Vector3, radius: float) -> void:
		calls.append({"op": "dig", "center": center, "radius": radius})

	func place_sphere(center: Vector3, radius: float) -> void:
		calls.append({"op": "place", "center": center, "radius": radius})


func _make_context() -> WorldContext:
	var ctx := WorldContext.new()
	ctx.terrain_edit = RecordingEditService.new()
	return ctx


func test_dig_command_routes_to_dig_sphere() -> void:
	var ctx := _make_context()
	var recorder: RecordingEditService = ctx.terrain_edit

	DigCommand.new(Vector3(1, 2, 3), 1.6).apply(ctx)

	assert_eq(recorder.calls.size(), 1)
	assert_eq(recorder.calls[0]["op"], "dig")
	assert_eq(recorder.calls[0]["center"], Vector3(1, 2, 3))
	assert_eq(recorder.calls[0]["radius"], 1.6)


func test_place_command_routes_to_place_sphere() -> void:
	var ctx := _make_context()
	var recorder: RecordingEditService = ctx.terrain_edit

	PlaceCommand.new(Vector3(4, 5, 6), 2.5).apply(ctx)

	assert_eq(recorder.calls.size(), 1)
	assert_eq(recorder.calls[0]["op"], "place")
	assert_eq(recorder.calls[0]["center"], Vector3(4, 5, 6))
	assert_eq(recorder.calls[0]["radius"], 2.5)


func test_command_bus_applies_command() -> void:
	var ctx := _make_context()
	var recorder: RecordingEditService = ctx.terrain_edit
	var bus := CommandBus.new(ctx)

	bus.execute(DigCommand.new(Vector3.ZERO, 1.0))

	assert_eq(recorder.calls.size(), 1)
	assert_eq(recorder.calls[0]["op"], "dig")


func test_command_bus_emits_command_executed() -> void:
	var ctx := _make_context()
	var bus := CommandBus.new(ctx)
	watch_signals(bus)

	var cmd := PlaceCommand.new(Vector3.ONE, 1.0)
	bus.execute(cmd)

	assert_signal_emitted(bus, "command_executed")
	assert_signal_emitted_with_parameters(bus, "command_executed", [cmd])
