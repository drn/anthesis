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
const _SESSION_PANEL_SCENE := preload("res://scenes/ui/session_panel.tscn")
const _PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")

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

## Ferromancy (Phase 8). Metal deposit props scattered with the flora, plus the
## throwable ferric coin spawned by the coin-toss command.
const _DEPOSIT_LODESTONE_SCENE := preload("res://scenes/props/metal_deposit_lodestone.tscn")
const _DEPOSIT_SKYSTEEL_SCENE := preload("res://scenes/props/metal_deposit_skysteel.tscn")
const _DEPOSIT_VIGORITE_SCENE := preload("res://scenes/props/metal_deposit_vigorite.tscn")
const _DEPOSIT_KEENGLASS_SCENE := preload("res://scenes/props/metal_deposit_keenglass.tscn")
const _FERRIC_COIN_SCENE := preload("res://scenes/props/ferric_coin.tscn")

## Maps each burnable metal kind to the inventory flake item that charges it.
const FLAKE_MAP := {
	&"iron": &"iron_flakes",
	&"steel": &"steel_flakes",
	&"pewter": &"pewter_flakes",
	&"tin": &"tin_flakes",
}

## Strike-damage multiplier while the player burns Vigor (the boon side of the
## pewter trade; the channel boons themselves live in [FerromancyRig]).
const VIGOR_STRIKE_MULT := 1.5
## A coin landing faster than this (m/s) deals strike damage to a struck Umbral.
const COIN_STRIKE_SPEED := 6.0
## Damage a fast-moving thrown coin deals on impact.
const COIN_STRIKE_DAMAGE := 8.0

## Sequencer (Phase 6 contract #10).
## A Note Block joins the nearest Sequencer Core within this many metres.
const SEQUENCER_CORE_RANGE := 10.0
## Name of the music stem player whose transport the Sequencer Cores lock to.
const TRANSPORT_STEM_PLAYER := "Stem_pad"

## Adaptive music tuning (Phase 5 contract #6).
## An Umbral within this many metres of the player feeds the &"enemy_near"
## intensity event each tick, lifting the soundtrack as danger closes in.
const ENEMY_NEAR_DISTANCE := 12.0

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

## Ferromancy (Phase 8): per-metal reserves, the sustained-burn channel manager,
## the status-effect tracker, the throwable-coin container, and the blue-line
## metal-sense overlay.
var _metal_reserves: MetalReserves
var _channels: ChannelSystem
var _status: StatusEffectSystem
var _coins: Node3D
var _metal_overlay: MetalLineOverlay
## Realized ferromancy behaviour (channel boons + Ferropull/push), kept out of
## this hub. Constructed in [method _build_magic], collaborators bound after the
## combat service exists.
var _ferro_rig: FerromancyRig

var _combat: CombatService
var _creatures: CreatureRegistry
var _spawner: SpawnSystem
var _umbrals: Node3D
var _player_health: Health
var _spawn_counter := 0
var _player_dead := false
var _spawn_point := Vector3.ZERO

var _intensity: IntensityModel
var _stem_registry: MusicStemRegistry
var _music: MusicSystem

var _blocks: Node3D
var _block_place: BlockPlacementService

## Networking (Phase 7 contract #9). Default OFFLINE: nothing networks until the
## SessionPanel drives host()/join(). The router is the single seam every
## player-intent command flows through.
var _session: NetworkSession
var _router: CommandRouter
var _command_log: CommandLog
var _player_sync: PlayerSync
var _remote_players: Node3D
var _session_panel: SessionPanel

## Pause menu + persisted settings (Escape).
var _settings: GameSettings
var _settings_applier: SettingsApplier
var _pause_menu: PauseMenu

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
	_build_music()
	_build_sequencer()
	_build_net()
	_build_pause_menu()
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


## The adaptive stem mixer (Phase 5).
func music() -> MusicSystem:
	return _music


## The game-intensity signal driving the soundtrack (Phase 5).
func intensity() -> IntensityModel:
	return _intensity


## The container holding placed sequencer blocks (Phase 6).
func blocks_container() -> Node3D:
	return _blocks


## The sequencer block placement/removal service (Phase 6).
func block_place() -> BlockPlacementService:
	return _block_place


## The multiplayer session (Phase 7). OFFLINE until host()/join() is driven.
func session() -> NetworkSession:
	return _session


## The authority-aware command router every player intent flows through (Phase 7).
func router() -> CommandRouter:
	return _router


## The bounded host-side command log used for late-join replay (Phase 7).
func command_log() -> CommandLog:
	return _command_log


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

	# Ferromancy (Phase 8): one well per metal, a per-tick status tracker, and the
	# channel manager that drives sustained burns. The magic gate resolves each
	# ability to its well by resource_kind — &"lumen" → the Lumen well, a metal
	# kind → that metal's reserve — so a single MagicSystem gates every cast.
	_metal_reserves = MetalReserves.new(FLAKE_MAP)

	_status = StatusEffectSystem.new()
	_status.name = "StatusEffects"
	add_child(_status)

	_channels = ChannelSystem.new()
	_channels.name = "Channels"
	add_child(_channels)
	_channels.setup(_metal_reserves, _inventory)

	var well_resolver := func(kind: StringName) -> LumenWell:
		if kind == &"lumen":
			return _well
		return _metal_reserves.well(kind)
	_magic = MagicSystem.new(well_resolver, func() -> int: return _clock.current_tick())

	# Drive both per-tick subsystems off the deterministic clock. Stored on
	# scene-tree Nodes so the tick Callables can never be GC'd.
	_clock.ticked.connect(_status.on_tick)
	_clock.ticked.connect(_channels.on_tick)

	# The rig owns the realized channel boons; collaborators (combat) are bound
	# later in _install_ability_effects once the combat service exists.
	_ferro_rig = FerromancyRig.new()
	_ferro_rig.install_channels(_channels)

	# A container for spawned Lumen Bloom motes, kept out of the flora subtree.
	_blooms = Node3D.new()
	_blooms.name = "Blooms"
	add_child(_blooms)

	# A container for thrown ferric coins (live, local-only physics entities).
	_coins = Node3D.new()
	_coins.name = "Coins"
	add_child(_coins)

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
	# Ferromancy wiring (Phase 8): status tracker, channel manager, metal reserves,
	# and the coin-spawn seam the ThrowCoinCommand calls after consuming a coin.
	_context.status = _status
	_context.channels = _channels
	_context.metal_reserves = _metal_reserves
	_context.coin_spawn = _spawn_coin
	_command_bus = CommandBus.new(_context)


func _build_player() -> void:
	_player = _PLAYER_SCENE.instantiate()
	add_child(_player)
	_player.dig_requested.connect(_on_dig_requested)
	_player.place_requested.connect(_on_place_requested)
	_player.harvest_requested.connect(_on_harvest_requested)
	_player.cast_requested.connect(_on_cast_requested)
	_player.strike_requested.connect(_on_strike_requested)
	_player.place_block_requested.connect(_on_place_block_requested)
	_player.block_interact_requested.connect(_on_block_interact_requested)
	_player.block_remove_requested.connect(_on_block_remove_requested)
	# Ferromancy intents (Phase 8): channel toggles, flare, coin toss.
	_player.channel_toggle_requested.connect(_on_channel_toggle_requested)
	_player.flare_changed.connect(_on_flare_changed)
	_player.throw_coin_requested.connect(_on_throw_coin_requested)


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
	_flora.prop_scenes = [
		_MUSHROOM_SCENE,
		_FLOWER_SCENE,
		_CRYSTAL_SCENE,
		_DEPOSIT_LODESTONE_SCENE,
		_DEPOSIT_SKYSTEEL_SCENE,
		_DEPOSIT_VIGORITE_SCENE,
		_DEPOSIT_KEENGLASS_SCENE,
	]
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
	# Ferromancy: metal-reserve gauges read the reserves + channel state.
	_hud.bind_metals(_metal_reserves, _channels)
	# Loot awards drive a transient pickup toast (presentation reads only).
	_loot.loot_awarded.connect(_on_loot_awarded)

	# Blue-line metal-sense overlay: a 3D child fed read-only providers for the
	# player's camera and the live metal-source group (Phase 8).
	_metal_overlay = MetalLineOverlay.new()
	_metal_overlay.name = "MetalLineOverlay"
	add_child(_metal_overlay)
	_metal_overlay.setup(
		func() -> Camera3D:
			return _player.get_node_or_null("Camera3D") if _player != null else null,
		func() -> Array: return get_tree().get_nodes_in_group(&"metal_sources"),
		_metal_reserves,
	)


func _on_loot_awarded(amounts: Array[ItemAmount]) -> void:
	_hud.show_loot(amounts, _registry)


# ---------------------------------------------------------------------------
# Adaptive music (Phase 5 contract #6)
# ---------------------------------------------------------------------------


## Stand up the adaptive soundtrack and wire it to the gameplay event streams.
##
## A single [IntensityModel] is the soundtrack's "how intense is the moment"
## signal; the [MusicSystem] reads it to crossfade phase-locked stems loaded via
## the [MusicStemRegistry]. The model is fed from three sources, all read-only:
## the [CommandBus] (dig/cast/harvest intents), the [CombatService.damage_applied]
## signal (player-hurt vs. enemy hit), and a per-tick proximity check for nearby
## Umbrals. The clock drives both the model's decay and the volume slew inside
## [MusicSystem].
func _build_music() -> void:
	_intensity = IntensityModel.new()
	_stem_registry = MusicStemRegistry.new()
	_music = MusicSystem.new()
	_music.name = "MusicSystem"
	add_child(_music)
	_music.setup(_stem_registry.stems(), _intensity, _clock)

	# Event sources feed heat into the intensity model (presentation reads only).
	_command_bus.command_executed.connect(_on_command_executed)
	_combat.damage_applied.connect(_on_damage_for_music)
	_clock.ticked.connect(_on_music_tick)


## Map an executed command to its intensity event kind. Only the player-driven
## intents that should colour the soundtrack are mapped; everything else (place,
## craft, damage) is silent here — damage is handled via [CombatService].
func _on_command_executed(cmd: WorldCommand) -> void:
	if cmd is DigCommand:
		_intensity.on_event(&"dig")
	elif cmd is CastCommand:
		_intensity.on_event(&"cast")
	elif cmd is HarvestCommand:
		_intensity.on_event(&"harvest")


## Route applied damage into the intensity model: a hit on the player is the
## tense &"player_hurt", anything else is a &"combat_hit" the player landed.
func _on_damage_for_music(target_id: int, _amount: float) -> void:
	if target_id == _player.get_instance_id():
		_intensity.on_event(&"player_hurt")
	else:
		_intensity.on_event(&"combat_hit")


## Each simulation tick, raise intensity once if any Umbral is closing in. The
## [MusicSystem] connects to the same [signal SimulationClock.ticked] to decay
## the model and slew volumes; this handler only adds proximity heat.
func _on_music_tick(_tick_index: int) -> void:
	if not _player_placed or _umbrals == null:
		return
	var player_pos := _player.global_position
	for child in _umbrals.get_children():
		if not (child is Umbral):
			continue
		if player_pos.distance_to((child as Umbral).global_position) <= ENEMY_NEAR_DISTANCE:
			_intensity.on_event(&"enemy_near")
			return


# ---------------------------------------------------------------------------
# In-world music sequencer (Phase 6 — the signature feature)
# ---------------------------------------------------------------------------


## Stand up the in-world sequencer: a Blocks container plus the
## [BlockPlacementService] that spawns/removes Sequencer Cores and Note Blocks.
##
## The service is inventory-gated (it charges/refunds the same [Inventory] the
## rest of the game uses) and is handed two seams: a container provider (the
## Blocks node) and a core_lookup that returns the nearest [SequencerCore] within
## [constant SEQUENCER_CORE_RANGE] of a position. Cores lock their [StepTimeline]
## to the live music transport via [method _transport_position] so player
## compositions ride the same 110 BPM grid as the soundtrack. The service is
## published on the [WorldContext] so the block commands can reach it.
func _build_sequencer() -> void:
	_blocks = Node3D.new()
	_blocks.name = "Blocks"
	add_child(_blocks)

	_block_place = BlockPlacementService.new(
		_inventory,
		func() -> Node3D: return _blocks,
		_nearest_core,
	)
	_block_place.block_placed.connect(_on_block_placed)
	_context.block_place = _block_place


## Find the nearest placed [SequencerCore] within range of [param pos], or null.
func _nearest_core(pos: Vector3) -> SequencerCore:
	if _blocks == null:
		return null
	var best: SequencerCore = null
	var best_dist := SEQUENCER_CORE_RANGE
	for child in _blocks.get_children():
		if not (child is SequencerCore):
			continue
		var core := child as SequencerCore
		var dist := core.global_position.distance_to(pos)
		if dist <= best_dist:
			best_dist = dist
			best = core
	return best


## Read the live music transport position (seconds) from the pad stem player so
## cores lock to the soundtrack. Returns 0.0 until the player exists / is found.
func _transport_position() -> float:
	if _music == null:
		return 0.0
	for player in _music.players():
		if player.name == TRANSPORT_STEM_PLAYER:
			return player.get_playback_position()
	# Fall back to the first stem if the pad is renamed.
	var all := _music.players()
	if not all.is_empty():
		return all[0].get_playback_position()
	return 0.0


## A block was placed: a freshly spawned Sequencer Core must be locked to the
## music transport, and the player gets a one-line hint about block controls.
func _on_block_placed(item_id: StringName, _position: Vector3) -> void:
	if item_id == &"sequencer_core":
		_lock_new_cores_to_transport()
	if _hud != null and _hud.has_method("show_hint"):
		_hud.show_hint("N: place Core   B: place Note Block   E: retune   F: remove")


## Bind the transport Callable into any Sequencer Core that has not yet been set
## up. Called after a core is placed (the placement service spawns it before this
## handler runs, so its setup is deferred to here).
func _lock_new_cores_to_transport() -> void:
	if _blocks == null:
		return
	for child in _blocks.get_children():
		if child is SequencerCore:
			(child as SequencerCore).setup(_transport_position)


# ---------------------------------------------------------------------------
# Networking (Phase 7 contract #9 — host-authority co-op)
# ---------------------------------------------------------------------------


## Stand up the networking layer and wire it to the rest of the game.
##
## Everything here defaults to OFFLINE: the [NetworkSession] holds no peer until
## the [SessionPanel] (M) drives host()/join(), and [method has_authority] reports
## true so the solo path runs the identical command flow as the host. The
## [CommandRouter] is the single seam [method submit] that all player intents
## route through — see [method _on_dig_requested] et al. The [CommandLog] backs
## late-join replay, [PlayerSync] broadcasts/receives avatar positions, and the
## panel lives in the HUD's CanvasLayer so it overlays the world.
func _build_net() -> void:
	_session = NetworkSession.new()
	_session.name = "NetworkSession"
	add_child(_session)

	_command_log = CommandLog.new()

	_router = CommandRouter.new()
	_router.name = "CommandRouter"
	add_child(_router)
	_router.setup(_session, _command_bus, self, _command_log)
	_router.state_received.connect(_on_state_received)

	# Remote-peer avatars live under a dedicated container.
	_remote_players = Node3D.new()
	_remote_players.name = "RemotePlayers"
	add_child(_remote_players)

	_player_sync = PlayerSync.new()
	_player_sync.name = "PlayerSync"
	add_child(_player_sync)
	_player_sync.setup(_session, _player, _remote_players)

	# Session panel: lives in the HUD CanvasLayer so it overlays gameplay. The
	# panel only emits intent signals; World owns the session lifecycle.
	_session_panel = _SESSION_PANEL_SCENE.instantiate()
	_hud.add_child(_session_panel)
	_session_panel.bind(_session)
	_session_panel.host_requested.connect(_on_host_requested)
	_session_panel.join_requested.connect(_on_join_requested)
	_session_panel.leave_requested.connect(_on_leave_requested)

	# On a fresh client join, pull the host's world state and replay it.
	_session.session_started.connect(_on_session_started)


## Panel asked to host: open a server on the default port.
func _on_host_requested() -> void:
	_session.host()


## Panel asked to join [param address] on the default port.
func _on_join_requested(address: String) -> void:
	_session.join(address)


## Panel asked to leave: tear the session down (returns to OFFLINE / solo).
func _on_leave_requested() -> void:
	_session.leave()


## A session became active. A joining client (not hosting) requests the host's
## full world snapshot so it can rebuild + replay; the host has nothing to pull.
func _on_session_started(hosting: bool) -> void:
	if not hosting:
		_router.request_state.rpc_id(NetworkSession.HOST_PEER_ID)


## The host's late-join snapshot arrived: rebuild the world from its seed and
## replay every logged command so this client matches the shared world.
func _on_state_received(state: Dictionary) -> void:
	var new_seed: int = int(state.get("seed", seed_value))
	var log_entries: Array = state.get("log", [])
	rebuild_for_session(new_seed, log_entries)


## Rebuild terrain / flora / blocks for [param new_seed] then replay
## [param log_entries] (encoded [CommandCodec] dicts) in order.
##
## Used by a late-joining client after the host's snapshot arrives. The player is
## re-parked, Umbrals are cleared (host-authority spawns them; clients never do),
## and the music/intensity state is left running. Replay routes each decoded
## command straight through the [CommandBus] (not the router) so it is applied
## locally without re-broadcasting.
func rebuild_for_session(new_seed: int, log_entries: Array) -> void:
	seed_value = new_seed
	_world_seed = WorldSeed.new(seed_value)

	# Rebuild terrain with the new seed.
	if is_instance_valid(_voxel_world):
		_voxel_world.queue_free()
		remove_child(_voxel_world)
	_build_terrain()

	# Clear and rebuild the flora subtree (re-scattered once terrain streams in).
	for child in _flora.get_children():
		child.queue_free()
	_flora_scattered = false

	# Clear placed blocks; replay will re-create them with identical names.
	for child in _blocks.get_children():
		child.queue_free()

	# Clear blooms and Umbrals (host-only; clients hold none).
	for child in _blooms.get_children():
		child.queue_free()
	for child in _umbrals.get_children():
		if child is Umbral:
			_combat.unregister((child as Umbral).get_instance_id())
		child.queue_free()

	# Re-park the player; deferred placement drops them once terrain streams in.
	_player_placed = false
	_poll_elapsed = 0.0
	_player.global_position = Vector3(0.0, PLAYER_SAFE_ALTITUDE, 0.0)
	_player.velocity = Vector3.ZERO
	set_process(true)

	# Replay the host's committed history in order.
	_replay_log(log_entries)


## Decode and apply each entry in [param log_entries] through the bus, in order.
## Undecodable / stale entries (despawned targets) are skipped.
func _replay_log(log_entries: Array) -> void:
	for entry in log_entries:
		if not (entry is Dictionary):
			continue
		var cmd := CommandCodec.decode(entry, self)
		if cmd != null:
			_command_bus.execute(cmd)


# ---------------------------------------------------------------------------
# Pause menu + settings (Escape)
# ---------------------------------------------------------------------------


## Stand up the Escape pause menu and the persisted [GameSettings] it edits.
##
## The menu lives in the HUD CanvasLayer, added after the other panels so it
## overlays them, and only emits intent signals — World owns pausing, quitting,
## and applying each setting to the engine. Settings load from (and save back
## to) user://settings.cfg, so they survive restarts.
func _build_pause_menu() -> void:
	_settings = GameSettings.new()
	_settings.load_from_file()
	_settings_applier = SettingsApplier.new(_player)
	_pause_menu = _PAUSE_MENU_SCENE.instantiate()
	_hud.add_child(_pause_menu)
	_pause_menu.bind(_settings)
	_pause_menu.opened.connect(_on_menu_opened)
	_pause_menu.closed.connect(_on_menu_closed)
	_pause_menu.quit_requested.connect(_on_quit_requested)
	_settings.changed.connect(_on_setting_changed)
	_settings_applier.apply_all(_settings)


## Pause the simulation while the menu is up — but only offline: in a live
## co-op session the shared world keeps running under the menu overlay. The
## menu itself processes ALWAYS, so Escape still closes it while paused.
func _on_menu_opened() -> void:
	if _session == null or not _session.is_active():
		get_tree().paused = true


func _on_menu_closed() -> void:
	get_tree().paused = false


func _on_quit_requested() -> void:
	get_tree().quit()


## A setting changed in the menu: apply it to the engine and persist the file.
func _on_setting_changed(key: StringName, _value: Variant) -> void:
	_settings_applier.apply(key, _settings)
	_settings.save_to_file()


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
	_router.submit(DigCommand.new(world_pos, radius))


func _on_place_requested(world_pos: Vector3, radius: float) -> void:
	_router.submit(PlaceCommand.new(world_pos, radius))


func _on_harvest_requested(target: Node, drops: Array[ItemAmount]) -> void:
	_router.submit(HarvestCommand.new(target, drops))


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
	# Casting is client-local (non-replicable); the router executes it on the
	# originating peer only.
	_router.submit(CastCommand.new(abilities[index], target_pos))


func _on_craft_requested(recipe: Recipe) -> void:
	# Crafting is client-local (non-replicable); routed for a single seam.
	_router.submit(CraftCommand.new(recipe))


## Route a block placement intent (N / B) through the command layer.
func _on_place_block_requested(item_id: StringName, position: Vector3) -> void:
	_router.submit(PlaceBlockCommand.new(item_id, position))


## Route a Note Block interaction (E) into a pitch-cycle through the bus.
func _on_block_interact_requested(target: Node) -> void:
	_router.submit(CycleNoteCommand.new(target))


## Route a block removal intent (F on a block) through the command layer.
func _on_block_remove_requested(target: Node) -> void:
	_router.submit(RemoveBlockCommand.new(target))


# ---------------------------------------------------------------------------
# Combat: player strike, Umbral spawning, and the respawn sequence
# ---------------------------------------------------------------------------


## Route a player melee strike into a [DamageCommand] with forward+up knockback.
## Burning Vigor (pewter) amplifies the strike's damage by [constant VIGOR_STRIKE_MULT].
func _on_strike_requested(target_id: int, _hit_point: Vector3) -> void:
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	if forward.length() > 0.0:
		forward = forward.normalized()
	var knockback := forward * STRIKE_KNOCKBACK_FORWARD + Vector3.UP * STRIKE_KNOCKBACK_UP
	var damage := PLAYER_STRIKE_DAMAGE
	if _status != null and _status.has(_player.get_instance_id(), &"vigor"):
		damage *= VIGOR_STRIKE_MULT
	# Combat is client-local (non-replicable) in v0: damage stays on the peer
	# that dealt it. Umbrals are host-only, so on a client this no-ops harmlessly.
	_router.submit(DamageCommand.new(target_id, damage, knockback))


# ---------------------------------------------------------------------------
# Ferromancy: coin toss, channel toggles, flare (Phase 8)
# ---------------------------------------------------------------------------


## Spawn a thrown [FerricCoin] at [param origin] moving at [param velocity].
## Wired into [member WorldContext.coin_spawn]; the [ThrowCoinCommand] calls this
## only after it has consumed a coin from the inventory.
func _spawn_coin(origin: Vector3, velocity: Vector3) -> void:
	if _coins == null:
		return
	var coin: FerricCoin = _FERRIC_COIN_SCENE.instantiate()
	_coins.add_child(coin)
	coin.global_position = origin
	coin.linear_velocity = velocity
	coin.struck.connect(_on_coin_struck)


## A thrown coin hit an Umbral: deal strike damage when it landed fast enough.
func _on_coin_struck(target_id: int, speed: float) -> void:
	if speed <= COIN_STRIKE_SPEED:
		return
	_router.submit(DamageCommand.new(target_id, COIN_STRIKE_DAMAGE, Vector3.ZERO))


## Route a channel toggle intent (G / T) through the command layer.
func _on_channel_toggle_requested(channel_id: StringName) -> void:
	_router.submit(ToggleChannelCommand.new(channel_id))


## Route a flare press/release (Shift) through the command layer.
func _on_flare_changed(active: bool) -> void:
	_router.submit(SetFlareCommand.new(active))


## Route a coin-throw intent (Q) through the command layer.
func _on_throw_coin_requested(origin: Vector3, velocity: Vector3) -> void:
	_router.submit(ThrowCoinCommand.new(origin, velocity))


## Drive deterministic Umbral spawning and far-despawn each simulation tick.
##
## HOST-ONLY in a session: Umbrals are local-host-side in v0 and are not synced,
## so a non-authoritative client skips spawn planning entirely (it holds no
## creatures). Offline (solo) still has authority and spawns as before.
func _on_combat_tick(tick_index: int) -> void:
	if not _player_placed:
		return
	if not _session.has_authority():
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
	# Damage is client-local (non-replicable); Umbral contact only happens on the
	# host where Umbrals live, so this stays host-local in a session.
	_router.submit(DamageCommand.new(_player.get_instance_id(), damage, knockback))


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
	# Bind the rig now that the player and combat service exist; its ferro effects
	# read both at cast time.
	_ferro_rig.setup(self, _status, _combat)
	_context.ability_effects = {
		&"shape_burst": _effect_shape_burst,
		&"lumen_bloom": _effect_lumen_bloom,
		&"skyward": _effect_skyward,
		&"ferro_pull": _ferro_rig.ferro_pull,
		&"ferro_push": _ferro_rig.ferro_push,
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
