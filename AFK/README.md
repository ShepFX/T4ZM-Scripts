# T4 Zombies AFK System (Plutonium)

A robust, GSC-based AFK (Away From Keyboard) system designed specifically for **Call of Duty: World at War (T4)** running on the **Plutonium** platform. This script allows players to safely step away from a match without ending the game or dying, featuring anti-griefing measures and round-state management.

## ✨ Features

* **Chat Command Activation:** Simply type `.afk` in global or team chat to toggle the mode.
* **Anti-Panic Delay:** A 60-second countdown prevents players from using the command as an "instant escape." If you take damage during this window, activation is cancelled.
* **Round Freezing:** If **all** active players go AFK, zombie spawning pauses and the round progress is "frozen" until someone returns.
* **Positional Security:** Teleports players to a safe spawn location to prevent positional exploits and restores them to their original spot upon return.
* **Full Protection:** While AFK, players are invulnerable, ignored by AI, and have their score locked to prevent passive point gain.
* **Visual HUD:** Clear on-screen indicators showing AFK status and a countdown timer.
* **Post-AFK Grace Period:** Provides 30 seconds of invulnerability when returning so you can get your bearings.

## 🛠 Configuration

You can adjust these variables in the `init()` function to tune the experience:

| Variable | Default Value | Description |
| :--- | :--- | :--- |
| `min_round` | 20 | Minimum round required to use the command. |
| `cooldown_ms` | 2 hours | Time required between uses per player. |
| `duration_s` | 15 minutes | Maximum time a player can stay AFK before forced resume. |
| `activation_delay_s` | 60 seconds | The "grace period" before AFK kicks in. |

## 🚀 Installation

1. Download the `.gsc` file.
2. Place the script in your Plutonium T4 scripts folder:
   * `%localappdata%\Plutonium\storage\t4\scripts\sp\`
3. Restart your server or private match.

## 🕹 Usage

* **To Enter AFK:** Type `.afk` in the chat. Wait for the 60-second timer.
* **To Cancel Activation:** Type `.afk` again during the countdown.
* **To Return:** Type `.afk` while in AFK mode.

---

### ⚠️ Requirements
* **Platform:** Plutonium T4 (WAW)
* **Game Mode:** Zombies
* **Dependencies:** `common_scripts\utility`, `maps\_utility`, `maps\_zombiemode_utility`.

---

## 👨‍💻 Developer Notes
The script includes a built-in Debug HUD. To enable it for testing, uncomment the following line in the `init()` function:
```cpp
// level thread debug_hud_monitor();
