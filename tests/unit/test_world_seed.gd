extends GutTest

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _seq(rng: RandomNumberGenerator, count: int) -> Array:
	var out := []
	for _i in range(count):
		out.append(rng.randi())
	return out


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


## Same seed + same stream => identical sequences.
func test_same_seed_same_stream_identical() -> void:
	var ws1 := WorldSeed.new(42)
	var ws2 := WorldSeed.new(42)
	var seq1 := _seq(ws1.derive("terrain"), 8)
	var seq2 := _seq(ws2.derive("terrain"), 8)
	assert_eq(seq1, seq2, "Same seed+stream must produce identical sequences")


## Different streams from the same seed => different sequences.
func test_different_streams_different_sequences() -> void:
	var ws := WorldSeed.new(99)
	var seq_a := _seq(ws.derive("flora"), 8)
	var seq_b := _seq(ws.derive("weather"), 8)
	assert_ne(seq_a, seq_b, "Different stream names must produce different sequences")


## Different seeds => different sequences for the same stream.
func test_different_seeds_different_sequences() -> void:
	var ws1 := WorldSeed.new(1)
	var ws2 := WorldSeed.new(2)
	var seq1 := _seq(ws1.derive("terrain"), 8)
	var seq2 := _seq(ws2.derive("terrain"), 8)
	assert_ne(seq1, seq2, "Different seeds must produce different sequences for the same stream")


## derive() called twice with the same stream returns fresh but identical generators.
func test_derive_twice_same_stream_fresh_identical() -> void:
	var ws := WorldSeed.new(777)
	var rng_a := ws.derive("loot")
	var rng_b := ws.derive("loot")
	# Both start at the same state, so their sequences must match
	var seq_a := _seq(rng_a, 8)
	var seq_b := _seq(rng_b, 8)
	assert_eq(seq_a, seq_b, "Two generators derived from the same stream must start identically")
	# Consuming one should not affect the other (they are independent)
	rng_a.randi()
	var next_b := rng_b.randi()
	var rng_c := ws.derive("loot")
	# rng_c should still restart from the beginning
	var seq_c := _seq(rng_c, 8)
	assert_eq(seq_c[0], seq_b[0], "A fresh derive must always restart from stream seed")


## seed property is readable and equals the value passed to _init.
func test_seed_property_readable() -> void:
	var ws := WorldSeed.new(12345)
	assert_eq(ws.seed, 12345, "seed property must return the root seed")
