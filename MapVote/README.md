# Map vote

`.map` starts a vote and lists the other maps in this server's rotation
(`sv_maprotation`), for example `.1 Verruckt  .2 Shi No Numa`. Players vote with
`.1`, `.2` and so on; typing another number changes your vote.

- A map wins as soon as it has a majority of the players on the server (solo is
  instant). After 60 seconds with no winner the vote fails.
- 5-minute cooldown after any vote, and each player can only start one vote
  every 10 minutes.
- A passed vote changes map straight away with `map <name>` (players reconnect). The rotation then carries on as normal.
- Only useful on servers whose rotation has 2 or more maps.

Every vote is written to the games log as `CUKMV ...` lines. To test over RCON:
`set cuk_mv_test list` logs the options, `set cuk_mv_test 2` acts as if option 2
won.

## Installation

Copy `T4MapVote.gsc` to ``storage/t4/raw/scripts/sp/``.
