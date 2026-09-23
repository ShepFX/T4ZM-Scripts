Script for stopping players joining a zombies lobby mid-game, with the same rules as the CUK BO1 and BO2 servers.

- `.lock` in chat from round 1 starts a lock vote. A majority of the players in the game locks the server; a solo player locks it straight away. Votes stay open for 60 seconds, with a 5-minute cooldown between votes.
- At round 20 the server locks itself regardless.
- Locking sets a random 4-digit server password, which clears when the game ends.

Install: put `PostRoundLock.gsc` in `raw/scripts/sp/` on the server (the CUK servers run it as `T4RoundLocker.gsc`; the name does not matter). It runs `init()` at map load.

Big thanks to [HGM](https://github.com/NotHGM), [Resxt](https://github.com/Resxt) and [Amos](https://github.com/Ayymoss) <33
