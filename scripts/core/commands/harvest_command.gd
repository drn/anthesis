## Harvests a flora prop: awards its drops then removes it from the scene.
##
## HarvestCommand is the authoritative mutation for prop harvesting. It awards
## loot via [LootService] first, then calls the [member WorldContext.flora_harvest]
## Callable to free the prop node, so the order is always: inventory updated,
## then prop removed — never the reverse.
class_name HarvestCommand
extends WorldCommand

var _target: Node
var _drops: Array[ItemAmount]


## Capture the [param target] prop node and its [param drops] loot table.
func _init(target: Node, drops: Array[ItemAmount]) -> void:
	_target = target
	_drops = drops


## Award drops via [LootService] then remove [member _target] via flora_harvest.
##
## If [member WorldContext.loot] is null the drops are silently skipped.
## The flora_harvest Callable is only called when it is valid, so callers in
## unit tests that leave it as the default invalid [Callable] are safe.
func apply(ctx: WorldContext) -> void:
	if ctx.loot != null:
		ctx.loot.award_harvest_loot(_drops)
	if ctx.flora_harvest.is_valid():
		ctx.flora_harvest.call(_target)
