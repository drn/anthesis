## Deterministic RNG service for world generation and simulation.
##
## WorldSeed provides a root seed and a way to derive independent,
## reproducible [RandomNumberGenerator] streams for each named system.
## Every stream is seeded deterministically from (root_seed, stream_name),
## so re-creating the same WorldSeed with the same integer always yields
## identical sequences — regardless of the order systems are initialized.
##
## Usage:
##   var ws := WorldSeed.new(12345)
##   var rng := ws.derive("terrain")
##   rng.randi()   # reproducible
class_name WorldSeed

## The root seed supplied at construction time.
var seed: int:
	get:
		return _seed
	set(_v):
		push_error("WorldSeed.seed is read-only")

var _seed: int


## Construct a WorldSeed with the given integer [param root_seed].
func _init(root_seed: int) -> void:
	_seed = root_seed


## Return a [RandomNumberGenerator] seeded from [param stream_name].
##
## Two calls with the same [param stream_name] return generators with
## identical starting state (independent instances, not shared).
## Two calls with different stream names return generators with different
## (uncorrelated) seeds.
func derive(stream_name: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = _stream_seed(stream_name)
	return rng


## Compute the deterministic seed for a named stream.
##
## Uses a djb2-style hash combined with the root seed to produce a
## 64-bit integer that is unique to (root_seed, stream_name).
func _stream_seed(stream_name: String) -> int:
	# djb2 hash over UTF-8 bytes of the stream name
	var h: int = 5381
	for ch in stream_name.to_utf8_buffer():
		h = ((h << 5) + h) ^ ch
	# Mix with root seed using a simple bijective step (FNV-inspired).
	# Constant is 0x9e3779b97f4a7c15 reinterpreted as signed int64; the
	# multiply wraps in 64-bit arithmetic, which is reproducible.
	return (_seed ^ h) * -7046029254386353131
