# Crafting, Items, and Loot

The Anthesis item system is fully data-driven: every item type and recipe is a
Godot `.tres` resource on disk. `ItemRegistry` loads them at boot. `Inventory`
holds the player's stock. `CraftingService` runs the atomic consume-produce
transaction. `LootService` awards deterministic item drops for digging and
harvesting.

---

## Key Files

| File | Role |
|------|------|
| `scripts/core/items/item_def.gd` | Item type definition (`Resource`) |
| `scripts/core/items/item_amount.gd` | `{item_id, count}` pair used in recipes + loot |
| `scripts/core/items/recipe.gd` | Recipe definition (`inputs[]`, `output`) |
| `scripts/systems/items/item_registry.gd` | Disk scan + id-keyed catalog |
| `scripts/systems/inventory/inventory.gd` | Fixed-slot, stack-aware container |
| `scripts/systems/crafting/crafting_service.gd` | Atomic craft transaction |
| `scripts/systems/items/loot_service.gd` | Deterministic dig + harvest drops |
| `resources/items/` | `.tres` ItemDef files |
| `resources/recipes/` | `.tres` Recipe files |
| `tests/unit/test_inventory.gd` | Stacking, overflow, slot mechanics |
| `tests/unit/test_crafting_service.gd` | Atomicity, rollback, signal tests |
| `tests/unit/test_loot_service.gd` | Determinism, crystal-roll tests |
| `tests/unit/test_item_registry.gd` | Registry scan tests |
| `tests/unit/test_item_resources.gd` | `.tres` load / field validation |
| `scripts/ui/inventory_panel.gd` | Inventory grid + recipe UI (binds `Inventory.changed`; crafts only via the `on_craft` Callable -> `CraftCommand`) |

---

## Data Types

### ItemDef

```gdscript
class_name ItemDef
extends Resource

@export var id: StringName          # primary key, e.g. &"soil"
@export var display_name: String
@export var max_stack: int = 99     # per-slot ceiling in Inventory
@export var category: StringName = &"material"   # "material", "tool", "placeable"
@export var swatch_color: Color = Color.WHITE
@export_multiline var description: String
```

### ItemAmount

```gdscript
class_name ItemAmount
extends Resource

@export var item_id: StringName   # must match an ItemDef.id
@export var count: int = 1
```

Used in recipe `inputs` arrays, recipe `output`, loot tables (`Harvestable.drops`),
and `LootService` return values.

### Recipe

```gdscript
class_name Recipe
extends Resource

@export var id: StringName
@export var display_name: String
@export var inputs: Array[ItemAmount] = []
@export var output: ItemAmount
```

---

## ItemRegistry

Scans `res://resources/items/` and `res://resources/recipes/` at construction.
Both directories are optional (missing → empty catalog, no error).

```gdscript
func _init(items_dir := "res://resources/items", recipes_dir := "res://resources/recipes")
func item(id: StringName) -> ItemDef       # null if not found
func recipe(id: StringName) -> Recipe      # null if not found
func recipes() -> Array[Recipe]            # discovery order
func item_ids() -> Array[StringName]       # discovery order
```

Handles `.tres.remap` suffixes for exported builds (strips `.remap` to recover
the logical path). Items and recipes with an empty `id` are silently skipped.

---

## Inventory

`Inventory` (`extends RefCounted`) holds a fixed number of parallel-array slots.
Each slot is either empty (`_ids[i] == &""`) or holds one item id with a count.

```gdscript
signal changed   # fires once per mutating call

func _init(size := 24, registry: ItemRegistry = null)
func add(item_id: StringName, count: int) -> int   # returns overflow
func remove(item_id: StringName, count: int) -> int  # returns amount removed
func count_of(item_id: StringName) -> int
func slot(i: int) -> Dictionary    # {} when empty, {id, count} when occupied
func size() -> int
func is_empty() -> bool
```

### Stacking Semantics

`add` runs two passes:
1. Top up existing matching stacks (up to the item's `max_stack`).
2. Fill empty slots (up to `max_stack` each).

Returns the overflow — the amount that did not fit. Non-positive count or empty id
is a no-op returning 0.

`remove` drains across all matching stacks in slot order, empties slots that hit
zero, and returns the actual amount removed (may be less than requested).

`_max_stack_for(item_id)` consults the registry if available; falls back to
`DEFAULT_MAX_STACK = 99` when the registry is null or the item is unknown.

`changed` fires exactly once per call that altered state — UI can bind cheaply.

---

## CraftingService

`CraftingService` (`extends RefCounted`) is stateless logic. The registry is
injected for stack-size lookups during the output-fit check.

```gdscript
signal crafted(recipe: Recipe)

func _init(registry: ItemRegistry)
func can_craft(inv: Inventory, recipe: Recipe) -> bool
func craft(inv: Inventory, recipe: Recipe) -> bool
```

### Atomicity

`craft` is atomic:

1. `can_craft` — checks every input is present (count check, not fit check).
2. If `recipe.output` is missing/empty, return false.
3. Remove all inputs from `inv`.
4. `inv.add(output.item_id, output.count)` — if leftover > 0 (output doesn't fit),
   call `_rollback`: pull back any stored output, restore all inputs, return false.
5. On full success, emit `crafted(recipe)`, return true.

**A failed craft never consumes inputs.** The rollback path (`_rollback`) reverses
both the partial output store and all consumed inputs.

`crafted` emits only on success.

---

## LootService

`LootService` (`extends RefCounted`) awards items to an `Inventory` and emits
`loot_awarded` so the HUD can toast the pickup.

```gdscript
signal loot_awarded(amounts: Array[ItemAmount])

func _init(world_seed: WorldSeed, inv: Inventory)
func award_dig_loot(center: Vector3, radius: float) -> Array[ItemAmount]
func award_harvest_loot(drops: Array[ItemAmount]) -> void
```

### Dig Loot Determinism

Soil count: `clampi(int(radius * 2.0), 1, 8)` — always 1..8.

Crystal shard: rolled with probability `CRYSTAL_SHARD_CHANCE = 0.18` from a
per-cell stream. The stream name is:

```gdscript
"loot:%d,%d,%d" % [int(roundf(center.x)), int(roundf(center.y)), int(roundf(center.z))]
```

The center is **quantized to whole units** so jittery near-identical positions
resolve to the same stream. Re-running the same dig at the same location with the
same world seed always yields the same awards.

`_world_seed.derive(stream_name).randf()` is the only RNG call. No bare `randf()`
or `randi()`.

### Harvest Loot

Passes each `ItemAmount` in `drops` directly to `inv.add`. Drops with empty id or
count ≤ 0 are skipped. Emits `loot_awarded` with the applied amounts.

---

## Adding Items and Recipes

### New ItemDef

Create `resources/items/<id>.tres`:

```
[gd_resource type="Resource" script_class="ItemDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/core/items/item_def.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"my_item"
display_name = "My Item"
max_stack = 20
category = &"material"
swatch_color = Color(0.5, 0.8, 0.2, 1)
description = "A short flavor line."
```

`ItemRegistry` discovers it on next boot. No code changes needed.

### New Recipe

Create `resources/recipes/<id>.tres`. The typed-array syntax for `inputs` is
mandatory — Godot's `.tres` serializer requires it for `Array[ItemAmount]`:

```
[gd_resource type="Resource" script_class="Recipe" load_steps=6 format=3]

[ext_resource type="Script" path="res://scripts/core/items/recipe.gd" id="1"]
[ext_resource type="Script" path="res://scripts/core/items/item_amount.gd" id="2"]

[sub_resource type="Resource" id="input_1"]
script = ExtResource("2")
item_id = &"my_item"
count = 3

[sub_resource type="Resource" id="output_1"]
script = ExtResource("2")
item_id = &"finished_item"
count = 1

[resource]
script = ExtResource("1")
id = &"finished_item"
display_name = "Finished Item"
inputs = Array[ExtResource("2")]([SubResource("input_1")])
output = SubResource("output_1")
```

Key serialization note: `inputs` must use the typed-array syntax
`Array[ExtResource("2")]([...])` or Godot will deserialize it as `Array` (untyped),
which causes a type mismatch at runtime. See `resources/recipes/bloom_brick.tres`
for the canonical example.

### Adding a Loot Drop to a Flora Prop

Open the prop scene, select the `Harvestable` child node, and set `drops` in the
Inspector. Alternatively edit the prop's `.tscn` directly and add an `ItemAmount`
sub-resource to the `drops` array. The `lumen` field on `Harvestable` sets the
well credit for that prop.

---

## Testing Notes

`tests/unit/test_crafting_service.gd` is the canonical reference. Key patterns:

- `_registry_with({&"item_id": max_stack})` builds a minimal registry with custom
  stack caps for overflow/rollback tests — copy this helper for any test that needs
  controlled stacking.
- Atomicity tests construct a 2- or 3-slot inventory intentionally sized so the
  output cannot fit after inputs are consumed, then assert that both inputs and
  output are fully restored.

`tests/unit/test_loot_service.gd` exercises the crystal-roll determinism: the same
center + world seed always produces the same result across repeated calls.

`tests/unit/test_item_resources.gd` loads every `.tres` from `resources/items/` and
asserts that `id` is non-empty and `max_stack > 0`. Copy this pattern for any new
resource category.

---

## Gotchas

- `CraftingService.craft` removes inputs before checking output fit. The rollback
  path restores them, but only if your item ids are stable. A mistyped id in a
  recipe `.tres` will silently fail to remove or restore.
- `Inventory.add` returns overflow — **check the return value** if it matters to
  your use-case. `LootService` ignores overflow intentionally (excess loot is lost).
- `ItemRegistry` preserves **discovery order** (filesystem scan order) for
  `recipes()` and `item_ids()`. Do not rely on alphabetical order unless you sort
  explicitly.
- The typed-array syntax in `.tres` `inputs` is not optional — omitting it causes
  a silent type downgrade to `Array` and breaks `CraftingService.can_craft` input
  iteration.
- `CraftingService` never touches world/voxel state — crafting mutations stay in
  the command layer (`CraftCommand`), which delegates here.
