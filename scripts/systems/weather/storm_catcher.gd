## A sky-exposed crystal pylon that converts dun gems to charged gems during a
## Resonance Storm.
##
## The StormCatcher is a [StaticBody3D] prop the player can place and interact
## with. Its four-gem rack accepts dun gems via [method deposit], returns all
## held gems via [method collect], and converts one dun to charged per storm
## pulse via [method charge_one] (called by the world integrator when
## [WeatherSystem] fires [signal WeatherSystem.storm_pulse] and this node is
## sky-exposed).
##
## Visual update: [signal gems_changed] fires on every mutation so a connected
## gem-row visual can brighten as [method charged_count] rises.
class_name StormCatcher
extends StaticBody3D

## Fires whenever the gem counts change (deposit, collect, or charge_one).
## [param dun] and [param charged] reflect the new totals.
signal gems_changed(dun: int, charged: int)

## Maximum gems (dun + charged combined) the rack holds at once.
const CAPACITY := 4

var _dun: int = 0
var _charged: int = 0


func _ready() -> void:
	add_to_group(&"storm_catchers")


## Accept up to remaining capacity dun gems; return the number accepted.
##
## If [param count] exceeds the remaining space, only the available slots
## are filled. Returns 0 when the rack is full.
func deposit(count: int) -> int:
	var space := CAPACITY - (_dun + _charged)
	var accepted := mini(count, space)
	if accepted <= 0:
		return 0
	_dun += accepted
	gems_changed.emit(_dun, _charged)
	return accepted


## Empty the rack; return a Dictionary with keys "dun" and "charged".
##
## Both counts are zeroed and [signal gems_changed] fires (with 0, 0).
func collect() -> Dictionary:
	var result := {"dun": _dun, "charged": _charged}
	_dun = 0
	_charged = 0
	gems_changed.emit(_dun, _charged)
	return result


## Convert one dun gem to a charged gem; return [code]true[/code] on success.
##
## Returns [code]false[/code] when there are no dun gems to convert.
## [signal gems_changed] fires on a successful conversion.
func charge_one() -> bool:
	if _dun <= 0:
		return false
	_dun -= 1
	_charged += 1
	gems_changed.emit(_dun, _charged)
	return true


## Current count of dun (uncharged) gems in the rack.
func dun_count() -> int:
	return _dun


## Current count of charged gems in the rack.
func charged_count() -> int:
	return _charged
