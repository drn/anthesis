extends GutTest

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _amount(id: StringName, count: int) -> ItemAmount:
	var a := ItemAmount.new()
	a.item_id = id
	a.count = count
	return a


## bloom_brick = 4 soil + 1 crystal_shard -> 2 bloom_brick.
func _bloom_recipe() -> Recipe:
	var r := Recipe.new()
	r.id = &"bloom_brick"
	r.display_name = "Bloom Brick"
	var inputs: Array[ItemAmount] = [_amount(&"soil", 4), _amount(&"crystal_shard", 1)]
	r.inputs = inputs
	r.output = _amount(&"bloom_brick", 2)
	return r


func _registry_with(stacks: Dictionary) -> ItemRegistry:
	var reg := ItemRegistry.new("res://__no_items__", "res://__no_recipes__")
	for id in stacks:
		var def := ItemDef.new()
		def.id = id
		def.display_name = String(id)
		def.max_stack = stacks[id]
		reg._items[id] = def
	return reg


# ---------------------------------------------------------------------------
# can_craft
# ---------------------------------------------------------------------------


func test_can_craft_true_when_inputs_present() -> void:
	var svc := CraftingService.new(ItemRegistry.new("res://__none__", "res://__none__"))
	var inv := Inventory.new(8)
	inv.add(&"soil", 4)
	inv.add(&"crystal_shard", 1)
	assert_true(svc.can_craft(inv, _bloom_recipe()), "Exact inputs => craftable")


func test_can_craft_false_on_missing_input() -> void:
	var svc := CraftingService.new(ItemRegistry.new("res://__none__", "res://__none__"))
	var inv := Inventory.new(8)
	inv.add(&"soil", 4)  # missing the crystal shard
	assert_false(svc.can_craft(inv, _bloom_recipe()), "Missing input => not craftable")


func test_can_craft_false_on_insufficient_quantity() -> void:
	var svc := CraftingService.new(ItemRegistry.new("res://__none__", "res://__none__"))
	var inv := Inventory.new(8)
	inv.add(&"soil", 3)  # need 4
	inv.add(&"crystal_shard", 1)
	assert_false(svc.can_craft(inv, _bloom_recipe()), "Too few inputs => not craftable")


func test_can_craft_false_on_null_recipe() -> void:
	var svc := CraftingService.new(ItemRegistry.new("res://__none__", "res://__none__"))
	assert_false(svc.can_craft(Inventory.new(8), null), "Null recipe => not craftable")


# ---------------------------------------------------------------------------
# craft consumes exactly + produces output
# ---------------------------------------------------------------------------


func test_craft_consumes_inputs_and_adds_output() -> void:
	var svc := CraftingService.new(ItemRegistry.new("res://__none__", "res://__none__"))
	var inv := Inventory.new(8)
	inv.add(&"soil", 6)  # extra soil should remain
	inv.add(&"crystal_shard", 1)
	var ok := svc.craft(inv, _bloom_recipe())
	assert_true(ok, "Craft should succeed")
	assert_eq(inv.count_of(&"soil"), 2, "Consumed exactly 4 soil")
	assert_eq(inv.count_of(&"crystal_shard"), 0, "Consumed the crystal shard")
	assert_eq(inv.count_of(&"bloom_brick"), 2, "Produced 2 bloom bricks")


func test_craft_fails_when_inputs_missing() -> void:
	var svc := CraftingService.new(ItemRegistry.new("res://__none__", "res://__none__"))
	var inv := Inventory.new(8)
	inv.add(&"soil", 4)
	var ok := svc.craft(inv, _bloom_recipe())
	assert_false(ok, "Cannot craft without all inputs")
	assert_eq(inv.count_of(&"soil"), 4, "Inputs untouched on failure")


# ---------------------------------------------------------------------------
# atomicity: output overflow into a FULL inventory => no consumption
# ---------------------------------------------------------------------------


func test_craft_atomic_fail_no_consume_on_output_overflow() -> void:
	# Inputs share single slots with unrelated full stacks, so consuming the
	# inputs frees NO slot. With every slot occupied and the inputs spread into
	# stacks that stay non-empty, there is nowhere for the 2 bloom_brick output
	# to land, so the craft must fail without consuming.
	var reg := _registry_with({&"soil": 8, &"crystal_shard": 4, &"bloom_brick": 2, &"filler": 99})
	var svc := CraftingService.new(reg)
	# 2 slots: soil+extra soil in slot 0 (so removing 4 leaves 4, slot stays
	# occupied), crystal+extra crystal in slot 1 (removing 1 leaves crystals).
	var inv := Inventory.new(2, reg)
	inv.add(&"soil", 8)  # slot 0, cap 8 — full, stays occupied after removing 4
	inv.add(&"crystal_shard", 4)  # slot 1, cap 4 — stays occupied after removing 1
	assert_true(svc.can_craft(inv, _bloom_recipe()), "Inputs are present")

	var ok := svc.craft(inv, _bloom_recipe())
	assert_false(ok, "Output cannot fit => craft fails")
	# Critical: inputs must be fully restored, output must not appear.
	assert_eq(inv.count_of(&"soil"), 8, "Soil restored after rollback")
	assert_eq(inv.count_of(&"crystal_shard"), 4, "Crystal shard restored after rollback")
	assert_eq(inv.count_of(&"bloom_brick"), 0, "No output created on failed craft")


func test_craft_partial_output_overflow_rolls_back_fully() -> void:
	# Room for only 1 of the 2 output bricks; the craft must fail and undo the
	# single brick it managed to place plus restore all inputs. The two input
	# slots both retain a surplus so consuming inputs frees no slot, and the one
	# free slot only caps at a single brick.
	var reg := _registry_with({&"soil": 8, &"crystal_shard": 4, &"bloom_brick": 1})
	var svc := CraftingService.new(reg)
	var inv := Inventory.new(3, reg)
	inv.add(&"soil", 8)  # slot 0 — full, stays occupied after removing 4
	inv.add(&"crystal_shard", 4)  # slot 1 — stays occupied after removing 1
	# slot 2 is free, but bloom_brick caps at 1 so only 1 of 2 can land.
	var ok := svc.craft(inv, _bloom_recipe())
	assert_false(ok, "Partial output fit => craft fails")
	assert_eq(inv.count_of(&"soil"), 8, "Soil fully restored")
	assert_eq(inv.count_of(&"crystal_shard"), 4, "Crystal shard fully restored")
	assert_eq(inv.count_of(&"bloom_brick"), 0, "Stray output brick rolled back")


# ---------------------------------------------------------------------------
# crafted signal
# ---------------------------------------------------------------------------


func test_crafted_signal_emitted_on_success() -> void:
	var svc := CraftingService.new(ItemRegistry.new("res://__none__", "res://__none__"))
	var recipe := _bloom_recipe()
	var inv := Inventory.new(8)
	inv.add(&"soil", 4)
	inv.add(&"crystal_shard", 1)
	watch_signals(svc)
	svc.craft(inv, recipe)
	assert_signal_emitted(svc, "crafted", "crafted must fire on success")
	assert_signal_emitted_with_parameters(svc, "crafted", [recipe], 0)


func test_crafted_signal_not_emitted_on_failure() -> void:
	var svc := CraftingService.new(ItemRegistry.new("res://__none__", "res://__none__"))
	var inv := Inventory.new(8)
	inv.add(&"soil", 4)  # missing crystal shard
	watch_signals(svc)
	svc.craft(inv, _bloom_recipe())
	assert_signal_not_emitted(svc, "crafted", "crafted must not fire on failure")
