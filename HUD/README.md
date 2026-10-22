# HUD: zombie counter, run clock and round splits

The World at War zombies HUD, drawn like the game's own HUD rather than as a panel:
no boxes or bars, just text in the top-right corner, right-aligned. The top left
is where the game's message feed goes (high round records and every
`iPrintLn`), so the HUD keeps clear of it.

```
                ZOMBIES 24     zombies left this round (alive + still to spawn), red at 5 or fewer
                   ALIVE 9     of those, how many are up on the map right now
                    DOGS 2     only on dog rounds, or while dogs are alive
                     12:34     run clock, the time the speedrun boards use
            ROUND 12  1:23     the round that just ended, for 6 seconds
```

The run clock takes its start from the speedrun logger (`level.srStart`), so the
clock and the speedrun boards always show the same time. A player who loads in
late sees the same time as everyone else.

## Usage

- **`.counter`** hides or shows the counter.
- **`.timer`** hides or shows the clock and splits.

The clock is redrawn once a second: a client-side count-up timer is set and then
never ticks on the WaW single-player engine.

Custom maps that draw their own "Zombies Left" (KFC and McDonalds) keep their
own HUD: this script does nothing on them.

Labels use the `default` font. The `small` font is a low-resolution bitmap
that looks pixelated in game.


## No leaks

- `settext()` is only ever called with a few fixed strings, registered once at
  map load. Every number goes through `setvalue()`, so a long game can't fill
  the configstring table ("G_FindConfigstringIndex: overflow").
- No background boxes, so fewer HUD elements per player, which leaves room for
  the perk icons. Each player's elements are destroyed when they disconnect.
- One level thread counts the enemies for everyone.

## Installation

Copy `T4HUD.gsc` into `raw/scripts/sp/`. It replaces the old `T4RunTimer.gsc`.
