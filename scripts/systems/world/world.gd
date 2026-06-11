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

## Combat tuning (Phase 4 contract #11).
## The player's starting / maximum health pool.
const PLAYER_MAX_HEALTH := 40.0
## Damage a single player melee strike deals to an Umbral.
const PLAYER_STRIKE_DAMAGE := 12.0
## Horizontal knockback impulse a strike imparts (along player forward).
const STRIKE_KNOCKBACK_FORWARD := 6.0
## Upward knockback impulse a strike imparts.
const STRIKE_KNOCKBACK_UP := 2.0
## Horizontal knockback an Umbral's contact attack shoves the player with.
const HURT_KNOCKBACK_FORCE := 5.0
## Despawn any Umbral farther than this (metres) from the player each round.
const UMBRAL_DESPAWN_DISTANCE := 60.0
## Seconds the death screen holds before the player respawns.
const RESPAWN_DELAY := 4.0

const _UMBRAL_SCENE := preload("res://scenes/creatures/umbral.tscn")

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

var _combat: CombatService
var _creatures: CreatureRegistry
var _spawner: SpawnSystem
var _umbrals: Node3D
var _player_health: Health
var _spawn_counter := 0
var _player_dead := false
var _spawn_point := Vector3.ZERO

var _poll_elapsed := 0.0
var _player_placed := false
var _flora_scattered := false


func _ready() -> void:
	_world_seed = WorldSeed.new(seed_value)
	_build_terrain()
	_build_environment()
	_build_items()
	_build_magic()
	_build_combat()
	_build_command_layer()
	_build_player()
	_build_flora()
	_install_ability_effects()
	_wire_combat()
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


## The combatant registry and damage router (Phase 4).
func combat() -> CombatService:
	return _combat


## The player's [Health] pool (owned by World, not the player controller).
func player_health() -> Health:
	return _player_health


## The creature definition catalog.
func creatures() -> CreatureRegistry:
	return _creatures


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


## Stand up the combat substrate (Phase 4 contract #11).
##
## The [CombatService] is the id→(health, node) router every hit passes through.
## The [CreatureRegistry] loads Umbral defs from disk and the [SpawnSystem] (pure
## logic, seeded off the "spawning" [WorldSeed] stream) decides when/where they
## condense. Spawned Umbrals live under a dedicated container so they stay out of
## the flora / bloom subtrees.
func _build_combat() -> void:
	_combat = CombatService.new()
	_creatures = CreatureRegistry.new()

	_umbrals = Node3D.new()
	_umbrals.name = "Umbrals"
	add_child(_umbrals)

	_spawner = SpawnSystem.new(_world_seed.derive("spawning"), _creatures.creatures())


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
	# Combat wiring: hits route through the bus into the CombatService.
	_context.combat = _combat
	_command_bus = CommandBus.new(_context)


func _build_player() -> void:
	_player = _PLAYER_SCENE.instantiate()
	add_child(_player)
	_player.dig_requested.connect(_on_dig_requested)
	_player.place_requested.connect(_on_place_requested)
	_player.harvest_requested.connect(_on_harvest_requested)
	_player.cast_requested.connect(_on_cast_requested)
	_player.strike_requested.connect(_on_strike_requested)


## Wire the player into the combat layer and drive Umbral spawning off the clock.
##
## The player's [Health] is owned here (the controller stays movement+intent
## only), registered with the [CombatService] under the player's instance id so
## an Umbral's [DamageCommand] can find it. The clock drives the deterministic
## spawn planner each tick; the player's death triggers the respawn sequence.
func _wire_combat() -> void:
	_player_health = Health.new(PLAYER_MAX_HEALTH)
	_combat.register(_player.get_instance_id(), _player_health, _player)
	_player_health.died.connect(_on_player_died)
	_clock.ticked.connect(_on_combat_tick)


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
	# Combat: health bar + hurt vignette read the player's Health pool.
	_hud.bind_health(_player_health)
	# Loot awards drive a transient pickup toast (presentation reads only).
	_loot.loot_awarded.connect(_on_loot_awarded)


func _on_loot_awarded(amounts: Array[ItemAmount]) -> void:
	_hud.show_loot(amounts, _registry)


# ---------------------------------------------------------------------------
# Deferred placement (terrain streams in asynchronously)
# ---------------------------------------------------------------------------


func _place_player(surface_y: float) -> void:
	_player_placed = true
	_spawn_point = Vector3(0.0, surface_y + PLAYER_SPAWN_CLEARANCE, 0.0)
	_player.global_position = _spawn_point
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
# Combat: player strike, Umbral spawning, and the respawn sequence
# ---------------------------------------------------------------------------


## Route a player melee strike into a [DamageCommand] with forward+up knockback.
func _on_strike_requested(target_id: int, _hit_point: Vector3) -> void:
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	if forward.length() > 0.0:
		forward = forward.normalized()
	var knockback := forward * STRIKE_KNOCKBACK_FORWARD + Vector3.UP * STRIKE_KNOCKBACK_UP
	_command_bus.execute(DamageCommand.new(target_id, PLAYER_STRIKE_DAMAGE, knockback))


## Drive deterministic Umbral spawning and far-despawn each simulation tick.
func _on_combat_tick(tick_index: int) -> void:
	if not _player_placed:
		return
	_despawn_distant_umbrals()
	var alive := _umbrals.get_child_count()
	var glow := _collect_glow_points()
	var height_fn := func(pos: Vector3) -> float:
		return _voxel_world.height_at(Vector2(pos.x, pos.z))
	var plans := _spawner.plan(tick_index, _player.global_position, alive, glow, height_fn)
	for plan in plans:
		_spawn_umbral(plan["def"], plan["position"])


## World positions that keep Umbrals away: live flora props and active blooms.
func _collect_glow_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if _flora != null:
		for child in _flora.get_children():
			if child is Node3D:
				points.append((child as Node3D).global_position)
	if _blooms != null:
		for child in _blooms.get_children():
			if child is Node3D:
				points.append((child as Node3D).global_position)
	return points


## Instantiate one Umbral, give it a per-creature RNG stream, and register it.
func _spawn_umbral(def: CreatureDef, position: Vector3) -> void:
	var umbral: Umbral = _UMBRAL_SCENE.instantiate()
	_umbrals.add_child(umbral)
	umbral.global_position = position
	var rng := _world_seed.derive("umbral:%d" % _spawn_counter)
	_spawn_counter += 1
	umbral.setup(def, _clock, rng, _player)
	_combat.register(umbral.get_instance_id(), umbral.health(), umbral)
	umbral.attack_landed.connect(_on_umbral_attack.bind(umbral))
	umbral.perished.connect(_on_umbral_perished.bind(umbral))


## An Umbral lands a contact hit: damage the player with knockback away from it.
func _on_umbral_attack(damage: float, umbral: Umbral) -> void:
	if not is_instance_valid(umbral):
		return
	var away := _player.global_position - umbral.global_position
	away.y = 0.0
	if away.length() > 0.0:
		away = away.normalized()
	var knockback := away * HURT_KNOCKBACK_FORCE + Vector3.UP * STRIKE_KNOCKBACK_UP
	_command_bus.execute(DamageCommand.new(_player.get_instance_id(), damage, knockback))


## An Umbral dissolved: award its drops + lumen and drop it from the registry.
## [param _at] is the death position (informational); drops route into the
## inventory rather than spawning world pickups in v1.
func _on_umbral_perished(def: CreatureDef, _at: Vector3, umbral: Umbral) -> void:
	if def != null:
		_loot.award_harvest_loot(def.drops)
		_well.add(def.lumen_reward)
	if is_instance_valid(umbral):
		_combat.unregister(umbral.get_instance_id())


## Free Umbrals that have wandered farther than the despawn radius from the
## player, unregistering them from the combat service first.
func _despawn_distant_umbrals() -> void:
	for child in _umbrals.get_children():
		if not (child is Umbral):
			continue
		var umbral := child as Umbral
		if _player.global_position.distance_to(umbral.global_position) > UMBRAL_DESPAWN_DISTANCE:
			_combat.unregister(umbral.get_instance_id())
			umbral.queue_free()


# ---------------------------------------------------------------------------
# Player death / respawn
# ---------------------------------------------------------------------------


## The player's Health hit zero: show the death screen, freeze input, and arm a
## timer that respawns them at the spawn point with full health.
func _on_player_died() -> void:
	if _player_dead:
		return
	_player_dead = true
	_hud.show_death(RESPAWN_DELAY)
	_player.set_physics_process(false)
	var timer := get_tree().create_timer(RESPAWN_DELAY)
	timer.timeout.connect(_respawn_player)


## Return the player to the spawn point at full health and resume control.
func _respawn_player() -> void:
	_player.global_position = _spawn_point
	_player.velocity = Vector3.ZERO
	_player_health.heal(_player_health.max_health())
	_player.set_physics_process(true)
	_player_dead = false
	_hud.hide_death()


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
