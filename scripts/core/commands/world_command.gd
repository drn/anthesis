## Abstract base for all world mutations.
##
## Every change to authoritative world state is expressed as a WorldCommand
## and routed through the [CommandBus]. This keeps mutation logic in one
## auditable place and leaves room for a future authoritative server to
## validate, order, and replay commands. Subclasses capture their parameters
## in [method _init] and act on the world through the [WorldContext] in
## [method apply].
class_name WorldCommand
extends RefCounted


## Apply this command's effect using services on [param _ctx].
##
## Subclasses must override. The base implementation reports misuse.
func apply(_ctx: WorldContext) -> void:
	push_error("WorldCommand.apply is abstract; override it in a subclass")
