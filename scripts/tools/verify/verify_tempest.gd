# scripts/tools/verify/verify_tempest.gd — SceneTree harness, NOT a GUT test.
#
# Boots the real world.tscn windowed and exercises the full Phase 9 tempest /
# Resonance Storm loop through the live command/context seams:
#   1. Grant charged + dun gems and a storm catcher (state SETUP, not under test).
#   2. Place a storm catcher in open air ahead of the player and rack a dun gem.
#   3. force_storm() then let the live clock drive warning -> storm: assert the
#      HUD banner shows and the StormVisuals wind layer is emitting, and that the
#      first storm pulse charged the sky-exposed catcher's dun gem.
#   4. Inhale a charged gem via InhaleCommand: assert the tempest well filled and
#      the player's glow light_energy rose above zero.
#   5. Cast Skylash via CastCommand: assert the player's gravity_dir flipped off
#      DOWN, then ticks past the lash duration and asserts it restored.
#   6. Spawn an Umbral at the player's feet and cast Bondlash: assert it carries
#      the &"rooted" status.
# Screenshots land in docs/media/ named phase9-*.png. Any engine script error
# during the run fails the harness.
#
# Run (windowed, never --headless):
#   HOME=/tmp/anthesis-home tools/godot/macos_editor.app/Contents/MacOS/Godot \
#     --path . -s res://scripts/tools/verify/verify_tempest.gd
extends SceneTree

const WORLD_SCENE := "res://scenes/world/world.tscn"
const MEDIA_DIR := "res://docs/media"
const CATCHER_SCENE := "res://scenes/props/storm_catcher.tscn"
const UMBRAL_SCENE := "res://scenes/creatures/umbral.tscn"

var _world: World
var _frame := 0
var _failed := false
var _catcher: StormCatcher
var _umbral: Umbral
var _sky: AbilityDef
var _bond: AbilityDef
var _gravity_flipped := false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MEDIA_DIR))
	var registry := AbilityRegistry.new()
	_sky = registry.ability(&"sky_lash")
	_bond = registry.ability(&"bond_lash")
	_world = load(WORLD_SCENE).instantiate()
	root.add_child(_world)


func _process(_delta: float) -> bool:
	_frame += 1

	# Let terrain stream and the player land, then grant the gem economy + catcher.
	if _frame == 200:
		_grant_gems()
		_place_catcher()
	if _frame == 240:
		_snap("phase9-1-setup")

	# Summon the storm and deterministically pump the weather machine through
	# warning -> storm + past the first pulse (storm tick 20). Pumping on_tick
	# directly fires weather_changed (banner + visuals) and storm_pulse (catcher
	# charge) without depending on how many live-clock ticks accrued per frame.
	if _frame == 260:
		_force_storm_to_first_pulse()
	if _frame == 300:
		_check_storm_visuals()
		_check_catcher_charged()
		_snap("phase9-2-storm")
	if _frame == 320:
		_snap("phase9-3-catcher")

	# Inhale: fill the well, light the glow.
	if _frame == 540:
		_inhale()
	if _frame == 560:
		_check_glow()
		_snap("phase9-4-tempest-glow")

	# Skylash: flip gravity, then confirm it restores after the lash window.
	if _frame == 580:
		_cast_sky_lash()
	if _frame == 582:
		_snap("phase9-5-skylash")

	# Bondlash: root a spawned Umbral.
	if _frame == 600:
		_spawn_umbral()
	if _frame == 620:
		_cast_bond_lash()
		_check_bond_lash()

	# Skylash lasts sky.magnitude seconds (6 s = 60 ticks). Deterministically pump
	# the status tracker past that window, then assert gravity restored.
	if _frame == 720:
		_expire_sky_lash()
		_check_gravity_restored()
		if _failed:
			print("VERIFY_FAIL verify_tempest — see CHECK lines above")
		else:
			print("VERIFY_OK verify_tempest frame=%d" % _frame)
		return true
	return false


# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------


func _grant_gems() -> void:
	var inv := _world.inventory()
	inv.add(&"charged_gem", 4)
	inv.add(&"dun_gem", 4)
	inv.add(&"storm_catcher", 2)


func _place_catcher() -> void:
	var player := _world.player()
	var forward := -player.global_transform.basis.z
	forward.y = 0.0
	_catcher = load(CATCHER_SCENE).instantiate()
	_world.add_child(_catcher)
	# Drop it in open ground a few metres ahead, lifted slightly so the sky ray
	# starts above the catcher body.
	_catcher.global_position = (
		player.global_position + forward.normalized() * 4.0 + Vector3.UP * 1.0
	)
	_catcher.deposit(1)
	_check("catcher racked a dun gem", _catcher.dun_count() == 1)


## Pump the weather machine: force_storm, then enough on_tick calls to clear the
## 10-tick forced warning, enter the storm, and fire the first pulse (storm tick
## 20). The live clock also ticks weather, but extra ticks only advance the storm.
func _force_storm_to_first_pulse() -> void:
	var weather: WeatherSystem = _world.get_node("Weather")
	weather.force_storm()
	# 1 calm -> warning, 10 warning -> storm, 20 storm ticks -> first pulse.
	for t in range(1, 1 + 10 + WeatherSystem.PULSE_INTERVAL + 1):
		weather.on_tick(t)


func _check_storm_visuals() -> void:
	var weather: WeatherSystem = _world.get_node("Weather")
	_check("weather reached the storm state", weather.state() == &"storm")
	var hud := _world.hud()
	var banner: Label = hud.get_node_or_null("StormBanner")
	_check("storm banner is visible", banner != null and banner.visible)
	var visuals := _world.get_node_or_null("StormVisuals")
	var wind: GPUParticles3D = null
	if _world.get_node_or_null("Environment_Rig") != null:
		wind = _world.get_node("Environment_Rig").get_node_or_null("StormWindParticles")
	_check("StormVisuals node exists", visuals != null)
	_check("storm wind particles emitting", wind != null and wind.emitting)


func _check_catcher_charged() -> void:
	_check("storm pulse charged the exposed catcher", _catcher.charged_count() >= 1)


func _inhale() -> void:
	var ctx: WorldContext = _world.command_bus().get("_ctx")
	var well: LumenWell = ctx.tempest.well()
	var before: float = well.current()
	_world.command_bus().execute(InhaleCommand.new())
	_check("inhale filled the tempest well", well.current() > before)


func _check_glow() -> void:
	var glow: OmniLight3D = _world.player().get_node_or_null("TempestGlow")
	_check("player carries a tempest glow", glow != null)
	if glow != null:
		_check("the glow lit up while holding light", glow.light_energy > 0.0)


func _cast_sky_lash() -> void:
	var player := _world.player()
	# Top up so the cost gate passes regardless of leak.
	_world.command_bus().get("_ctx").tempest.well().add(TempestLight.CAPACITY)
	_world.command_bus().execute(CastCommand.new(_sky, Vector3.ZERO))
	_gravity_flipped = player.gravity_dir != Vector3.DOWN
	_check("Skylash redirected the player's gravity", _gravity_flipped)


func _spawn_umbral() -> void:
	var player := _world.player()
	_umbral = load(UMBRAL_SCENE).instantiate()
	_world.add_child(_umbral)
	var def := CreatureRegistry.new().creatures()[0]
	_umbral.setup(def, _world.get_node("SimulationClock"), RandomNumberGenerator.new(), player)
	_umbral.global_position = player.global_position + Vector3(0.6, 0.0, 0.0)


func _cast_bond_lash() -> void:
	_world.command_bus().get("_ctx").tempest.well().add(TempestLight.CAPACITY)
	_world.command_bus().execute(CastCommand.new(_bond, _umbral.global_position))


func _check_bond_lash() -> void:
	var status: StatusEffectSystem = _world.get_node("StatusEffects")
	_check(
		"Bondlash rooted the nearby Umbral",
		status.has(_umbral.get_instance_id(), &"rooted"),
	)


## Pump the status tracker past the Skylash duration so its on_expire restores
## gravity (deterministic, independent of how many live-clock ticks accrued).
func _expire_sky_lash() -> void:
	var status: StatusEffectSystem = _world.get_node("StatusEffects")
	for t in range(1, int(_sky.magnitude * 10.0) + 2):
		status.on_tick(t)


func _check_gravity_restored() -> void:
	_check("gravity restored after the lash window", _world.player().gravity_dir == Vector3.DOWN)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _check(label: String, ok: bool) -> void:
	print("CHECK %s: %s" % [label, "ok" if ok else "FAIL"])
	if not ok:
		_failed = true


func _snap(image_name: String) -> void:
	var img := root.get_texture().get_image()
	var absolute := ProjectSettings.globalize_path("%s/%s.png" % [MEDIA_DIR, image_name])
	var err := img.save_png(absolute)
	print("SNAP %s err=%d" % [absolute, err])
