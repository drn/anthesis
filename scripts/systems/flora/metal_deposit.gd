## A harvestable metal ore deposit — a static world prop that participates in
## the ferromantic metal-source protocol (Contract #7).
##
## MetalDeposit is a [StaticBody3D] root script. On [method _ready] it registers
## itself in the [code]metal_sources[/code] scene group so [FerroKinetics] can
## locate it for push/pull. It is always anchored (embedded in terrain), so
## [method is_metal_anchored] returns true — any push/pull resolves as a player
## impulse rather than moving the deposit.
##
## Each deposit scene pairs this script with a [Harvestable] child that
## declares the ore drops and lumen reward.
class_name MetalDeposit
extends StaticBody3D

## Ferromantic mass in kg. Deposits are heavy anchors — default 400 kg.
@export var metal_mass := 400.0


func _ready() -> void:
	add_to_group(&"metal_sources")


## Metal-source protocol (#7): deposits are terrain-anchored and never move.
func is_metal_anchored() -> bool:
	return true
