## Harvests a flora prop: awards its drops then removes it from the scene.
##
## HarvestCommand is the authoritative mutation for prop harvesting. It awards
## loot via [LootService] first, gathers Lumen from the prop's [Harvestable] into
## the player's well, then calls the [member WorldContext.flora_harvest] Callable
## to free the prop node. The order is always: inventory updated, lumen gathered,
## then prop removed — never the reverse.
##
## Gathering living flora is the only source of the Lumen investiture: a prop's
## [member Harvestable.lumen] is credited via [member WorldContext.lumen_gain]
## when both the magic system and that gain Callable are wired. All magic hooks
## are guarded so contexts that wire none of them (legacy / unit tests) behave
## exactly as before.
class_name HarvestCommand
extends WorldCommand

var _target: Node
var _drops: Array[ItemAmount]


## Capture the [param target] prop node and its [param drops] loot table.
func _init(target: Node, drops: Array[ItemAmount]) -> void:
	_target = target
	_drops = drops


## Award drops, gather Lumen, then remove [member _target] via flora_harvest.
##
## If [member WorldContext.loot] is null the drops are silently skipped. Lumen is
## credited only when the magic system and [member WorldContext.lumen_gain] are
## both wired and the target owns a [Harvestable] with positive lumen. The
## flora_harvest Callable is only called when it is valid, so callers in unit
## tests that leave any of these as defaults are safe.
func apply(ctx: WorldContext) -> void:
	if ctx.loot != null:
		ctx.loot.award_harvest_loot(_drops)
	_gather_lumen(ctx)
	if ctx.flora_harvest.is_valid():
		ctx.flora_harvest.call(_target)


## Credit the target's [Harvestable] lumen into the well via ctx.lumen_gain.
##
## No-op unless magic is wired, lumen_gain is valid, and the target carries a
## [Harvestable] child with a positive [member Harvestable.lumen].
func _gather_lumen(ctx: WorldContext) -> void:
	if ctx.magic == null or not ctx.lumen_gain.is_valid():
		return
	if _target == null or not is_instance_valid(_target):
		return
	var harvestable := _target.get_node_or_null("Harvestable") as Harvestable
	if harvestable == null or harvestable.lumen <= 0.0:
		return
	ctx.lumen_gain.call(harvestable.lumen)
