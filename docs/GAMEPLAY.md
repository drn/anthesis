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
fight Umbrals ──► shards + spores        ┘             sequencer parts, coins,
mine metal deposits ──► ores ─────────────────► refine ──► metal flakes     dun gems
                                                          │                       │
        lumen powers instant magic ◄── flora glow keeps the dark away             │
        metal flakes power channels + Ferromancy          │              rack on storm catcher
                                                          ▼                       ▼
                              place a Sequencer Core + Note Blocks         survive the storm
                              and compose music inside the world                   │
                                                                          charged gem ──► inhale (R)
                                                                                         ▼
                                                                          Tempestlight: heals, speed,
                                                                          Skylash + Bondlash abilities
```

Everything you can craft traces back to five activities: digging, harvesting
glowing flora, fighting the shadow creatures that condense in the dark, mining
metal deposits for the Ferromancy tier, and surviving Resonance Storms to charge
gems for the Tempestlight tier of magic.

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
| **E** | Harvest flora · retune a Note Block · interact with storm catcher |
| **R** | Inhale a charged gem (enter Tempestlight holding mode) |
| **H** | Place a storm catcher (requires one in inventory) |
| **1 / 2** | Cast: Bondlash · Ferropull |
| **3 / 4 / 5** | Cast: Ferropush · Lumen Bloom · Worldshaper Burst |
| **6 / 7** | Cast: Skylash · Skyward Step |
| **G** | Toggle Vigor channel (burn pewter) |
| **T** | Toggle Keensight channel (burn tin) |
| **Tab** | Metal sense — blue lines to nearby metal sources |
| **Q** | Throw ferric coin |
| **Shift** | Flare — 3× channel drain while held |
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
| **Crystal Shard** | material | Crystal formations (3×), Digging (18%), Shardling kills (2×) | Every recipe; Ferric Coin forge |
| **Glow Spore** | material | Glow Mushrooms (2×), Voidmoth kills (1×) | Torches, Note Blocks |
| **Lumen Petal** | material | Glow Flowers (2×) | Lumen Torches |
| **Bloom Brick** | material | Crafted | Note Blocks, Sequencer Core |
| **Lumen Torch** | placeable | Crafted | Light source; Sequencer Core ingredient |
| **Note Block** | placeable | Crafted | One voice of the sequencer |
| **Sequencer Core** | placeable | Crafted | The heart of the in-world sequencer |
| **Lodestone Ore** | material | Lodestone deposits (2×) | Refines to Iron Flakes |
| **Skysteel Ore** | material | Skysteel deposits (2×) | Refines to Steel Flakes |
| **Vigorite Ore** | material | Vigorite deposits (2×) | Refines to Pewter Flakes |
| **Keenglass Shard** | material | Keenglass deposits (2×) | Refines to Tin Flakes |
| **Iron Flakes** | consumable | Refine Lodestone Ore · stack 99 | Fuel Ferropull (iron reserve) |
| **Steel Flakes** | consumable | Refine Skysteel Ore · stack 99 | Fuel Ferropush (steel reserve) |
| **Pewter Flakes** | consumable | Refine Vigorite Ore · stack 99 | Fuel Vigor channel |
| **Tin Flakes** | consumable | Refine Keenglass Shard · stack 99 | Fuel Keensight channel |
| **Ferric Coin** | material | Crafted · stack 99 | Thrown projectile; Ferropull/push anchor |
| **Dun Gem** | material | Crafted · stack 16 | Rack on a storm catcher to charge during a Resonance Storm |
| **Charged Gem** | material | Storm-charged dun gem · stack 16 | Inhale (R) to fill your Tempestlight well (+40 charge) |
| **Storm Catcher** | placeable | Crafted · stack 8 | Sky-exposed crystal pylon that charges up to 4 dun gems per storm |

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
| **Iron Flakes** | 1 Lodestone Ore | 2 Iron Flakes |
| **Steel Flakes** | 1 Skysteel Ore | 2 Steel Flakes |
| **Pewter Flakes** | 1 Vigorite Ore | 2 Pewter Flakes |
| **Tin Flakes** | 1 Keenglass Shard | 2 Tin Flakes |
| **Ferric Coin** | 1 Crystal Shard + 2 Soil | 8 Ferric Coins |
| **Dun Gem** | 3 Crystal Shards + 1 Glow Spore | 1 Dun Gem |
| **Storm Catcher** | 2 Crystal Shards + 1 Keenglass Shard + 2 Soil | 1 Storm Catcher |

The full chain to your first sequencer: dig until you have shards and soil,
harvest mushrooms and flowers for spores and petals, craft bricks → torch →
core → note blocks.

For Ferromancy: find the glinting craggy deposit clusters scattered across the
terrain, harvest them for ores, then refine at the crafting bench. Each ore
yields 2 flakes; each flake provides 30 charge (well capacity 60 per metal).

---

## Magic: Lumen

Anthesis uses a hard-magic system: every ability has a fixed cost and a fixed
cooldown, no exceptions. **Lumen** — living light gathered by harvesting flora,
stored in your lumen well (capacity 100) — powers the three classic abilities.
**Metals** power the Ferromancy tier: mine deposits, refine ores into flakes,
and burn flakes for instant or sustained effects. **Tempestlight** — charged storm
energy inhaled from a charged gem — powers the two lash abilities.

Ability hotkeys are alphabetical by ability id. The full seven-slot order is:

| Key | Ability | Resource | Cost | Cooldown | Effect |
|-----|---------|----------|------|----------|--------|
| **1** | **Bondlash** | Tempestlight | 15 | 1.0 s | Roots the nearest Umbral within 2 m in place for 5 s. It keeps attacking but cannot chase. |
| **2** | **Ferropull** | Iron | 12 | 0.8 s | Yanks you toward a metal anchor, or flings a light source toward you. |
| **3** | **Ferropush** | Steel | 12 | 0.8 s | Launches you off an anchor (coin-jumping), or hurls a light source away. |
| **4** | **Lumen Bloom** | Lumen | 15 | 2.0 s | Plants a pulsing mote of light. Pushes back the dark — blocks Umbral spawns. |
| **5** | **Worldshaper Burst** | Lumen | 25 | 3.0 s | Tears a sphere of terrain apart — digging as a spell. |
| **6** | **Skylash** | Tempestlight | 20 | 1.0 s | Snaps your gravity to the nearest cardinal axis for 6 s — fall sideways, walk on walls. |
| **7** | **Skyward Step** | Lumen | 10 | 1.5 s | The ground pushes back beneath you, launching you into the air. |

(Cooldowns in seconds at 10 ticks/s. Slot order is alphabetical by ability id:
bond_lash, ferro_pull, ferro_push, lumen_bloom, shape_burst, sky_lash, skyward.)

Tactically: Lumen Bloom is your portable safety, Worldshaper Burst is bulk
excavation, and Skyward Step is mobility. The ferro abilities are your movement
and combat engine once you have metals. Bondlash pins Umbrals; Skylash lets you
escape or explore vertical surfaces — but the camera does not reorient with
gravity in v1, so movement stays yaw-based.

---

## Ferromancy

Ferromancy is Anthesis's second magic tier. Where lumen is a pool you top up by
harvesting flora, metal reserves are stocks you build up by mining and refining.
Burn the wrong metal at the wrong moment and you pay for it in pain.

### Mining and Refining

Metal deposits — craggy crystal clusters with a distinctive metallic tint —
scatter across the terrain like props. Press **E** (harvest) to collect 2 ores.
Refine at the crafting bench (**I**) to convert each ore into 2 flakes.

| Deposit | Ore | Refines to | Powers |
|---------|-----|-----------|--------|
| Lodestone (blue-grey) | Lodestone Ore | Iron Flakes | Ferropull (slot 1) |
| Skysteel (silver-white) | Skysteel Ore | Steel Flakes | Ferropush (slot 2) |
| Vigorite (amber-red) | Vigorite Ore | Pewter Flakes | Vigor channel (G) |
| Keenglass (pale cyan) | Keenglass Shard | Tin Flakes | Keensight channel (T) |

Each flake gives 30 charge; each metal well holds 60 charge (2 flakes' worth).
Flakes are **auto-swallowed** from your inventory the moment you cast or channel —
you never manually equip them.

### Ferropull and Ferropush (Slots 1 and 2)

Hold your aim within a 30° cone of a metal target and press **1** (Ferropull) or
**2** (Ferropush). Each cast costs 12 iron or steel charge respectively (0.8 s
cooldown).

- **Anchored or heavy targets** (deposits, large objects, Shardlings): the target
  doesn't move — you do. Pull yanks you toward it; push launches you away. This is
  the primary mobility tool.
- **Light, unanchored targets** (ferric coins, light Umbrals): the target moves,
  you stay put. Pull drags it to you; push hurls it away.

Ferropull on a wall is a grappling hook. Ferropush off a floor is a jump pack.
A sequence of push/pull onto different anchors lets you chain across the terrain
with no cooldown overlap.

### Ferric Coins (Q)

Press **Q** to throw a Ferric Coin from your inventory (crafted from 1 Crystal Shard
+ 2 Soil → 8 coins). The coin flies at 18 m/s and then rests. Once still, it acts
as a lightweight Ferropush anchor — launch yourself off it, then Ferropull the coin
back. Any coin that strikes an Umbral above 6 m/s deals 8 damage. Coins despawn
after 60 seconds.

### Vigor (G — burn pewter)

**G** toggles Vigor: while burning pewter flakes, you move 40% faster
(`speed_scale = 1.4`) and deal 1.5× strike damage. Incoming damage is also reduced
by 30% (the body becomes tougher under Allomantic pewter).

**Pewter drag.** If pewter runs out *while Vigor is active* — you didn't toggle it
off in time — you take a 10-second slow (`speed_scale = 0.6`). The HUD pewter bar
turning orange is your warning. Toggle off cleanly before the bar empties.

### Keensight (T — burn tin)

**T** toggles Keensight: while burning tin, the world brightens (ambient light
+60%), making it easier to spot distant Umbrals and ore deposits. Tin drains at
0.1 charge per tick — four times slower than pewter — so it is the most sustainable
channel.

### Flare (Shift — hold)

Hold **Shift** while a channel is active to flare: all active channels drain at
3× the normal rate for as long as you hold it. Flare does not increase the
magnitude of vigor or keensight in v1 — it's a way to burn through reserves when
you want to top up (or if the enemy situation demands it). Combining Vigor flare and
Keensight flare drains both reserves simultaneously.

### Metal Sense (Tab)

Hold **Tab** to see translucent blue lines from your position to every metal source
within 24 m. Requires iron or steel charge in reserve. Line opacity scales with
the target's mass — deposits are bright, coins are faint.

### HUD Metal Bars

A compact vertical stack of four bars appears beside the lumen orb (FE / ST / PW /
SN). Each bar shows current reserve and glows brighter while the corresponding
channel is active.

---

## Combat and the Umbrals

**Umbrals** — shadow wisps with glowing cores — condense out of darkness.
They only spawn in a ring 20–42 m away from you, and **never within 9 m of a
glow source** (flora or an active Lumen Bloom). Light is your territory; the
dark is theirs. At most 6 are alive at once.

Press **F** to strike. Each species drops materials on death, so combat feeds
the crafting loop:

| Creature | Health | Damage | Speed | Drops | Metal mass |
|----------|--------|--------|-------|-------|------------|
| **Voidmoth** | 12 | 4 | Fast | 1× Glow Spore | — |
| **Shardling** | 30 | 9 | Slow | 2× Crystal Shards | 60 (ferromantic target) |

Shardlings are the tougher fight but the better payday — two guaranteed crystal
shards beats gambling on the 18% dig roll. Shardlings are also Ferromantic targets:
their 60-mass body can be pulled toward you or pushed away, giving you both
a ranged opener and an emergency escape. They are not anchored, so the impulse
moves them, not you.

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

## Tempestlight and Resonance Storms

Resonance Storms are the sky's anger made lethal — and your only source of
Tempestlight, the third magic resource.

### Recognising a Storm

The sky bruises violet, fog thickens, the music drops to a warning pulse, and the
HUD banner reads **A RESONANCE STORM APPROACHES**. You have 45 seconds before it
hits. Storms come every 6–10 minutes; each lasts 90 seconds.

During the storm the banner reads **RESONANCE STORM**. Every 2 seconds, any
sky-exposed player takes **3 HP** per pulse. Thirty-plus pulses in the open will
kill you. Find or dig shelter immediately.

### Storm Catchers

A **Storm Catcher** is a small crystal pylon that charges dun gems during a storm.
Place it somewhere with a clear line to the sky — no roof overhead.

1. Craft **Dun Gems** (3 Crystal Shards + 1 Glow Spore → 1 Dun Gem).
2. Craft a **Storm Catcher** (2 Crystal Shards + 1 Keenglass Shard + 2 Soil → 1
   Storm Catcher). Press **H** to place it.
3. Press **E** near the catcher (with dun gems in inventory) to rack up to 4 gems.
4. Survive the storm underground. Each 2-second pulse that hits the catcher converts
   one dun gem to a **Charged Gem**. A full rack of 4 can charge in a single storm.
5. Press **E** near the catcher again to collect charged gems (and any uncharged
   dun gems) back into inventory.

A catcher under a roof charges nothing — sky exposure is required, the same rule
that makes the catcher dangerous to stand next to. Keep your shelter and your
catcher on different plots.

### Inhale (R)

Press **R** with a charged gem in inventory to inhale it. You consume the gem,
gain 40 Tempestlight charge (well capacity 100), and the gem returns to your
inventory as an inert dun gem ready for the next storm.

While holding Tempestlight:

- **Glow.** An OmniLight3D grows to 3.0 energy (7 m range) as your charge rises.
  The HUD tempest meter beside the lumen orb shows your fill ratio.
- **Speed.** +20% move speed (composes multiplicatively with Vigor).
- **Healing.** Every second, if you are hurt, the well spends 2 charge and heals
  1 HP. Roughly 1 HP/s while the supply lasts.
- **Leak.** The well drains 1 charge/s even when you do nothing. One charged gem
  (~40 charge) lasts about 40 seconds. Two gems fill the well to 80 and last
  roughly 80 seconds.

### Lash Abilities

While holding Tempestlight you can cast Bondlash (slot 1) and Skylash (slot 6).

**Bondlash (1):** Costs 15 charge, 1-second cooldown. Roots the nearest Umbral
within 2 m for 5 seconds — it freezes in place but keeps attacking. Use it to
stop a chasing Umbral while you repositon, or to lock a Shardling for a
Ferropull grab.

**Skylash (6):** Costs 20 charge, 1-second cooldown. Snaps your gravity to the
nearest cardinal axis (the direction you are looking, snapped) for 6 seconds.
Walk on walls, fall sideways, or run along the underside of a cave roof.

> **v1 limitation.** The camera does not reorient with gravity. Movement input
> (WASD) stays yaw-based — "forward" is still your look direction projected onto
> the horizontal plane. When gravity is sideways, this means "forward" is no
> longer "forward relative to the floor". Plan your momentum accordingly.

Skylash expires or you can re-cast to snap to a new axis mid-lash (refreshes
the 6-second window and re-snaps to the current camera direction).

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
