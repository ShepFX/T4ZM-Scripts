# Game stats logger

Appends one line per player per game to `scriptdata/gamestats.txt`, recording what they
actually did: kills, headshots, downs, revives, bleed-outs and points.

A player's line is written when they leave, and for everyone still in when the
game ends, so every session is counted exactly once and nobody is double
counted for reconnecting.

Each line carries a `runId` shared by everyone in that game, so the rows for a
single game can be grouped back together, plus the server port — folder names
and server names do not reliably match, but a port is unique.

## Installation

Copy `T4GameStats.gsc` into ``raw/scripts/sp/``. Plutonium runs it at map load.

Deployed as `T4GameStats.gsc` on all 14 T4 zombie servers.
