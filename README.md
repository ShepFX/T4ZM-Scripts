# CUKServers World at War (T4) zombie scripts

The GSC the CUKServers World at War (T4) servers actually run. Every file here was taken
from a live server, so what is in this repo is what is running.

Scripts install into `runtime/plutonium/storage/t4/raw/scripts/sp/` unless a folder's README says
otherwise; Plutonium runs them at map load.

## What is deployed where

Several files are named differently on the servers than in this repo. The
deployed name is the one that matters — that is the filename to copy to.

| In this repo | Deployed as | Running on |
| --- | --- | --- |
| `AFK/_zm_AFK.gsc` | `t4_zm_afk.gsc` | 14 zombie servers |
| `GameStats/T4GameStats.gsc` | `T4GameStats.gsc` | 14 zombie servers |
| `Join-in-progress-script/PostRoundLock.gsc` | `T4RoundLocker.gsc` | 14 zombie servers |
| `LiveRound/T4LiveRound.gsc` | `T4LiveRound.gsc` | 14 zombie servers |
| `Round-Record-Saver/RoundRecord.gsc` | `T4RoundSaverNew.gsc` | 13 zombie servers (t4sp-stair is behind) |
| `RunTimer/T4RunTimer.gsc` | `T4RunTimer.gsc` | 14 zombie servers |
| `Speedrun/T4Speedrun.gsc` | `T4Speedrun.gsc` | 14 zombie servers |
| `Zombie Counter/_zombie_counter_hud_t4.gsc` | `-` | not deployed anywhere |

Last verified against the live servers on 2026-09-25.
