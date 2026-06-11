## Advances a Note Block to its next pentatonic pitch.
##
## The player interacting with a Note Block cycles its pitch; this command is
## that mutation expressed through the command layer. It is a guarded no-op
## unless the target is a live node in group [code]"note_blocks"[/code] that
## exposes [code]cycle_pitch[/code], so cores and arbitrary nodes are ignored.
class_name CycleNoteCommand
extends WorldCommand

var _target: Node


## Capture the [param target] note block to retune.
func _init(target: Node) -> void:
	_target = target


## Cycle the target's pitch when it is a valid Note Block; otherwise no-op.
func apply(_ctx: WorldContext) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if not _target.is_in_group(&"note_blocks"):
		return
	if _target.has_method("cycle_pitch"):
		_target.cycle_pitch()
