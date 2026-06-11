## Toggles a burning channel (e.g. vigor, keensight) via the [ChannelSystem].
##
## ToggleChannelCommand is the authoritative entry point for flipping a metal-
## burning channel on or off. It carries the channel id and routes the request
## through [member WorldContext.channels] so the toggle — including the cost
## check, drain start, and on_start/on_stop callbacks — stays inside the command
## layer. When no [ChannelSystem] is wired the command is a silent no-op,
## mirroring the null-tolerance of every other command.
class_name ToggleChannelCommand
extends WorldCommand

var _channel_id: StringName


## Capture the [param channel_id] to toggle (e.g. [code]&"vigor"[/code]).
func _init(channel_id: StringName) -> void:
	_channel_id = channel_id


## Route the toggle through [member WorldContext.channels].
##
## Silently does nothing when no channel system is wired.
func apply(ctx: WorldContext) -> void:
	if ctx.channels == null:
		return
	ctx.channels.toggle(_channel_id)
