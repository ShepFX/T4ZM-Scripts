# Restart vote

`.restart` starts a vote to restart the current map. Your own `.restart` counts
as a yes, and others agree with `.restart` or `.yes`.

- Passes as soon as a majority of the players on the server agree (solo is
  instant). After 60 seconds without a majority the vote fails.
- 5-minute cooldown after any vote, and each player can only start one vote
  every 10 minutes.
- Won't start while a `.map` vote is running.

Every vote is written to the games log as `SHEPRV ...` lines. To test it over
RCON, `set shep_rv_test pass` acts as if a vote passed.

## Installation

Copy `T4RestartVote.gsc` to ``storage/t4/raw/scripts/sp/``.
