## Interact with a [StormCatcher]: deposit dun gems or collect charged ones.
##
## InteractCatcherCommand is the authoritative entry point for all storm-catcher
## interactions. The semantics are deposit-or-collect: if the catcher holds any
## gems (dun + charged > 0) the player collects them all and the counts are added
## to the player's inventory; otherwise the player deposits dun gems up to the
## catcher's remaining capacity and the deposited amount is removed from inventory.
##
## The catcher argument is validated with duck-typing: null, freed, or anything
## that does not expose the expected [StormCatcher] interface is silently ignored,
## so the caller never needs to guard. All inventory mutations route through the
## command layer via this class — no presentation code touches gems directly.
##
## The command is client-local: it is not encoded in [CommandCodec].
class_name InteractCatcherCommand
extends WorldCommand

var _catcher: Node


## Capture the [param catcher] node to interact with.
func _init(catcher: Node) -> void:
	_catcher = catcher


## Deposit or collect gems via [member _catcher], routing inventory changes
## through [member WorldContext.inventory].
##
## No-op when the catcher is null, freed, or lacks the [StormCatcher] interface.
## No-op when inventory is null. Collect path: if catcher holds any gems, collect
## returns them all and they are added to inventory. Deposit path: if catcher is
## empty, up to [code]min(StormCatcher.CAPACITY, inventory.count_of(&"dun_gem"))[/code]
## dun gems are deposited; the accepted count (deposit's return value) is removed
## from inventory.
func apply(ctx: WorldContext) -> void:
	if _catcher == null or not is_instance_valid(_catcher):
		return
	if not _catcher.has_method("collect") or not _catcher.has_method("deposit"):
		return
	if ctx.inventory == null:
		return
	var dun: int = _catcher.dun_count()
	var charged: int = _catcher.charged_count()
	if dun + charged > 0:
		var result: Dictionary = _catcher.collect()
		var dun_collected: int = result.get("dun", 0)
		var charged_collected: int = result.get("charged", 0)
		if dun_collected > 0:
			ctx.inventory.add(&"dun_gem", dun_collected)
		if charged_collected > 0:
			ctx.inventory.add(&"charged_gem", charged_collected)
	else:
		var available: int = ctx.inventory.count_of(&"dun_gem")
		var to_deposit: int = mini(StormCatcher.CAPACITY, available)
		if to_deposit > 0:
			var accepted: int = _catcher.deposit(to_deposit)
			if accepted > 0:
				ctx.inventory.remove(&"dun_gem", accepted)
