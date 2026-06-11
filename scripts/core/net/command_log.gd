## Ordered, bounded record of committed replication dictionaries.
##
## The host appends every committed command's encoded form here (see
## [CommandCodec]) so a late-joining peer can replay the world from its seed.
## Replay order matters — deterministic block names and sequencer adoption both
## depend on commands being applied in the exact sequence the host committed
## them — so the log is a plain ordered list, never reordered.
##
## The log is bounded at [constant MAX_ENTRIES]. Beyond that, the oldest entries
## are dropped and counted via [method dropped]. A late joiner arriving after a
## drop reconstructs a partial world (the dropped edits are lost); this is an
## accepted v0 trade-off for a bounded memory footprint, and [method dropped]
## lets callers surface it.
class_name CommandLog
extends RefCounted

## Maximum retained entries; older entries are dropped past this.
const MAX_ENTRIES := 5000

var _entries: Array[Dictionary] = []
var _dropped: int = 0


## Append [param data] (a [CommandCodec] wire dictionary) to the log.
##
## When the log is already at [constant MAX_ENTRIES], the oldest entry is
## evicted first and [method dropped] is incremented, so the size never exceeds
## the cap. The entry is stored as a deep copy so later mutation of the caller's
## dictionary cannot corrupt the recorded history.
func append(data: Dictionary) -> void:
	if _entries.size() >= MAX_ENTRIES:
		_entries.pop_front()
		_dropped += 1
	_entries.append(data.duplicate(true))


## A deep copy of every retained entry, in commit order.
##
## Callers receive copies, so mutating the returned array or its dictionaries
## never affects the log's internal state.
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _entries:
		out.append(e.duplicate(true))
	return out


## The number of entries currently retained (at most [constant MAX_ENTRIES]).
func size() -> int:
	return _entries.size()


## How many entries have been evicted due to the [constant MAX_ENTRIES] bound.
func dropped() -> int:
	return _dropped


## Forget all entries and reset the dropped count (e.g. when a session ends).
func clear() -> void:
	_entries.clear()
	_dropped = 0
