## Inhales a charged gem to fill the [TempestLight] well.
##
## InhaleCommand is the authoritative entry point for inhaling tempest investiture.
## It routes the request through [member WorldContext.tempest] so the gem exchange —
## removing one charged_gem and crediting dun_gem + well charge — stays inside the
## command layer. When no [TempestLight] is wired (legacy / unit-test contexts with
## no tempest) the command is a silent no-op, mirroring the null-tolerance of every
## other command.
##
## The command is client-local: it carries no parameters beyond what the context
## already holds and is not encoded in [CommandCodec].
class_name InhaleCommand
extends WorldCommand


## No parameters; the target is always the local player's well and inventory,
## both available on [WorldContext].
func _init() -> void:
	pass


## Route the inhale through [member WorldContext.tempest].
##
## Silently does nothing when no tempest system is wired. Delegates inventory
## exchange (charged_gem → dun_gem + well charge) entirely to
## [method TempestLight.inhale] so the cost/exchange logic lives in one place.
func apply(ctx: WorldContext) -> void:
	if ctx.tempest == null:
		return
	ctx.tempest.inhale(ctx.inventory)
