## Removes a sequencer block from the world and refunds it to the inventory.
##
## Routes through [member WorldContext.block_place] to remove the target block
## and learn which item it represents, then credits that item back to the
## player's inventory. Keeping the refund here (rather than in the service) lets
## removal mirror the inventory side of [PlaceBlockCommand]. A no-op when the
## service is unwired or the target is not a recognised block.
class_name RemoveBlockCommand
extends WorldCommand

var _target: Node


## Capture the [param target] block node to remove.
func _init(target: Node) -> void:
	_target = target


## Remove the block and refund its item id when one was returned.
func apply(ctx: WorldContext) -> void:
	if ctx.block_place == null:
		return
	var id := ctx.block_place.remove(_target)
	if id != &"" and ctx.inventory != null:
		ctx.inventory.add(id, 1)
