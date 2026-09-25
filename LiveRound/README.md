# Live round reporter

Writes the round currently being played to `scriptdata/currentround.txt` so the
website can show a live round, and blanks the file when the game ends so a
finished game never keeps displaying.

```text
<round>|<players>|<port>|<hostname>
```

An empty file means no game in progress. The port is what ties the file to the
right server: folder names and server names do not reliably match
(`t4sp-mcdonalds` is "[CUK] Mcdonald's [EU]"), but a port is unique.

The round is read from `level.round_number`, which is present on stock and
custom maps alike, unlike the round-change notify names.

## Installation

Copy `T4LiveRound.gsc` into `raw/scripts/sp/`. Plutonium runs it at map load.

Deployed on all 14 T4 zombie servers.
