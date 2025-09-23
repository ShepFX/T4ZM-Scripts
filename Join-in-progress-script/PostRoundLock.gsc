#include common_scripts\utility;
#include maps\_utility;
#include maps\_zombiemode_utility;
#include maps\_loadout;

init()
{
    // Config
    level.min_lock_round = 20;

    // State
    level.locked = false;
    level.pin = "";
    level.lock_initialized = false;

    // Ensure server starts unlocked
    setDvar( "password", "" );
    setDvar( "g_password", "" );

    // Threads
    level thread onPlayerConnect();
    level thread roundMonitor();

    // Level-scope chat listeners (WaW signature: text, player)
    level thread listenForChatCommands();
    level thread listenForTeamChatCommands();

    // Clear password at end of game
    level thread resetPasswordOnEnd();
}

onPlayerConnect()
{
    for ( ;; )
    {
        level waittill( "connected", player );

        if ( !isDefined( player ) )
            continue;

        // Register +actionslot 2 as a command, we'll require ADS to be held at press time
        player notifyOnPlayerCommand( "toggle_lock_cmd", "+actionslot 2" );
        player thread monitorUnlockInput();
    }
}

// Round transitions -> announce state (kill feed)
roundMonitor()
{
    level endon( "disconnect" );

    for ( ;; )
    {
        level waittill( "between_round_over" );

        // First time we reach threshold -> auto-lock (silent action line)
        if ( isRoundLockActive() && !level.lock_initialized )
        {
            level.lock_initialized = true;
            level.locked = true;
            level.pin = generatePin();
            setDvar( "g_password", level.pin );
            setDvar( "password", level.pin );
        }

        if ( !level.lock_initialized )
            continue;

        if ( level.locked )
        {
            if ( !isDefined( level.pin ) || level.pin == "" )
                level.pin = generatePin();

            setDvar( "g_password", level.pin );
            setDvar( "password", level.pin );

            announceAll( getLockedMessage() );
        }
        else
        {
            setDvar( "g_password", "" );
            setDvar( "password", "" );

            announceAll( getUnlockedMessage() );
        }
    }
}

// ADS + Action Slot 2 to toggle
monitorUnlockInput()
{
    self endon( "disconnect" );

    for ( ;; )
    {
        self waittill( "toggle_lock_cmd" );

        // Require ADS to be held when +actionslot 2 is pressed
        if ( self AdsButtonPressed() )
        {
            setLocked( !level.locked, self );
            wait( 0.4 ); // debounce
        }
    }
}

// Global chat (WaW signature: text, player)
listenForChatCommands()
{
    level endon( "disconnect" );

    for ( ;; )
    {
        level waittill( "say", text, player );

        if ( !isDefined( text ) || !isDefined( player ) )
            continue;

        text = sanitizeChat( text );

        if ( text == ".unlock" )
        {
            setLocked( false, player );
        }
        else if ( text == ".lock" )
        {
            setLocked( true, player );
        }
    }
}

// Team chat
listenForTeamChatCommands()
{
    level endon( "disconnect" );

    for ( ;; )
    {
        level waittill( "say_team", text, player );

        if ( !isDefined( text ) || !isDefined( player ) )
            continue;

        text = sanitizeChat( text );

        if ( text == ".unlock" )
        {
            setLocked( false, player );
        }
        else if ( text == ".lock" )
        {
            setLocked( true, player );
        }
    }
}

sanitizeChat( text )
{
    if ( !isDefined( text ) )
        return "";

    // Trim leading spaces, tabs, and '§' without using strlen
    // Use a small safety cap to avoid infinite loops
    for ( i = 0; i < 64; i++ )
    {
        if ( text == "" )
            return "";

        first = getSubStr( text, 0, 1 );

        if ( first == " " || first == "§" || first == "\t" )
        {
            // Drop the first character; length param can be large
            text = getSubStr( text, 1, 1024 );
            continue;
        }
        break;
    }

    return text;
}

// Set lock state and announce via kill feed.
// actor: optional player who triggered the change.
setLocked( shouldLock, actor )
{
    actorName = getActorName( actor );

    // Block locking until the minimum round is reached
    if ( shouldLock && !isRoundLockActive() )
    {
        if ( isDefined( actor ) )
            actor iPrintLn( "^3Locking is disabled until round ^5" + level.min_lock_round );
        return;
    }

    if ( shouldLock )
    {
        level.lock_initialized = true;
        level.locked = true;
        level.pin = generatePin();

        setDvar( "g_password", level.pin );
        setDvar( "password", level.pin );

        announceAll( actorName + " ^7locked the server. Password ^5" + level.pin );
    }
    else
    {
        level.locked = false;

        setDvar( "g_password", "" );
        setDvar( "password", "" );

        announceAll( actorName + " ^7unlocked the server." );
    }
}

// Helpers

isRoundLockActive()
{
    return isDefined( level.round_number ) && level.round_number >= level.min_lock_round;
}

getLockedMessage()
{
    return "Server is now ^1LOCKED^7. Use password ^5" + level.pin + " ^7to rejoin. Unlock with ^5ADS + 2^7 or type ^5.unlock^7";
}

getUnlockedMessage()
{
    return "Server remains ^2unlocked^7 - to lock again do ^5.lock^7 (or press ^5ADS + 2^7)";
}

// Kill feed broadcast
announceAll( message )
{
    players = getPlayersSafe();
    for ( i = 0; i < players.size; i++ )
        players[i] iPrintLn( message );
}

// Safe actor name
getActorName( actor )
{
    if ( isDefined( actor ) && isDefined( actor.name ) )
        return actor.name;
    return "Someone";
}

// 4-digit PIN
generatePin()
{
    str = "";
    for ( i = 0; i < 4; i++ )
        str = str + randomInt( 10 );
    return str;
}

// Safe players array getter
getPlayersSafe()
{
    if ( isDefined( level.players ) )
        return level.players;

    return getEntArray( "player", "classname" );
}

// Clear password on game end
resetPasswordOnEnd()
{
    level endon( "disconnect" );
    level waittill( "end_game" );

    setDvar( "g_password", "" );
    setDvar( "password", "" );
}
