# Gameplay Guide

How to play Anthesis: what every item does, where loot comes from, how magic,
combat, and the in-world music sequencer work, and how the systems feed each
other. This is the player-facing view; for the engineering side, see
[ARCHITECTURE.md](ARCHITECTURE.md) (the layer model) and the per-system deep
dives in [docs/systems/](systems/).

---

## The Loop at a Glance

```
dig terrain ──► soil + crystal shards ──┐
harvest flora ──► lumen + spores/petals ─┼──► craft ──► torches, bricks,
fight Umbrals ──► shards + spores        ┘             sequencer parts
                                                          │
        lumen powers magic ◄── flora glow keeps the dark away
                                                          ▼
                              place a Sequencer Core + Note Blocks
                              and compose music inside the world
```

Everything you can craft traces back to three activities: digging, harvesting
glowing flora, and fighting the shadow creatures that condense in the dark.

---

## Controls

| Input | Action |
|-------|--------|
| **W A S D** | Move |
| **Space** | Jump |
| **Mouse** | Look |
| **Left click** | Dig terrain |
| **Right click** | Place terrain |
| **F** | Strike (attack Umbrals / remove placed blocks) |
| **E** | Harvest flora · retune a Note Block |
| **1 / 2 / 3** | Cast: Lumen Bloom · Worldshaper Burst · Skyward Step |
| **N** | Place a Sequencer Core (requires one in inventory) |
| **B** | Place a Note Block (requires one in inventory) |
| **I** | Inventory + crafting panel (toggle) |
| **M** | Multiplayer panel (host / join) |
| **Esc** | Pause menu — settings + key bindings |

Key bindings can be rebound from the pause menu (Esc).

> This table mirrors the one in the [README](../README.md#controls) — if a
> default binding changes, update both.

---

## Digging

Left click carves a smooth sphere out of the terrain — every surface is
diggable, so caves, tunnels, and arches are yours to make. Right click places
terrain back.

Every dig also awards loot:

| Drop | Chance | Amount |
|------|--------|--------|
| **Soil** | Always | Scales with dig radius (3 per dig at the default radius, max 8) |
| **Crystal Shard** | 18% | 1 |

The crystal roll is **deterministic per location**: the same spot in the same
world always gives the same result. Re-digging one crater will never produce a
shard that wasn't there — to hunt shards, keep digging in *new* places.

Crystal shards are the keystone material: every crafting recipe ultimately
requires them.

---

## Flora and Harvesting

Bioluminescent flora dots the world. Press **E** while looking at a prop to
harvest it. Harvesting does two things at once: it grants item drops *and*
fills your lumen well (the magic resource).

| Flora | Lumen | Item drops |
|-------|-------|------------|
| Glow Mushroom (cyan cap) | 8 | 2× Glow Spore |
| Glow Flower (magenta petals) | 10 | 2× Lumen Petal |
| Crystal formation | 15 | 3× Crystal Shard |

Crystal formations are the best shard source in the game — three guaranteed
shards per harvest, on top of the biggest lumen payout.

Flora matters even when you don't harvest it: its glow suppresses Umbral
spawning nearby (see [Combat](#combat-and-the-umbrals)). Stripping an area of
all its light makes it dangerous.

---

## Items

| Item | Type | How you get it | What it's for |
|------|------|----------------|---------------|
| **Soil** | material | Digging (always) | Bloom Bricks |
| **Crystal Shard** | material | Crystal formations (3×), Digging (18%), Shardling kills (2×) | Every recipe |
| **Glow Spore** | material | Glow Mushrooms (2×), Voidmoth kills (1×) | Torches, Note Blocks |
| **Lumen Petal** | material | Glow Flowers (2×) | Lumen Torches |
| **Bloom Brick** | material | Crafted | Note Blocks, Sequencer Core |
| **Lumen Torch** | placeable | Crafted | Light source; Sequencer Core ingredient |
| **Note Block** | placeable | Crafted | One voice of the sequencer |
| **Sequencer Core** | placeable | Crafted | The heart of the in-world sequencer |

---

## Crafting

Press **I** to open the inventory and crafting panel. Recipes light up when
you can afford them.

| Recipe | Inputs | Output |
|--------|--------|--------|
| **Bloom Brick** | 4 Soil + 1 Crystal Shard | 2 Bloom Bricks |
| **Lumen Torch** | 1 Crystal Shard + 2 Glow Spores + 1 Lumen Petal | 1 Lumen Torch |
| **Note Block** | 1 Bloom Brick + 1 Glow Spore | 2 Note Blocks |
| **Sequencer Core** | 2 Bloom Bricks + 2 Crystal Shards + 1 Lumen Torch | 1 Sequencer Core |

The full chain to your first sequencer: dig until you have shards and soil,
harvest mushrooms and flowers for spores and petals, craft bricks → torch →
core → note blocks.

---

## Magic: Lumen

Anthesis uses a hard-magic system: every ability has a fixed lumen cost and a
fixed cooldown, no exceptions. **Lumen** is living light gathered by
harvesting flora, stored in your lumen well (capacity 100, shown on the HUD).
Nothing is conjured for free — if the well can't afford a cast, the cast
fails.

| Key | Ability | Cost | Cooldown | Effect |
|-----|---------|------|----------|--------|
| **1** | **Lumen Bloom** | 15 | 2.0 s | Plants a pulsing mote of light. Pushes back the dark — its glow counts as a safe zone that blocks Umbral spawns. |
| **2** | **Worldshaper Burst** | 25 | 3.0 s | Tears a sphere of terrain apart — digging as a spell, in a perfect carved radius. |
| **3** | **Skyward Step** | 10 | 1.5 s | The ground pushes back beneath you, launching you into the air. |

(Cooldowns are defined in ticks on each ability's `.tres` — the simulation
runs at 10 ticks per second, so 20 ticks = 2.0 s.)

Tactically: Lumen Bloom is your portable safety, Worldshaper Burst is bulk
excavation, and Skyward Step is mobility (and an escape button when Umbrals
swarm).

---

## Combat and the Umbrals

**Umbrals** — shadow wisps with glowing cores — condense out of darkness.
They only spawn in a ring 20–42 m away from you, and **never within 9 m of a
glow source** (flora or an active Lumen Bloom). Light is your territory; the
dark is theirs. At most 6 are alive at once.

Press **F** to strike. Each species drops materials on death, so combat feeds
the crafting loop:

| Creature | Health | Damage | Speed | Drops |
|----------|--------|--------|-------|-------|
| **Voidmoth** | 12 | 4 | Fast | 1× Glow Spore |
| **Shardling** | 30 | 9 | Slow | 2× Crystal Shards |

Shardlings are the tougher fight but the better payday — two guaranteed
crystal shards beats gambling on the 18% dig roll.

If you die, you respawn at your spawn point after 4 seconds with full health.
Inventory is kept.

---

## The Music

The soundtrack is generative and adaptive: five phase-locked EDM stems (pad,
bass, arp, drums, shimmer) fade in and out with an intensity meter driven by
what you're doing. Stand still in safety and you'll hear only the ambient
pad; dig, cast, and fight — or let Umbrals get close — and the bass, drums,
and shimmer layer in. The full band plays only when things are genuinely
hectic.

Everything runs at a fixed 110 BPM, which matters for the next section.

---

## The Sequencer (Signature Mechanic)

The in-world music sequencer lets you compose loops *with your hands, in the
world*, locked to the soundtrack's transport.

1. **Craft** a Sequencer Core and a stack of Note Blocks (see
   [Crafting](#crafting)).
2. **Place the core** with **N** — a slowly rotating gold-white prism, locked
   to the global 110-beat pulse.
3. **Ring it with Note Blocks** using **B**. Where a block sits around the
   core decides *when* it plays: the circle is divided into 16 steps of a
   one-bar loop (~2.2 s). North of the core is step 0, and steps advance
   clockwise — east is step 4, south is step 8, west is step 12.
4. **Retune** a block by pressing **E** on it — each press cycles it through
   an 8-note pentatonic bank, so anything you place stays in key.
5. **Rearrange freely.** Strike a block with **F** to pick it back up.
   Nudging a block around the circle shifts its timing; moving it closer or
   farther doesn't matter, only the angle does.

The spatial arrangement *is* the pattern. A tight cluster north of the core
is a burst at the top of the bar; blocks at north, east, south, and west are
a four-on-the-floor. Because the core shares its clock with the adaptive
soundtrack, your loop always plays in time with the music.

---

## Co-op

Press **M** to host or join a session — up to 8 players (1 host + 7 clients)
over LAN/direct ENet. The world is host-authoritative: terrain edits and
placed blocks are shared and stay in sync (late joiners replay the world's
edit history on arrival), while inventory, lumen, and health remain personal
to each player.

---

## Settings

**Esc** opens the pause menu: mouse sensitivity, volume, fullscreen, and full
key rebinding. The game pauses while the menu is open (solo only — the world
keeps running for others in co-op).
