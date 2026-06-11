## Single entry point for executing world mutations.
##
## All gameplay code submits [WorldCommand]s here rather than mutating world
## state directly. The bus applies each command against a shared
## [WorldContext] and announces completion via [signal command_executed].
## Centralizing execution leaves a natural place to later add validation,
## ordering, logging, or network replication for an authoritative server.
class_name CommandBus
extends RefCounted

## Emitted after a command has been applied.
signal command_executed(cmd: WorldCommand)

var _ctx: WorldContext


## Construct with the [param ctx] commands will be applied against.
func _init(ctx: WorldContext) -> void:
	_ctx = ctx


## Apply [param cmd] against the context, then emit [signal command_executed].
func execute(cmd: WorldCommand) -> void:
	cmd.apply(_ctx)
	command_executed.emit(cmd)
