#include common_scripts\utility;
#include maps\_utility;
#include maps\_zombiemode_utility;

//
// AFK System for T4 Zombies (Plutonium)
// Usage: .afk in chat to toggle AFK mode
// Requires: Round 20+, 2-hour cooldown between uses
//

init()
{
    println( "[AFK] init() called" );

    level.afk_system = spawnStruct();
    level.afk_system.min_round = 20;
    level.afk_system.cooldown_ms = 7200000;       // 2 hours
    level.afk_system.duration_s = 900;             // 15 minutes
    level.afk_system.activation_delay_s = 60;      // 1-minute anti-panic delay
    level.afk_system.round_frozen = false;
    level.afk_system.saved_round_zombies = 0;
    level.afk_system.saved_max_ai = 0;
    level.afk_system.spawn_points = undefined;
    level.afk_system.verified_spawn = undefined;

    level thread on_player_connect();
    level thread round_freeze_monitor();
    level thread cache_spawn_points();
    level thread listen_for_chat_commands();
    // level thread debug_hud_monitor();

    println( "[AFK] init() complete" );
}

// ============================================================
// Chat Command Listener (Plutonium T4)
// ============================================================

listen_for_chat_commands()
{
    level endon( "end_game" );

    level thread listen_global_chat();
    level thread listen_team_chat();
}

listen_global_chat()
{
    level endon( "end_game" );

    for ( ;; )
    {
        level waittill( "say", text, player );
        handle_chat_command( text, player );
    }
}

listen_team_chat()
{
    level endon( "end_game" );

    for ( ;; )
    {
        level waittill( "say_team", text, player );
        handle_chat_command( text, player );
    }
}

handle_chat_command( text, player )
{
    if ( !isDefined( text ) || !isDefined( player ) )
        return;

    command = sanitize_chat( text );

    if ( command == ".afk" )
    {
        println( "[AFK] .afk command by " + player.playername );
        player thread try_toggle_afk();
    }
}

sanitize_chat( text )
{
    if ( !isDefined( text ) )
        return "";

    for ( i = 0; i < 64; i++ )
    {
        if ( text == "" )
            return "";

        first = getSubStr( text, 0, 1 );
        if ( first == " " || first == "§" || first == "\t" )
        {
            text = getSubStr( text, 1, 1024 );
            continue;
        }
        break;
    }
    return text;
}

// ============================================================
// Player Connection
// ============================================================

on_player_connect()
{
    level endon( "end_game" );

    for ( ;; )
    {
        level waittill( "connected", player );

        println( "[AFK] player connected: " + player.playername );

        player.is_afk = false;
        player.afk_activating = false;

        if ( !isDefined( player.pers["afk_last_used"] ) )
            player.pers["afk_last_used"] = 0;

        player thread capture_spawn_position();
    }
}

// ============================================================
// Spawn Point Cache & Capture
// ============================================================

cache_spawn_points()
{
    wait 5;

    spawns = getstructarray( "initial_spawn_points", "targetname" );

    if ( !isDefined( spawns ) || spawns.size == 0 )
        spawns = getstructarray( "player_respawn_point", "targetname" );

    if ( isDefined( spawns ) && spawns.size > 0 )
    {
        level.afk_system.spawn_points = spawns;
        println( "[AFK] cached " + spawns.size + " spawn points" );
    }
    else
        println( "[AFK] WARNING: no spawn points found" );
}

capture_spawn_position()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    self waittill( "spawned_player" );

    if ( !isDefined( level.afk_system.verified_spawn ) )
    {
        level.afk_system.verified_spawn = self.origin;
        println( "[AFK] captured verified spawn from " + self.playername + " at (" + int( self.origin[0] ) + "," + int( self.origin[1] ) + "," + int( self.origin[2] ) + ")" );
    }
}

get_afk_spawn_point()
{
    // Primary: verified spawn from actual player spawn position
    if ( isDefined( level.afk_system.verified_spawn ) )
    {
        point = spawnStruct();
        point.origin = level.afk_system.verified_spawn;
        point.angles = ( 0, 0, 0 );
        println( "[AFK] using verified spawn at (" + int( point.origin[0] ) + "," + int( point.origin[1] ) + "," + int( point.origin[2] ) + ")" );
        return point;
    }

    // Fallback: struct-based spawn points (pick farthest from zombies)
    if ( isDefined( level.afk_system.spawn_points ) && level.afk_system.spawn_points.size > 0 )
    {
        spawns = level.afk_system.spawn_points;
        best = spawns[0];
        best_dist = 0;

        zombies = getaiarray( "axis" );

        for ( i = 0; i < spawns.size; i++ )
        {
            if ( !isDefined( spawns[i].origin ) )
                continue;

            min_zombie_dist = 999999999;

            if ( isDefined( zombies ) && zombies.size > 0 )
            {
                for ( z = 0; z < zombies.size; z++ )
                {
                    if ( !isDefined( zombies[z] ) || !isAlive( zombies[z] ) )
                        continue;

                    d = distanceSquared( spawns[i].origin, zombies[z].origin );
                    if ( d < min_zombie_dist )
                        min_zombie_dist = d;
                }
            }

            if ( min_zombie_dist > best_dist )
            {
                best_dist = min_zombie_dist;
                best = spawns[i];
            }
        }

        println( "[AFK] WARNING: using fallback spawn struct (verified spawn not captured)" );
        return best;
    }

    println( "[AFK] WARNING: no spawn points available for teleport" );
    return undefined;
}

// ============================================================
// AFK Toggle & Eligibility
// ============================================================

try_toggle_afk()
{
    // Cancel pending activation
    if ( self.afk_activating )
    {
        self.afk_activating = false;
        self notify( "afk_cancel" );
        self iPrintLn( "AFK activation ^1cancelled^7." );
        return;
    }

    // Deactivate if currently AFK
    if ( self.is_afk )
    {
        self thread deactivate_afk();
        return;
    }

    // Must not be spectator
    if ( self.sessionstate == "spectator" )
    {
        self iPrintLn( "Cannot use AFK while ^1spectating^7." );
        return;
    }

    // Round gate
    if ( level.round_number < level.afk_system.min_round )
    {
        self iPrintLn( "AFK available from round ^3" + level.afk_system.min_round + "^7." );
        return;
    }

    // Cooldown gate
    if ( self.pers["afk_last_used"] > 0 )
    {
        elapsed = getTime() - self.pers["afk_last_used"];
        if ( elapsed < level.afk_system.cooldown_ms )
        {
            remaining_min = int( ( level.afk_system.cooldown_ms - elapsed ) / 60000 );
            self iPrintLn( "AFK on cooldown. ^3" + remaining_min + "^7 min remaining." );
            return;
        }
    }

    // Must be alive
    if ( !isAlive( self ) )
    {
        self iPrintLn( "Cannot use AFK while ^1dead^7." );
        return;
    }

    // Must not be downed (last stand)
    if ( self maps\_laststand::player_is_in_laststand() )
    {
        self iPrintLn( "Cannot use AFK while ^1downed^7." );
        return;
    }

    println( "[AFK] " + self.playername + " passed all checks, starting activation delay" );
    self thread afk_activation_delay();
}

// ============================================================
// Activation Delay (1-minute anti-panic)
// ============================================================

afk_activation_delay()
{
    self endon( "disconnect" );
    self endon( "afk_cancel" );
    level endon( "end_game" );

    self.afk_activating = true;
    self.afk_health_at_start = self.health;
    delay = level.afk_system.activation_delay_s;

    println( "[AFK] activation delay started for " + self.playername + " (" + delay + "s)" );

    self iPrintLn( "AFK activating in ^3" + delay + "^7s. Type ^3.afk^7 to cancel." );

    for ( i = delay; i > 0; i-- )
    {
        if ( !isAlive( self ) || self maps\_laststand::player_is_in_laststand() )
        {
            println( "[AFK] activation cancelled (death/down) for " + self.playername );
            self.afk_activating = false;
            self iPrintLn( "AFK activation ^1cancelled^7." );
            return;
        }

        // Cancel if player took damage during grace period
        if ( self.health < self.afk_health_at_start )
        {
            println( "[AFK] activation cancelled (damage) for " + self.playername );
            self.afk_activating = false;
            self iPrintLn( "AFK activation ^1cancelled^7 - you took damage!" );
            return;
        }

        if ( i == 30 || i == 10 || ( i <= 5 && i > 0 ) )
            self iPrintLn( "AFK in ^3" + i + "^7..." );

        wait 1;
    }

    // Final safety check
    if ( !isAlive( self ) || self maps\_laststand::player_is_in_laststand() )
    {
        println( "[AFK] activation cancelled (final check) for " + self.playername );
        self.afk_activating = false;
        self iPrintLn( "AFK activation ^1cancelled^7." );
        return;
    }

    self thread activate_afk();
}

// ============================================================
// Activate / Deactivate AFK
// ============================================================

activate_afk()
{
    println( "[AFK] activating for " + self.playername + " (score=" + self.score + ")" );

    self.afk_activating = false;
    self.is_afk = true;
    self.afk_saved_score = self.score;

    // Save pre-AFK position for restore on deactivate
    self.afk_saved_origin = self.origin;
    self.afk_saved_angles = self getPlayerAngles();

    // Teleport to spawn to prevent positional exploits
    spawn_point = get_afk_spawn_point();
    if ( isDefined( spawn_point ) )
    {
        self setOrigin( spawn_point.origin );
        if ( isDefined( spawn_point.angles ) )
            self setPlayerAngles( spawn_point.angles );
        println( "[AFK] teleported " + self.playername + " to spawn" );
    }

    // Lock controls (keeps chat open)
    self disableWeapons();
    self SetMoveSpeedScale( 0 );
    self AllowJump( false );

    // Godmode + zombie AI ignore
    self enableInvulnerability();
    self.ignoreme = true;

    // HUD - "AFK" label
    self.afk_hud_label = NewClientHudElem( self );
    self.afk_hud_label.x = 0;
    self.afk_hud_label.y = -60;
    self.afk_hud_label.alignX = "center";
    self.afk_hud_label.alignY = "middle";
    self.afk_hud_label.horzAlign = "center";
    self.afk_hud_label.vertAlign = "middle";
    self.afk_hud_label.fontScale = 2.5;
    self.afk_hud_label.alpha = 1;
    self.afk_hud_label.color = ( 1, 0.8, 0 );
    self.afk_hud_label.sort = 100;
    self.afk_hud_label.hidewheninmenu = false;
    self.afk_hud_label setText( "AFK" );

    // HUD - countdown timer
    self.afk_hud_timer = NewClientHudElem( self );
    self.afk_hud_timer.x = 0;
    self.afk_hud_timer.y = -35;
    self.afk_hud_timer.alignX = "center";
    self.afk_hud_timer.alignY = "middle";
    self.afk_hud_timer.horzAlign = "center";
    self.afk_hud_timer.vertAlign = "middle";
    self.afk_hud_timer.fontScale = 2;
    self.afk_hud_timer.alpha = 1;
    self.afk_hud_timer.color = ( 1, 0.8, 0 );
    self.afk_hud_timer.sort = 100;
    self.afk_hud_timer.hidewheninmenu = false;

    // Broadcast to all players
    broadcast_iprintln( self.playername + " is now ^3AFK^7." );

    self thread afk_timer_countdown();
    self thread afk_score_lock();

    println( "[AFK] " + self.playername + " is now AFK" );
}

deactivate_afk()
{
    if ( !self.is_afk )
        return;

    println( "[AFK] deactivating for " + self.playername );

    self.is_afk = false;
    self.pers["afk_last_used"] = getTime();

    // Restore controls
    self enableWeapons();
    self SetMoveSpeedScale( 1 );
    self AllowJump( true );

    // Remove AI ignore but keep invulnerability for grace period
    self.ignoreme = false;

    // Restore pre-AFK position
    if ( isDefined( self.afk_saved_origin ) )
    {
        self setOrigin( self.afk_saved_origin );
        self setPlayerAngles( self.afk_saved_angles );
        println( "[AFK] restored " + self.playername + " to pre-AFK position" );
        self.afk_saved_origin = undefined;
        self.afk_saved_angles = undefined;
    }

    // 30s invulnerability grace period after resuming
    self thread afk_resume_grace();

    // Restore score
    self.score = self.afk_saved_score;

    // Destroy HUD
    if ( isDefined( self.afk_hud_label ) )
        self.afk_hud_label destroy();
    if ( isDefined( self.afk_hud_timer ) )
        self.afk_hud_timer destroy();

    // Clear saved score
    self.afk_saved_score = undefined;

    // Kill sub-threads (score lock, timer countdown)
    self notify( "afk_ended" );

    // Broadcast
    broadcast_iprintln( self.playername + " is no longer ^3AFK^7." );

    println( "[AFK] " + self.playername + " is no longer AFK" );
}

// ============================================================
// Score Lock & Timer Countdown
// ============================================================

afk_score_lock()
{
    self endon( "disconnect" );
    self endon( "afk_ended" );

    for ( ;; )
    {
        wait 0.5;
        if ( self.score != self.afk_saved_score )
        {
            println( "[AFK] score drift for " + self.playername + ": " + self.score + " -> " + self.afk_saved_score );
            self.score = self.afk_saved_score;
        }
    }
}

afk_timer_countdown()
{
    self endon( "disconnect" );
    self endon( "afk_ended" );

    total = level.afk_system.duration_s;

    // setTimer for client-side countdown display (MM:SS format)
    self.afk_hud_timer setTimer( total );

    for ( i = total; i >= 0; i-- )
    {
        // Timed warnings
        if ( i == 300 )
            self iPrintLnBold( "^3AFK expires in 5 minutes." );
        else if ( i == 60 )
        {
            self iPrintLnBold( "^1AFK expires in 1 minute!" );
            self.afk_hud_timer.color = ( 1, 0.2, 0.2 );
            self.afk_hud_label.color = ( 1, 0.2, 0.2 );
        }
        else if ( i == 30 )
            self iPrintLnBold( "^1AFK expires in 30 seconds!" );
        else if ( i == 10 )
            self iPrintLnBold( "^1AFK expires in 10 seconds!" );

        if ( i > 0 )
            wait 1;
    }

    // Timer expired - force deactivate
    println( "[AFK] timer expired for " + self.playername );
    self iPrintLnBold( "^1AFK time expired!" );
    self thread deactivate_afk();
}

afk_resume_grace()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    grace = 30;
    self iPrintLn( "^3Invulnerable for " + grace + "s - get your bearings!" );
    println( "[AFK] " + self.playername + " resume grace started (" + grace + "s)" );

    for ( i = grace; i > 0; i-- )
    {
        if ( i == 10 )
            self iPrintLn( "^1Invulnerability ends in 10s!" );
        else if ( i == 5 )
            self iPrintLn( "^1Invulnerability ends in 5s!" );

        wait 1;
    }

    self disableInvulnerability();
    self iPrintLn( "^1Invulnerability ended." );
    println( "[AFK] " + self.playername + " resume grace ended" );
}

// ============================================================
// Round Freeze System
// ============================================================

round_freeze_monitor()
{
    level endon( "end_game" );

    for ( ;; )
    {
        wait 0.5;

        players = get_players();
        active_count = 0;
        afk_count = 0;

        for ( i = 0; i < players.size; i++ )
        {
            if ( !isDefined( players[i].is_afk ) )
                continue;

            if ( players[i].is_afk )
                afk_count++;
            else if ( isAlive( players[i] ) && players[i].sessionstate == "playing" )
                active_count++;
        }

        should_freeze = ( afk_count > 0 && active_count == 0 );

        if ( should_freeze && !level.afk_system.round_frozen )
        {
            println( "[AFK] freeze triggered: afk=" + afk_count + " active=" + active_count );
            freeze_round();
        }
        else if ( !should_freeze && level.afk_system.round_frozen )
        {
            println( "[AFK] unfreeze triggered: afk=" + afk_count + " active=" + active_count );
            unfreeze_round();
        }
    }
}

freeze_round()
{
    alive_at_freeze = getaiarray( "axis" ).size;

    level.afk_system.round_frozen = true;
    level.afk_system.saved_round_zombies = alive_at_freeze + level.zombie_total;
    level.afk_system.saved_max_ai = level.zombie_vars["zombie_max_ai"];

    println( "[AFK] freeze: alive=" + alive_at_freeze + " queue=" + level.zombie_total + " budget=" + level.afk_system.saved_round_zombies );

    // Stop spawning by setting max concurrent AI to 0
    level.zombie_vars["zombie_max_ai"] = 0;

    // Prevent round-end: ensure zombie_total > 0 so game thinks more are coming
    if ( level.zombie_total <= 0 )
        level.zombie_total = 1;

    broadcast_iprintln( "^3Round paused - all players AFK." );
}

unfreeze_round()
{
    alive_now = getaiarray( "axis" ).size;

    // Recalculate queue: if zombies died during freeze (traps, env damage),
    // add them back to the queue so the round doesn't skip
    new_queue = level.afk_system.saved_round_zombies - alive_now;
    if ( new_queue < 0 )
        new_queue = 0;

    println( "[AFK] unfreeze: alive=" + alive_now + " budget=" + level.afk_system.saved_round_zombies + " new_queue=" + new_queue );

    level.afk_system.round_frozen = false;
    level.zombie_total = new_queue;
    level.zombie_vars["zombie_max_ai"] = level.afk_system.saved_max_ai;

    broadcast_iprintln( "^2Round resumed." );
}

// ============================================================
// Helpers
// ============================================================

broadcast_iprintln( message )
{
    players = get_players();
    for ( i = 0; i < players.size; i++ )
        players[i] iPrintLn( message );
}

// ============================================================
// On-Screen Debug HUD (per player, top-left)
// Uncomment debug_hud_monitor() in init() to enable
// ============================================================

debug_hud_monitor()
{
    level endon( "end_game" );

    for ( ;; )
    {
        level waittill( "connected", player );
        player thread debug_hud_player();
    }
}

debug_hud_player()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    wait 1;

    // Line 1: player + eligibility state
    self.afk_dbg_line1 = NewClientHudElem( self );
    self.afk_dbg_line1.x = 5;
    self.afk_dbg_line1.y = 30;
    self.afk_dbg_line1.alignX = "left";
    self.afk_dbg_line1.alignY = "top";
    self.afk_dbg_line1.horzAlign = "left";
    self.afk_dbg_line1.vertAlign = "top";
    self.afk_dbg_line1.fontScale = 1.2;
    self.afk_dbg_line1.alpha = 0.85;
    self.afk_dbg_line1.color = ( 0.8, 1, 0.8 );
    self.afk_dbg_line1.sort = 200;
    self.afk_dbg_line1.hidewheninmenu = true;

    // Line 2: round freeze + player counts
    self.afk_dbg_line2 = NewClientHudElem( self );
    self.afk_dbg_line2.x = 5;
    self.afk_dbg_line2.y = 45;
    self.afk_dbg_line2.alignX = "left";
    self.afk_dbg_line2.alignY = "top";
    self.afk_dbg_line2.horzAlign = "left";
    self.afk_dbg_line2.vertAlign = "top";
    self.afk_dbg_line2.fontScale = 1.2;
    self.afk_dbg_line2.alpha = 0.85;
    self.afk_dbg_line2.color = ( 0.8, 1, 0.8 );
    self.afk_dbg_line2.sort = 200;
    self.afk_dbg_line2.hidewheninmenu = true;

    // Update every 5 seconds to avoid config string overflow
    for ( ;; )
    {
        if ( self.is_afk )
            state = "^1AFK";
        else if ( self.afk_activating )
            state = "^3ACTV";
        else
            state = "^2IDLE";

        alive_str = "^2Y";
        if ( !isAlive( self ) )
            alive_str = "^1N";

        downed_str = "^2N";
        if ( self maps\_laststand::player_is_in_laststand() )
            downed_str = "^1Y";

        round_num = "?";
        if ( isDefined( level.round_number ) )
            round_num = "" + level.round_number;

        cd_str = "^2RDY";
        if ( isDefined( self.pers["afk_last_used"] ) && self.pers["afk_last_used"] > 0 )
        {
            cd_elapsed = getTime() - self.pers["afk_last_used"];
            if ( cd_elapsed < level.afk_system.cooldown_ms )
            {
                cd_remaining_s = int( ( level.afk_system.cooldown_ms - cd_elapsed ) / 1000 );
                if ( cd_remaining_s < 60 )
                    cd_str = "^1" + cd_remaining_s + "s";
                else
                    cd_str = "^1" + int( cd_remaining_s / 60 ) + "m";
            }
        }

        self.afk_dbg_line1 setText( "^6[AFK] ^7" + state + " ^7al:" + alive_str + " dn:" + downed_str + " r:" + round_num + " cd:" + cd_str );

        frozen_str = "^2N";
        if ( level.afk_system.round_frozen )
            frozen_str = "^1Y";

        zalive = "" + getaiarray( "axis" ).size;

        ztotal = "?";
        if ( isDefined( level.zombie_total ) )
            ztotal = "" + level.zombie_total;

        players = get_players();
        active_c = 0;
        afk_c = 0;
        for ( p = 0; p < players.size; p++ )
        {
            if ( isDefined( players[p].is_afk ) && players[p].is_afk )
                afk_c++;
            else if ( isAlive( players[p] ) && players[p].sessionstate == "playing" )
                active_c++;
        }

        self.afk_dbg_line2 setText( "^6[AFK] ^7frz:" + frozen_str + " za:" + zalive + " zq:" + ztotal + " p:" + active_c + "/^1" + afk_c );

        wait 5;
    }
}
