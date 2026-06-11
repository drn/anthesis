## Shared dependency bundle passed to every [WorldCommand] on apply.
##
## WorldContext is the seam between commands (which describe intent) and the
## systems that carry it out. Commands never reach into the scene tree; they
## only touch services exposed here. As new mutable subsystems appear
## (inventory, entities, lighting), add them as fields on this context.
class_name WorldContext
extends RefCounted

## Service that performs voxel terrain mutations. Assigned by the integrator.
var terrain_edit: TerrainEditService
