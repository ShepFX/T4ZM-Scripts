# Speedrun logger for T4 Zombies

World at War counterpart of the T6 speedrun logger. Logs how long a game took to
reach milestone rounds (10, 20, 30, 40, 50, 70, 100) and easter eggs, so shep.rip
can show "fastest to round N" and "fastest easter egg" boards per map and squad size.

## How it works

- The run starts when the first player can actually play: their first move or
  button press (fire, aim, use, grenade, melee) after spawning. Time spent
  loading in, or in the fade from black, costs nothing. Standing still doesn't
  hold the clock: it starts 3 seconds after the first spawn at the latest, and
  never before round 1 begins. A game that did not start at round 1 is not
  timed.
- Everyone in the game from round 1 is the roster; anyone joining from round 2
  onward ends timing for the game. A roster member who drops and rejoins stays
  on it.
- Round boards count the squad still in when round 2 starts, so a round-1 leaver
  who gets replaced never makes a 5-player run. Easter eggs also count round-1
  leavers who stayed at least a minute (up to 4 players). Round 1 can be stalled
  for as long as a squad likes, so without this a helper could do every step but
  the last and leave, putting a squad's egg on the solo board.
- World at War maps have no main quest. The stock maps' song easter eggs are
  timed (Verruckt, Shi No Numa, Der Riese), and so is the buyable ending on the
  custom maps that have one (KFC, McDonalds).

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
