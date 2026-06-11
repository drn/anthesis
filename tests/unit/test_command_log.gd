## Tests CommandLog: append/size, entries() hands back deep copies, the
## MAX_ENTRIES bound evicts oldest-first, and dropped() counts evictions.
extends GutTest

var _log: CommandLog


func before_each() -> void:
	_log = CommandLog.new()


func test_starts_empty() -> void:
	assert_eq(_log.size(), 0, "fresh log is empty")
	assert_eq(_log.dropped(), 0, "nothing dropped yet")
	assert_eq(_log.entries(), [], "no entries")


func test_append_grows_size_in_order() -> void:
	_log.append({"t": "dig", "r": 1.0})
	_log.append({"t": "place", "r": 2.0})
	assert_eq(_log.size(), 2, "two entries")
	var e := _log.entries()
	assert_eq(e[0]["t"], "dig", "first appended is first out")
	assert_eq(e[1]["t"], "place", "second appended is second out")


func test_entries_returns_deep_copies() -> void:
	_log.append({"t": "dig", "c": [1, 2, 3]})
	var first := _log.entries()
	# Mutate the returned copy, both the dict and its nested array.
	first[0]["t"] = "MUTATED"
	(first[0]["c"] as Array).append(99)
	var second := _log.entries()
	assert_eq(second[0]["t"], "dig", "stored tag unaffected by caller mutation")
	assert_eq(second[0]["c"], [1, 2, 3], "nested array unaffected (deep copy)")


func test_append_copies_input() -> void:
	var src := {"t": "dig", "c": [0, 0, 0]}
	_log.append(src)
	# Mutate the caller's dictionary after appending.
	src["t"] = "CHANGED"
	(src["c"] as Array).append(7)
	var e := _log.entries()
	assert_eq(e[0]["t"], "dig", "log unaffected by post-append source mutation")
	assert_eq(e[0]["c"], [0, 0, 0], "nested source array did not leak in")


func test_clear_resets_size_and_dropped() -> void:
	_log.append({"t": "dig"})
	_log.append({"t": "place"})
	_log.clear()
	assert_eq(_log.size(), 0, "cleared to empty")
	assert_eq(_log.dropped(), 0, "dropped reset by clear")
	assert_eq(_log.entries(), [], "no entries after clear")


# ---------------------------------------------------------------------------
# Bound at MAX_ENTRIES
# ---------------------------------------------------------------------------


func test_bound_caps_size_and_drops_oldest() -> void:
	var cap := CommandLog.MAX_ENTRIES
	# Append one past the cap; the very first entry must be evicted.
	for i in range(cap + 1):
		_log.append({"t": "dig", "i": i})
	assert_eq(_log.size(), cap, "size never exceeds the cap")
	assert_eq(_log.dropped(), 1, "exactly one entry dropped")
	var e := _log.entries()
	assert_eq(e[0]["i"], 1, "oldest (i=0) evicted; i=1 is now first")
	assert_eq(e[cap - 1]["i"], cap, "newest entry retained at the tail")


func test_bound_drops_count_accumulates() -> void:
	var cap := CommandLog.MAX_ENTRIES
	for i in range(cap + 5):
		_log.append({"i": i})
	assert_eq(_log.size(), cap, "still capped")
	assert_eq(_log.dropped(), 5, "five evictions counted")
	var e := _log.entries()
	assert_eq(e[0]["i"], 5, "first five evicted; i=5 leads")
