# Grid Quest: Creatures & Minions glossary + state form

A working design doc. Fill in / edit the **State entries** below (one per state). The **Glossary** at the
top is the shared vocabulary. Keep every other doc consistent with it.

---

## Glossary (the shared vocabulary)

- **Creature.** The entity itself; what you call one while it is **wild / free** (not yours). The
  umbrella noun (species live here: Frost Frog, Fire Horse, Breaker Monkey, Builder Bear). Collection log =
  **Creature Diary**.
- **Minion.** A creature that is **under your control** (an Entranced Minion or a Loyal Minion).
- **Enchantment Stone.** An item the **player holds** (in a stone/rune slot). It controls one creature's
  mind **remotely**; it is **never attached to the creature**. Limited (your slots). 1 held stone in use =
  1 Entranced Minion. Releasing the stone, or moving it to storage, ends the control.
- **Companion.** A minion currently **out walking with you** (fills a carry slot). A deployment role.
- **Containment / Paddock.** A pen that physically holds a released creature. Must be **appropriate for
  the creature type** (see the wall/material tiers).
- **Domestication.** An **experience-based** progression on a creature. It rises **only while the creature
  is Entranced** (under a held stone's control). It does NOT rise while Wild or Contained. At the loyalty
  experience threshold the creature becomes a **Loyal Minion**. (Progression, NOT a state.)

**State flow:**
`Wild -> Subdued -> Entranced Minion  <->  Contained (release the stone)  ->  ... Loyal Minion`
(Domestication experience is earned only while Entranced.)

---

## State form: template (copy this block for any new state)

```
### <State name>
- One line:
- Yours? (no / forced / willing):
- Behaviour (what it does):
- Commandable? (can you give it orders):
- Enters this state when:
- Leaves this state when:
- Held by / occupies (held stone? carry slot? paddock?):
- Reversion / risk (can it run or turn wild? trigger?):
- Gains Domestication XP? (only while Entranced):
- Player-facing cue (label / icon / colour):
- Open questions:
```

---

## State entries (prefilled starting point, edit freely)

### Wild
- One line: A free creature, not yours, hostile.
- Yours? (no / forced / willing): **No.**
- Behaviour (what it does): Roams; attacks the player; can wander onto your land and damage
  structures/fences (e.g. a wild Breaker Monkey breaks wood fences).
- Commandable? (can you give it orders): No.
- Enters this state when: Default for un-owned creatures; also when an Entranced Minion is released while
  not contained, or a Contained creature's pen is broken/entered before it is domesticated.
- Leaves this state when: You **Subdue** it in battle.
- Held by / occupies (held stone? carry slot? paddock?): Nothing.
- Reversion / risk: n/a (it *is* the wild state).
- Gains Domestication XP? No.
- Player-facing cue (label / icon / colour): _TODO_
- Open questions: _TODO_

### Subdued
- One line: Beaten down in a fight; the window to cast Entrancement is open.
- Yours? (no / forced / willing): No (yet).
- Behaviour (what it does): Downed / stunned; not attacking.
- Commandable? No.
- Enters this state when: You win the fight against a Wild creature.
- Leaves this state when: You cast **Entrancement** (goes to Entranced Minion, needs a free held stone);
  OR the weighted failure branch fires, so it **runs** (encounter ends), **stays subdued** (retry), or
  **gets up** (back to full fight).
- Held by / occupies: Nothing (transient).
- Reversion / risk: It can get up or run on a failed attempt (weights per creature difficulty).
- Gains Domestication XP? No.
- Player-facing cue: _TODO_
- Open questions: Must a free Enchantment Stone be in hand to even attempt Entrancement? _TODO_

### Entranced Minion
- One line: A creature whose mind is **forced** by an Enchantment Stone you hold; obeys because it is
  entranced.
- Yours? (no / forced / willing): **Forced.**
- Behaviour (what it does): Obeys commands; fights for you; uses its innate magic.
- Commandable? Yes.
- Enters this state when: You cast Entrancement on a Subdued creature with a **free held stone**.
- Leaves this state when: You **release the stone** (safe only if the creature is in appropriate
  Containment, which goes to Contained; otherwise it runs / turns **Wild**); OR its Domestication reaches
  the loyalty threshold (goes to **Loyal Minion**).
- Held by / occupies: **1 held Enchantment Stone** (in your slots). As a **Companion** it also fills a
  carry slot.
- Reversion / risk: If you release the stone, or move it to storage, while the creature is **not** in
  appropriate containment, it **breaks free**, so it runs or turns Wild.
- Gains Domestication XP? **Yes. This is the ONLY state that does** (it rises while entranced).
- Player-facing cue: _TODO_ (e.g. an "entranced" glyph showing the bond is forced/fragile).
- Open questions: _TODO_

### Contained (Paddocked)
- One line: A creature you released the stone from, into an appropriate paddock. Held now by the pen and
  not by magic, so the stone is free to reuse.
- Yours? (no / forced / willing): Held (physically), not commanded. Wild at heart until domesticated.
- Behaviour (what it does): Roams the containment **peacefully** while the pen holds.
- Commandable? No (it is parked, not a working minion).
- Enters this state when: You release a held stone from an Entranced Minion **while it is inside
  appropriate containment** (this **frees the stone** for reuse).
- Leaves this state when: You re-entrance it (spend a free stone) to make it a minion again; OR its
  containment is **broken or entered** before it is domesticated, so it turns **Wild/hostile**.
- Held by / occupies: **A paddock** (no held stone, no carry slot).
- Reversion / risk: **Break or go inside the containment and it is wild/hostile again**, until
  domesticated. Containment must match the creature's strength tier (Hedge < Wood < Slate < Brick approx
  Stone < Metal Bars; Chainlink = industrial). See-through Metal Bars are good for watching contained
  creatures.
- Gains Domestication XP? **No** (not entranced). Parking trades progress for a freed stone.
- Player-facing cue: _TODO_
- Open questions: _TODO_

### Loyal Minion
- One line: Domesticated to loyalty (enough experience). Obeys **willingly**, needs no stone and no cage.
- Yours? (no / forced / willing): **Willing.**
- Behaviour (what it does): Follows commands; fights for you; stays put even if the paddock breaks.
- Commandable? Yes.
- Enters this state when: An Entranced Minion's **Domestication experience reaches the loyalty threshold**.
- Leaves this state when: (Design choice, likely never reverts. Absorb sets it free as a normal creature;
  see the Absorb-vs-Domesticate fork.)
- Held by / occupies: **Nothing.** No held stone, no containment. A carry slot only while a Companion.
- Reversion / risk: **Never reverts** (stays even if fences break).
- Gains Domestication XP? Already at loyalty. Continues to level its stats/ability otherwise.
- Player-facing cue: _TODO_ (e.g. a "loyal" glyph distinct from the entranced one, the key thing a player
  wants to see at a glance).
- Open questions: What is the loyalty experience threshold (curve / numbers)? _TODO_

---

## Not-yet-resolved (for later passes)
- Exact Domestication experience curve and the loyalty threshold number.
- Player-facing cues / icons per state (art time).
- Per-creature entries (Frost Frog, Fire Horse, Breaker Monkey, Builder Bear, and so on): a separate
  per-creature form. Ask when ready.
