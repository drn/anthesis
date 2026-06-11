extends GutTest

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


## Build an in-memory registry whose items have the given max_stacks.
## stacks: Dictionary[StringName, int].
func _registry_with(stacks: Dictionary) -> ItemRegistry:
	# Point both scan dirs at a nonexistent path so the registry starts empty,
	# then inject definitions directly.
	var reg := ItemRegistry.new("res://__no_items__", "res://__no_recipes__")
	for id in stacks:
		var def := ItemDef.new()
		def.id = id
		def.display_name = String(id)
		def.max_stack = stacks[id]
		reg._items[id] = def
	return reg


func _count_signal(inv: Inventory) -> Array:
	# Returns a one-element array we can mutate as a counter inside a lambda.
	var counter := [0]
	inv.changed.connect(func() -> void: counter[0] += 1)
	return counter


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------


func test_default_size_and_empty() -> void:
	var inv := Inventory.new()
	assert_eq(inv.size(), 24, "Default inventory must have 24 slots")
	assert_true(inv.is_empty(), "Fresh inventory must be empty")
	assert_eq(inv.slot(0), {}, "Empty slot must return {}")


func test_custom_size() -> void:
	var inv := Inventory.new(6)
	assert_eq(inv.size(), 6, "Inventory must honor requested size")


# ---------------------------------------------------------------------------
# Adding & stacking
# ---------------------------------------------------------------------------


func test_add_single_stack() -> void:
	var inv := Inventory.new(4)
	var leftover := inv.add(&"soil", 5)
	assert_eq(leftover, 0, "Everything should fit")
	assert_eq(inv.count_of(&"soil"), 5, "Count must reflect added items")
	assert_eq(inv.slot(0), {"id": &"soil", "count": 5}, "First slot holds the stack")
	assert_false(inv.is_empty(), "Inventory is no longer empty")


func test_max_stack_without_registry_defaults_99() -> void:
	var inv := Inventory.new(4)
	var leftover := inv.add(&"soil", 100)
	assert_eq(leftover, 0, "100 fits across two slots (99 + 1)")
	assert_eq(inv.slot(0), {"id": &"soil", "count": 99}, "First slot caps at 99")
	assert_eq(inv.slot(1), {"id": &"soil", "count": 1}, "Overflow spills to next slot")


func test_max_stack_honored_with_registry() -> void:
	var reg := _registry_with({&"crystal_shard": 10})
	var inv := Inventory.new(4, reg)
	inv.add(&"crystal_shard", 25)
	assert_eq(inv.slot(0), {"id": &"crystal_shard", "count": 10}, "Stack 1 caps at 10")
	assert_eq(inv.slot(1), {"id": &"crystal_shard", "count": 10}, "Stack 2 caps at 10")
	assert_eq(inv.slot(2), {"id": &"crystal_shard", "count": 5}, "Remainder in stack 3")
	assert_eq(inv.count_of(&"crystal_shard"), 25, "Total preserved")


func test_add_overflow_returns_remainder() -> void:
	var reg := _registry_with({&"soil": 10})
	var inv := Inventory.new(2, reg)
	var leftover := inv.add(&"soil", 25)
	assert_eq(leftover, 5, "Only 20 fit in two stacks of 10; 5 overflow")
	assert_eq(inv.count_of(&"soil"), 20, "Stored exactly capacity")


func test_add_tops_up_existing_stacks_first() -> void:
	var reg := _registry_with({&"soil": 10})
	var inv := Inventory.new(4, reg)
	inv.add(&"soil", 6)
	# Adding 6 more should top up the existing partial stack before a new slot.
	inv.add(&"soil", 6)
	assert_eq(inv.slot(0), {"id": &"soil", "count": 10}, "Existing stack topped to cap")
	assert_eq(inv.slot(1), {"id": &"soil", "count": 2}, "Remainder in a fresh slot")


func test_add_zero_or_negative_is_noop() -> void:
	var inv := Inventory.new(4)
	assert_eq(inv.add(&"soil", 0), 0, "Adding 0 returns 0")
	assert_eq(inv.add(&"soil", -3), 0, "Adding negative returns 0")
	assert_true(inv.is_empty(), "No state change")


# ---------------------------------------------------------------------------
# Removing
# ---------------------------------------------------------------------------


func test_remove_partial() -> void:
	var inv := Inventory.new(4)
	inv.add(&"soil", 8)
	var removed := inv.remove(&"soil", 3)
	assert_eq(removed, 3, "Removed exactly requested")
	assert_eq(inv.count_of(&"soil"), 5, "Remaining count correct")


func test_remove_more_than_present_returns_actual() -> void:
	var inv := Inventory.new(4)
	inv.add(&"soil", 4)
	var removed := inv.remove(&"soil", 10)
	assert_eq(removed, 4, "Only 4 were available")
	assert_eq(inv.count_of(&"soil"), 0, "Item fully drained")
	assert_true(inv.is_empty(), "Drained slot is freed")


func test_remove_drains_across_slots_and_frees_them() -> void:
	var reg := _registry_with({&"soil": 5})
	var inv := Inventory.new(4, reg)
	inv.add(&"soil", 12)  # slots: 5, 5, 2
	var removed := inv.remove(&"soil", 7)
	assert_eq(removed, 7, "Removed across stacks")
	assert_eq(inv.count_of(&"soil"), 5, "5 remain")
	# Emptied slots must reopen for reuse.
	assert_eq(inv.slot(0), {}, "First slot emptied")


func test_remove_missing_item_is_noop() -> void:
	var inv := Inventory.new(4)
	assert_eq(inv.remove(&"nothing", 3), 0, "Removing absent item removes 0")


# ---------------------------------------------------------------------------
# Empty-slot reuse
# ---------------------------------------------------------------------------


func test_emptied_slot_is_reused() -> void:
	var inv := Inventory.new(2)
	inv.add(&"soil", 1)  # slot 0
	inv.add(&"glow_spore", 1)  # slot 1
	inv.remove(&"soil", 1)  # frees slot 0
	inv.add(&"lumen_petal", 1)  # should reuse slot 0
	assert_eq(inv.slot(0), {"id": &"lumen_petal", "count": 1}, "Freed slot reused")
	assert_eq(inv.slot(1), {"id": &"glow_spore", "count": 1}, "Other slot untouched")


# ---------------------------------------------------------------------------
# changed signal emission counts
# ---------------------------------------------------------------------------


func test_changed_emitted_once_per_successful_add() -> void:
	var inv := Inventory.new(4)
	var counter := _count_signal(inv)
	inv.add(&"soil", 3)
	assert_eq(counter[0], 1, "One emit per add that stored items")


func test_changed_not_emitted_on_noop_add() -> void:
	var inv := Inventory.new(0)  # zero slots: nothing can ever fit
	var counter := _count_signal(inv)
	var leftover := inv.add(&"soil", 5)
	assert_eq(leftover, 5, "Nothing fit")
	assert_eq(counter[0], 0, "No emit when nothing stored")


func test_changed_emitted_once_per_successful_remove() -> void:
	var inv := Inventory.new(4)
	inv.add(&"soil", 5)
	var counter := _count_signal(inv)
	inv.remove(&"soil", 2)
	assert_eq(counter[0], 1, "One emit per remove that changed state")


func test_changed_not_emitted_when_remove_removes_nothing() -> void:
	var inv := Inventory.new(4)
	inv.add(&"soil", 5)
	var counter := _count_signal(inv)
	inv.remove(&"glow_spore", 3)
	assert_eq(counter[0], 0, "No emit when nothing removed")
