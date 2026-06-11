## Immutable definition of a single adaptive music stem loaded from a .tres resource.
##
## MusicStemDef describes one looping audio stem in the adaptive music system:
## its id, the path to its WAV asset, the intensity thresholds that govern its
## volume, and whether it plays at full volume regardless of intensity.
##
## Stems are authored as MusicStemDef resources under resources/music/ and
## loaded by MusicStemRegistry. MusicSystem reads each def to drive the
## corresponding AudioStreamPlayer volume in response to IntensityModel level.
class_name MusicStemDef
extends Resource

## Unique identifier for this stem, used as the key in stem lookups.
@export var id: StringName
## Res-path to the WAV asset for this stem.
@export var stream_path: String
## Intensity level at which this stem begins fading in (0..1).
## Below this value the stem is silent (-60 dB).
@export var threshold: float = 0.0
## Intensity level at which the stem reaches full volume (base_db).
## Must be >= threshold.
@export var full_at: float = 1.0
## Volume in dB when the stem is at or above full_at intensity.
@export var base_db: float = -6.0
## When true, the stem plays at base_db regardless of intensity level.
## Used for the ambient pad that is always audible.
@export var always_on: bool = false
