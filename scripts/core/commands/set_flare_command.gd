## Arms or disarms the flare multiplier on the [ChannelSystem].
##
## SetFlareCommand is the authoritative entry point for raising or lowering the
## flare flag. While flaring, every active channel's drain is multiplied by
## [constant ChannelSystem.FLARE_DRAIN_MULT], burning through reserves faster
## in exchange for heightened effect. When no [ChannelSystem] is wired the
## command is a silent no-op, mirroring the null-tolerance of every other command.
class_name SetFlareCommand
extends WorldCommand

var _active: bool


## Capture whether flare should be [param active] (true) or disarmed (false).
func _init(active: bool) -> void:
	_active = active


## Route the flare change through [member WorldContext.channels].
##
## Silently does nothing when no channel system is wired.
func apply(ctx: WorldContext) -> void:
	if ctx.channels == null:
		return
	ctx.channels.set_flare(_active)
