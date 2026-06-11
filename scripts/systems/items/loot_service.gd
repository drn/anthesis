## Awards deterministic item drops for digging and harvesting.
##
## LootService turns world actions into inventory gains. Dig loot is fully
## deterministic: the quantity of soil scales with the dig radius, and a rare
## crystal shard is rolled from a [WorldSeed] stream that is re-seeded per dig
## from the quantized dig center. Re-running the same dig at the same location
## with the same world seed always yields the same award — a hard project rule.
##
## All randomness flows through the seeded "loot" stream; this service never
## calls [method @GlobalScope.randf] / [method @GlobalScope.randi] directly.
class_name LootService
extends RefCounted

## Emitted after any award with the [ItemAmount]s granted, so presentation
## (e.g. a HUD toast) can react without re-deriving the loot. Read-only for
## listeners; the service has already updated the inventory before emitting.
signal loot_awarded(amounts: Array[ItemAmount])

## Probability (0..1) that a dig also drops a single crystal shard.
const CRYSTAL_SHARD_CHANCE := 0.18
## Soil quantity bounds regardless of radius.
const SOIL_MIN := 1
const SOIL_MAX := 8

const SOIL_ID := &"soil"
const CRYSTAL_SHARD_ID := &"crystal_shard"

var _world_seed: WorldSeed
var _inv: Inventory


## Construct with the [param world_seed] for determinism and the target [param inv].
func _init(world_seed: WorldSeed, inv: Inventory) -> void:
	_world_seed = world_seed
	_inv = inv


## Award dig loot for a sphere of [param radius] centered at [param center].
##
## Returns the [ItemAmount]s awarded (for UI toasts). Soil count is
## [code]clampi(int(radius * 2.0), 1, 8)[/code]. A crystal shard is added with
## [constant CRYSTAL_SHARD_CHANCE] probability, rolled from a per-location
## deterministic stream so identical digs always match.
func award_dig_loot(center: Vector3, radius: float) -> Array[ItemAmount]:
	var awarded: Array[ItemAmount] = []

	var soil_count := clampi(int(radius * 2.0), SOIL_MIN, SOIL_MAX)
	_inv.add(SOIL_ID, soil_count)
	awarded.append(_make_amount(SOIL_ID, soil_count))

	var rng := _world_seed.derive(_dig_stream_name(center))
	if rng.randf() < CRYSTAL_SHARD_CHANCE:
		_inv.add(CRYSTAL_SHARD_ID, 1)
		awarded.append(_make_amount(CRYSTAL_SHARD_ID, 1))

	loot_awarded.emit(awarded)
	return awarded


## Add each drop in [param drops] to the inventory (harvest payout).
##
## Emits [signal loot_awarded] with the drops that were actually applied so
## presentation can toast the pickup.
func award_harvest_loot(drops: Array[ItemAmount]) -> void:
	var applied: Array[ItemAmount] = []
	for drop in drops:
		if drop == null or drop.item_id == &"" or drop.count <= 0:
			continue
		_inv.add(drop.item_id, drop.count)
		applied.append(drop)
	if not applied.is_empty():
		loot_awarded.emit(applied)


## Build the deterministic stream name for a dig at [param center].
##
## The center is quantized to whole units so jittery near-identical positions
## resolve to the same stream, keeping the crystal roll stable per cell.
func _dig_stream_name(center: Vector3) -> String:
	var qx := int(roundf(center.x))
	var qy := int(roundf(center.y))
	var qz := int(roundf(center.z))
	return "loot:%d,%d,%d" % [qx, qy, qz]


func _make_amount(item_id: StringName, count: int) -> ItemAmount:
	var amount := ItemAmount.new()
	amount.item_id = item_id
	amount.count = count
	return amount
