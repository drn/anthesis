## Places a sequencer block (Sequencer Core or Note Block) into the world.
##
## Routes the placement intent through [member WorldContext.block_place] so the
## inventory charge and scene spawn stay inside the command layer. A no-op when
## the service is unwired; the service itself refuses (without world change) when
## the item is not in stock.
class_name PlaceBlockCommand
extends WorldCommand

var _item_id: StringName
var _position: Vector3


## Capture the [param item_id] to place and the world [param position].
func _init(item_id: StringName, position: Vector3) -> void:
	_item_id = item_id
	_position = position


## Delegate to [member WorldContext.block_place]; silently no-op when unwired.
func apply(ctx: WorldContext) -> void:
	if ctx.block_place == null:
		return
	ctx.block_place.place(_item_id, _position)
