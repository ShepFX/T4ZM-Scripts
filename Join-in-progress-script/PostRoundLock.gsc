#include common_scripts\utility;
#include maps\_utility;
#include maps\_zombiemode_utility;
#include maps\_loadout;

/**
 * Main initialization function for the Round Lock script.
 */
init()
{
    // --- Configuration ---
    level.min_lock_round = 20; // The first round where locking becomes available.

    // --- State Variables ---
    level.locked = false;             // Is the server currently locked?
    level.pin = "";                   // The current 4-digit password.
    level.lock_initialized = false;   // Has the lock system been activated at least once?

    // Ensure the server starts without a password.
    setDvar("password", "");
    setDvar("g_password", "");

    // --- Start Core Processes ---
    level thread MonitorRoundChanges();      // Manages auto-locking and round-based announcements.
    level thread ListenForChatCommands();    // Handles chat commands like .lock and .unlock.
    level thread ResetPasswordOnEnd();       // Cleans up the password when the game ends.
}

// =================================================================================================
// Event Monitors
// =================================================================================================

/**
 * Monitors round transitions to handle auto-locking and status announcements.
 */
MonitorRoundChanges()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("between_round_over");

        // First time the threshold is reached, silently auto-lock the server.
        if (IsLockingAvailable() && !level.lock_initialized)
        {
            level.lock_initialized = true;
            level.locked = true;
            level.pin = GeneratePin();
            setDvar("g_password", level.pin);
            setDvar("password", level.pin);
        }

        // Only announce after the system has been initialized.
        if (!level.lock_initialized)
            continue;

        if (level.locked)
        {
            if (!isDefined(level.pin) || level.pin == "")
                level.pin = GeneratePin();
            
            setDvar("g_password", level.pin);
            setDvar("password", level.pin);
            BroadcastIprintln(GetLockedMessage());
        }
        else
        {
            setDvar("g_password", "");
            setDvar("password", "");
            BroadcastIprintln(GetUnlockedMessage());
        }
    }
}

/**
 * Sets up listeners for both global and team chat messages.
 */
ListenForChatCommands()
{
    level endon("game_ended");
    level thread ListenForGlobalChat();
    level thread ListenForTeamChat();
}

ListenForGlobalChat()
{
    level endon("game_ended");
    for(;;)
    {
        level waittill("say", text, player);
        HandleChatCommand(text, player);
    }
}

ListenForTeamChat()
{
    level endon("game_ended");
    for(;;)
    {
        level waittill("say_team", text, player);
        HandleChatCommand(text, player);
    }
}

// =================================================================================================
// Actions
// =================================================================================================

/**
 * Processes a chat message to execute a command.
 * @param text The raw chat message.
 * @param player The player who sent the message.
 */
HandleChatCommand(text, player)
{
    if (!isDefined(text) || !isDefined(player))
        return;

    command = SanitizeChat(text);

    if (command == ".unlock")
    {
        SetServerLocked(false, player);
    }
    else if (command == ".lock")
    {
        SetServerLocked(true, player);
    }
}

/**
 * Sets the server's lock state and announces the change.
 * @param shouldLock True to lock, false to unlock.
 * @param triggeringPlayer The player who initiated the action (optional).
 */
SetServerLocked(shouldLock, triggeringPlayer)
{
    // NEW: Provide feedback for redundant commands.
    if (!shouldLock && !level.locked)
    {
        if (isDefined(triggeringPlayer))
            triggeringPlayer iPrintLn("^3Server is already unlocked.");
        return;
    }
    if (shouldLock && level.locked)
    {
        if (isDefined(triggeringPlayer))
            triggeringPlayer iPrintLn("^3Server is already locked. Password: ^5" + level.pin);
        return;
    }

    // Block locking before the minimum round.
    if (shouldLock && !IsLockingAvailable())
    {
        if (isDefined(triggeringPlayer))
            triggeringPlayer iPrintLn("^3Cannot lock until round ^5" + level.min_lock_round);
        return;
    }

    playerName = GetTriggeringPlayerName(triggeringPlayer);

    if (shouldLock)
    {
        level.lock_initialized = true;
        level.locked = true;
        level.pin = GeneratePin();

        setDvar("g_password", level.pin);
        setDvar("password", level.pin);

        BroadcastIprintln("^1Locked by ^5" + playerName + "^7. Password: ^5" + level.pin);
    }
    else
    {
        level.locked = false;
        level.pin = "";

        setDvar("g_password", "");
        setDvar("password", "");

        BroadcastIprintln("^2Unlocked by ^5" + playerName);
    }
}

/**
 * Clears the server password when the game ends.
 */
ResetPasswordOnEnd()
{
    level waittill("end_game");
    setDvar("g_password", "");
    setDvar("password", "");
}

// =================================================================================================
// Helpers
// =================================================================================================

/**
 * Checks if the current round is at or above the minimum lock round.
 * @return True if locking is allowed, false otherwise.
 */
IsLockingAvailable()
{
    return isDefined(level.round_number) && level.round_number >= level.min_lock_round;
}

/**
 * Gets the formatted message for when the server is locked.
 */
getLockedMessage()
{
    return "^1Server Locked^7 | Password: ^5" + level.pin + "^7 | Type ^5.unlock^7 to open";
}

/**
 * Gets the formatted message for when the server is unlocked.
 */
getUnlockedMessage()
{
    return "^2Server Unlocked^7 | Type ^5.lock^7 to secure";
}

/**
 * Broadcasts a message to all players using iprintln.
 * @param message The text to display.
 */
BroadcastIprintln(message)
{
    players = getplayers();
    for (i = 0; i < players.size; i++)
        players[i] iPrintLn(message);
}

/**
 * Safely gets the name of the player who triggered an action.
 * @param triggeringPlayer The player entity.
 * @return The player's name or "Someone".
 */
GetTriggeringPlayerName(triggeringPlayer)
{
    // --- UPDATED to use .playerName ---
    if (isDefined(triggeringPlayer) && isDefined(triggeringPlayer.playerName))
        return triggeringPlayer.playerName;
    return "Someone";
}

/**
 * Generates a random 4-digit PIN as a string.
 */
GeneratePin()
{
    pin = "";
    for (i = 0; i < 4; i++)
        pin += randomInt(10);
    return pin;
}

/**
 * Cleans chat text by removing leading spaces and other special characters.
 */
SanitizeChat(text)
{
    if (!isDefined(text)) return "";

    for (i = 0; i < 64; i++) // Safety cap to prevent infinite loops.
    {
        if (text == "") return "";

        firstChar = getSubStr(text, 0, 1);
        if (firstChar == " " || firstChar == "§" || firstChar == "\t")
        {
            text = getSubStr(text, 1, 1024);
            continue;
        }
        break;
    }
    return text;
}
