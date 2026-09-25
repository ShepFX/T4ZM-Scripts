# Live round reporter

Publishes the round currently being played two ways, and clears both when the
game ends so a finished game never keeps displaying.

**A file**, `scriptdata/currentround.txt`, read by the website:

```text
<round>|<players>|<port>|<hostname>|<map>
```

An empty file means no game in progress.

**A dvar**, `cuk_round`, read by IW4MAdmin over rcon on its normal status poll,
which is what puts "Round N" on the webfront server cards. It is `0` when no
game is running. The dvar exists because the round is otherwise invisible from
outside the game: it is a script variable rather than a dvar, it is absent from
the server status response, and the game log never records a round change. The port is what ties the file to the
right server: folder names and server names do not reliably match
(`t4sp-mcdonalds` is "[CUK] Mcdonald's [EU]"), but a port is unique.

The round is read from `level.round_number`, which is present on stock and
custom maps alike, unlike the round-change notify names.

## Installation

Copy `T4LiveRound.gsc` into `raw/scripts/sp/`. Plutonium runs it at map load.

Deployed on all 14 T4 zombie servers.
