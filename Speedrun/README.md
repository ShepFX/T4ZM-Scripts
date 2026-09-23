# Speedrun logger for T4 Zombies

World at War counterpart of the T6 speedrun logger. Logs how long a game took to
reach milestone rounds (10, 20, 30, 40, 50, 70, 100), so stats.cukservers.net
can show "fastest to round N" boards per map and squad size.

## How it works

- World at War has no `start_of_round` notify, so the clock starts when
  `round_think()` stamps `level.round_start_time` for round 1. A game that did
  not start at round 1 is not timed.
- Everyone present before round 2 is the roster; anyone joining from round 2
  onward ends timing for the game.
- World at War maps have no main quest, so only round times are logged.

Each event appends one line to `scriptdata/speedrun.txt` beside
`highrounds.txt`:

```
<runId>|<mapname>|<kind>|<target>|<ms>|<players>|<id:name,id:name>|<port>
```

## Installation

Copy `T4Speedrun.gsc` into `raw/scripts/sp/` on the server alongside
`T4RoundSaverNew.gsc`. Plutonium runs it automatically at map load.

## Player names

World at War (and Black Ops 1) zombies are built on single-player, where a
player's name is `.playername`; `.name` is never set. The logger reads
`.playername` (falling back to `.name`). An earlier version read `.name`: it
either spun in `SrCleanName` until the engine's infinite-loop guard killed the
round watcher, or, once guarded, skipped every player - so nothing was logged
at all on T4/T5 until this was fixed.
