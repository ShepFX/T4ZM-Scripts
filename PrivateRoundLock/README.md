# Private server round lock

For the on-demand private servers started from Discord with `/server`. Those
servers are joined with a password the bot sends you. From round 20 nobody new
can join: once round 20 or later ends, the password is swapped for a random one
nobody knows, so the people already in keep playing but nobody can join late to
ride a high round.

The real password is kept in a dvar and put back when the game ends, so a
restarted game takes the password from Discord again.

The same file runs on T4, T5 and T6 (builtins only, no includes).

## Installation

Copy `T4PrivateRoundLock.gsc` to ``storage/t4/raw/scripts/sp/`` on the private server. It does nothing if the server
has no join password.

T4 private servers also take the password as `sv_privatePassword`; both are handled.
