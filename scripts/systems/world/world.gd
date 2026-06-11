## Top-level composition for an Anthesis play session.
##
## World is the INTEGRATOR seam: it owns the single [WorldSeed] for the run,
## instantiates the terrain / environment / player subsystems, wires the
## command layer (so the player's dig/place intents flow through a
## [CommandBus] into the [TerrainEditService]), and scatters bioluminescent
## flora once the voxel terrain has streamed in.
##
## Subsystems stay decoupled: the player only emits signals, commands only
## touch services on the [WorldContext], and presentation reads state it never
## owns. World is the only place that knows about all of them at once.
class_name World
extends Node3D

## How high above the sampled surface the player spawns.
const PLAYER_SPAWN_CLEARANCE := 4.0

## A safe altitude to hold the player at while terrain streams in. Well above
## the terrain's maximum relief so they never spawn inside solid voxels.
const PLAYER_SAFE_ALTITUDE := 220.0

## Give up waiting for terrain after this many seconds and place anyway.
const TERRAIN_POLL_TIMEOUT := 20.0

## Flora tuning (contract #8 integration defaults).
const FLORA_COUNT := 150
const FLORA_AREA_EXTENT := 55.0

const _TERRAIN_SCENE := preload("res://scenes/world/terrain.tscn")
const _ENVIRONMENT_SCENE := preload("res://scenes/world/environment.tscn")
const _PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const _MUSHROOM_SCENE := preload("res://scenes/props/glow_mushroom.tscn")
const _FLOWER_SCENE := preload("res://scenes/props/glow_flower.tscn")
const _CRYSTAL_SCENE := preload("res://scenes/props/crystal.tscn")
const _HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const _LUMEN_BLOOM_SCENE := preload("res://scenes/props/lumen_bloom.tscn")

## Item/recipe data and inventory sizing (Phase 2).
const INVENTORY_SIZE := 24

## Magic tuning (Phase 3 contract #13).
const LUMEN_CAPACITY := 100.0
## Starting lumen — enough for one Skyward + one Bloom; gathering teaches the loop.
const STARTING_LUMEN := 30.0
## How far above the cast target a Lumen Bloom mote is planted.
const BLOOM_SPAWN_LIFT := 0.5

## The single deterministic seed for the whole world. Propagated into the
## terrain generator and every randomized subsystem so a given value always
## produces the same world.
@export var seed_value: int = 20260610

var _world_seed: WorldSeed
var _voxel_world: VoxelWorld
var _player: Player
var _flora: FloraScatter

var _context: WorldContext
var _terrain_edit: TerrainEditService
var _command_bus: CommandBus

var _registry: ItemRegistry
var _inventory: Inventory
var _crafting: CraftingService
var _loot: LootService
var _hud: Hud

var _clock: SimulationClock
var _well: LumenWell
var _ability_registry: AbilityRegistry
var _magic: MagicSystem
var _blooms: Node3D

var _poll_elapsed := 0.0
var _player_placed := false
var _flora_scattered := false


func _ready() -> void:
	_world_seed = WorldSeed.new(seed_value)
	_build_terrain()
	_build_environment()
	_build_items()
	_build_magic()
	_build_command_layer()
	_build_player()
	_build_flora()
	_install_ability_effects()
	_build_hud()
	# Park the player up high until terrain streams in, then drop them onto it.
	_player.global_position = Vector3(0.0, PLAYER_SAFE_ALTITUDE, 0.0)


func _process(delta: float) -> void:
	if _player_placed and _flora_scattered:
		set_process(false)
		return
	_poll_elapsed += delta
	var surface_y := _voxel_world.height_at(Vector2.ZERO)
	var terrain_ready := not is_nan(surface_y)
	var timed_out := _poll_elapsed >= TERRAIN_POLL_TIMEOUT

	if not _player_placed and (terrain_ready or timed_out):
		_place_player(surface_y if terrain_ready else 0.0)
	if not _flora_scattered and (terrain_ready or timed_out):
		_scatter_flora()


# ---------------------------------------------------------------------------
# Introspection (used by the integration test)
# ---------------------------------------------------------------------------


## The command bus that routes player intents into terrain edits.
func command_bus() -> CommandBus:
	return _command_bus


## The voxel terrain subsystem.
func voxel_world() -> VoxelWorld:
	return _voxel_world


## The player controller.
func player() -> Player:
	return _player


## The flora scatter node.
func flora() -> FloraScatter:
	return _flora


## The player's inventory.
func inventory() -> Inventory:
	return _inventory


## The item/recipe registry.
func registry() -> ItemRegistry:
	return _registry


## The heads-up display.
func hud() -> Hud:
	return _hud


## The fixed-timestep simulation clock driving magic cooldowns.
func clock() -> SimulationClock:
	return _clock


## The player's Lumen well.
func lumen_well() -> LumenWell:
	return _well


## The magic rule gate.
func magic() -> MagicSystem:
	return _magic


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------


func _build_terrain() -> void:
	_voxel_world = _TERRAIN_SCENE.instantiate()
	# Seed must be set before the node enters the tree so _ready() builds the
	# generator deterministically.
	_voxel_world.seed_value = seed_value
	add_child(_voxel_world)


func _build_environment() -> void:
	var env := _ENVIRONMENT_SCENE.instantiate()
	add_child(env)


func _build_items() -> void:
	_registry = ItemRegistry.new()
	_inventory = Inventory.new(INVENTORY_SIZE, _registry)
	_crafting = CraftingService.new(_registry)
	_loot = LootService.new(_world_seed, _inventory)


## Stand up the tick substrate and magic rule gate (Phase 3 contract #13).
##
## The [SimulationClock] is a real scene-tree child so it ticks in _process; the
## [MagicSystem] reads its current tick through a Callable, keeping cooldowns
## deterministic and decoupled from wall-clock time. Ability data is loaded from
## resources via [AbilityRegistry]. The well starts partially charged so the
## player can cast once before they must gather more from flora.
func _build_magic() -> void:
	_clock = SimulationClock.new()
	_clock.name = "SimulationClock"
	add_child(_clock)

	_well = LumenWell.new(LUMEN_CAPACITY)
	_ability_registry = AbilityRegistry.new()
	_magic = MagicSystem.new(_well, func() -> int: return _clock.current_tick())

	# A container for spawned Lumen Bloom motes, kept out of the flora subtree.
	_blooms = Node3D.new()
	_blooms.name = "Blooms"
	add_child(_blooms)

	# Seed the starting charge after wiring so the HUD picks it up on bind.
	_well.add(STARTING_LUMEN)


func _build_command_layer() -> void:
	_terrain_edit = TerrainEditService.new(func() -> VoxelTool: return _voxel_world.voxel_tool())
	_context = WorldContext.new()
	_context.terrain_edit = _terrain_edit
	_context.registry = _registry
	_context.inventory = _inventory
	_context.crafting = _crafting
	_context.loot = _loot
	# Free a harvested prop only when it is genuinely a flora prop in our tree.
	_context.flora_harvest = _free_harvested_prop
	# Magic wiring: the rule gate plus the gather hook that credits the well.
	_context.magic = _magic
	_context.lumen_gain = func(amount: float) -> void: _well.add(amount)
	_command_bus = CommandBus.new(_context)


func _build_player() -> void:
	_player = _PLAYER_SCENE.instantiate()
	add_child(_player)
	_player.dig_requested.connect(_on_dig_requested)
	_player.place_requested.connect(_on_place_requested)
	_player.harvest_requested.connect(_on_harvest_requested)
	_player.cast_requested.connect(_on_cast_requested)


func _build_flora() -> void:
	_flora = FloraScatter.new()
	_flora.name = "FloraScatter"
	_flora.prop_scenes = [_MUSHROOM_SCENE, _FLOWER_SCENE, _CRYSTAL_SCENE]
	_flora.count = FLORA_COUNT
	_flora.area_extent = FLORA_AREA_EXTENT
	add_child(_flora)


func _build_hud() -> void:
	_hud = _HUD_SCENE.instantiate()
	add_child(_hud)
	# Crafting routes back through the command bus — the HUD never mutates state.
	_hud.bind(_inventory, _registry, _crafting, _on_craft_requested)
	# Magic: lumen bar + ability slots read the well / rule gate (no mutation).
	_hud.bind_magic(_well, _magic, _ability_registry.abilities())
	# Loot awards drive a transient pickup toast (presentation reads only).
	_loot.loot_awarded.connect(_on_loot_awarded)


func _on_loot_awarded(amounts: Array[ItemAmount]) -> void:
	_hud.show_loot(amounts, _registry)


# ---------------------------------------------------------------------------
# Deferred placement (terrain streams in asynchronously)
# ---------------------------------------------------------------------------


func _place_player(surface_y: float) -> void:
	_player_placed = true
	_player.global_position = Vector3(0.0, surface_y + PLAYER_SPAWN_CLEARANCE, 0.0)
	_player.velocity = Vector3.ZERO


func _scatter_flora() -> void:
	_flora_scattered = true
	_flora.scatter(_world_seed, func(xz: Vector2) -> float: return _voxel_world.height_at(xz))


# ---------------------------------------------------------------------------
# Player intent -> command layer
# ---------------------------------------------------------------------------


func _on_dig_requested(world_pos: Vector3, radius: float) -> void:
	_command_bus.execute(DigCommand.new(world_pos, radius))


func _on_place_requested(world_pos: Vector3, radius: float) -> void:
	_command_bus.execute(PlaceCommand.new(world_pos, radius))


func _on_harvest_requested(target: Node, drops: Array[ItemAmount]) -> void:
	_command_bus.execute(HarvestCommand.new(target, drops))


## Map a 1-indexed ability slot to its [AbilityDef] and cast it through the bus.
##
## The slot order mirrors [method AbilityRegistry.abilities] (sorted by id), so
## hotkeys 1/2/3 stay stable. Out-of-range slots are ignored. The cast routes
## through a [CastCommand] so cost/cooldown enforcement and effects all happen
## inside the rule gate, never here.
func _on_cast_requested(slot: int, target_pos: Vector3) -> void:
	var abilities := _ability_registry.abilities()
	var index := slot - 1
	if index < 0 or index >= abilities.size():
		return
	_command_bus.execute(CastCommand.new(abilities[index], target_pos))


func _on_craft_requested(recipe: Recipe) -> void:
	_command_bus.execute(CraftCommand.new(recipe))


# ---------------------------------------------------------------------------
# Ability effects (installed into the WorldContext; each returns success)
# ---------------------------------------------------------------------------


## Register the realized effect for each ability kind on the [WorldContext].
##
## Each effect is Callable(ability, target) -> bool and is invoked by [MagicSystem]
## only after cooldown + cost pass; returning true is what actually spends lumen
## and arms the cooldown. Effects are installed after the player exists so
## Skyward can read the player's velocity.
func _install_ability_effects() -> void:
	_context.ability_effects = {
		&"shape_burst": _effect_shape_burst,
		&"lumen_bloom": _effect_lumen_bloom,
		&"skyward": _effect_skyward,
	}


## Worldshaper Burst — carve a sphere of terrain at the target.
func _effect_shape_burst(ability: AbilityDef, target: Vector3) -> bool:
	_terrain_edit.dig_sphere(target, ability.magnitude)
	return true


## Lumen Bloom — plant a configured mote of living light just above the target.
func _effect_lumen_bloom(ability: AbilityDef, target: Vector3) -> bool:
	var mote := _LUMEN_BLOOM_SCENE.instantiate()
	_blooms.add_child(mote)
	mote.global_position = target + Vector3.UP * BLOOM_SPAWN_LIFT
	if mote.has_method("configure"):
		mote.configure(ability.magnitude)
	return true


## Skyward Step — the world exhales: impart an upward impulse on the player.
func _effect_skyward(ability: AbilityDef, _target: Vector3) -> bool:
	if _player == null:
		return false
	_player.velocity.y = maxf(_player.velocity.y, ability.magnitude)
	return true


## Safely free a harvested prop. Only frees nodes that are actually descendants
## of the FloraScatter subtree, so a stray HarvestCommand can never free
## arbitrary scene nodes.
func _free_harvested_prop(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		return
	if _flora != null and _flora.is_ancestor_of(target):
		target.queue_free()
