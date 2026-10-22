// T4 ZM - Zombie counter, run clock and round splits (Shep HUD, 22 Oct 2026)
//
// Replaces T4RunTimer.gsc. Drawn like the game's own HUD rather than as a
// panel: no boxes or bars, just text in the top-right corner. (The top left
// is the game's message feed: the high-rounds list and every iPrintLn land there.)
//
//     ZOMBIES 24        zombies left this round (alive + still to spawn), red at 5 or fewer
//        ALIVE 9        of those, how many are up on the map right now (smaller, grey)
//        DOGS 2        only while dogs are alive, or on a dog round
//     12:34             run clock (from round 1, the figure the speedrun boards use)
//     ROUND 12  1:23    the round that just ended, for 6 seconds
//
// .counter hides/shows the counter, .timer the clock and splits.
//
// The clock is redrawn once a second with setvalue(): a client-side count-up
// timer is set and then never ticks on the WaW single-player engine.
//
// Custom maps that draw their own "Zombies Left" (KFC, McDonalds) keep their
// own HUD: this script does nothing on them (_sh_own_counter()).
//
// No leaks:
//   - settext() only ever gets the fixed strings in _sh_strings(); every number goes
//     through setvalue(), so the configstring table cannot fill up however long a
//     game runs ("G_FindConfigstringIndex: overflow").
//   - At most 14 elements per player (no backgrounds), destroyed on disconnect, and
//     every per-player thread ends on disconnect. Script HUD elements share a limit
//     of about 31 on screen with the perk icons.
//   - One level thread counts the enemies for everyone.

// ════════════════════════════════════════════════════════════════════════════
//  ENTRY POINT
// ════════════════════════════════════════════════════════════════════════════

// Plutonium calls whichever of these the script defines, so both are here and
// the work is guarded to make a double call harmless.
main()
{
    _sh_boot();
}

init()
{
    _sh_boot();
}

_sh_boot()
{
    if ( isdefined( level._sh_booted ) && level._sh_booted )
        return;
    level._sh_booted = true;

    if ( _sh_own_counter() )
        return;

    // Total run time: set once when the first round starts and never reset.
    level._sh_total_start_ms = 0;
    level._sh_round_start_ms = 0;
    level._sh_current_round = 0;
    level._sh_split_round = 0;
    level._sh_split_ms = 0;
    level._sh_split_seconds = 6;

    level._sh_z = 0;
    level._sh_a = 0;
    level._sh_d = 0;
    level._sh_dog_round = false;

    level thread _sh_round_monitor();
    level thread _sh_count_monitor();
    level thread _sh_connect_monitor();
    level thread _sh_chat_monitor();
}

// Maps whose own script already shows the zombies left.
_sh_own_counter()
{
    map = getdvar( "mapname" );
    return map == "nazi_zombie_kfc2" || map == "nazi_zombie_mcdonalds";
}

// Every string the HUD shows, registered once in a fixed order before any
// player HUD exists.
_sh_strings()
{
    e = newhudelem();
    e.alpha = 0;
    e settext( "ZOMBIES" );
    e settext( "DOGS" );
    e settext( "ROUND" );
    e settext( ":" );
    e settext( ":0" );
    e settext( "0" );
    e settext( "ALIVE" );
    e destroy();
}


// ════════════════════════════════════════════════════════════════════════════
//  LAYOUT  (640x480 HUD units from the top-left of the screen)
// ════════════════════════════════════════════════════════════════════════════

// Measured off a WaW screenshot (2000x1126, so 1 unit = 2.35 px). Everything
// lines up on the right edge of the screen; a label sits left of its number, so
// it is placed from the width of the digits. Labels use the default font too:
// the "small" font is a low-resolution bitmap that looks pixelated in game.
_sh_layout_init()
{
    self._sh_x = -6;           // right edge of the stack, from the right of the screen
    self._sh_y = 10;           // top of the first row (clear of the Plutonium watermark)
    self._sh_num_w = 10.5;     // one big digit (default font, scale 2.0)
    self._sh_lab_dy = 8;       // label below the number's top, so the baselines meet
    self._sh_row_h = 20;       // one counter row
    self._sh_alive_w = 8.4;    // one digit of the smaller ALIVE number (scale 1.6)
    self._sh_alive_dy = 6;     // its label below the number's top
    self._sh_alive_h = 16;     // the ALIVE row
    self._sh_clock_h = 15;     // the clock row
    self._sh_small_w = 5.3;    // one digit of the label font (default, scale 1.0)
}

_sh_digits( n )
{
    if ( n >= 100 )
        return 3;
    if ( n >= 10 )
        return 2;
    return 1;
}

// The label sits left of its number, so it moves when the digit count changes.
_sh_place_label( num_digits, lab )
{
    lab.x = self._sh_x - num_digits * self._sh_num_w - 5;
}


// ════════════════════════════════════════════════════════════════════════════
//  ROUNDS AND ENEMIES (one thread each for the whole server)
// ════════════════════════════════════════════════════════════════════════════

// Polled: notify names vary between stock and custom maps, but
// level.round_number is present everywhere. A quarter-second poll so a split
// and the clock's start are picked up promptly.
_sh_round_monitor()
{
    level endon( "end_game" );

    for ( ;; )
    {
        wait 0.25;

        // The run clock starts with the speedrun script's run (level.srStart:
        // the first player's first move after spawning), so the two always
        // match. A game that did not start at round 1 is not timed there, and
        // the clock then runs from the first round this script saw.
        if ( isdefined( level.srStart ) )
            level._sh_total_start_ms = level.srStart;

        if ( !isdefined( level.round_number ) )
            continue;
        if ( level.round_number == level._sh_current_round )
            continue;

        // A round ended: publish its split before the next one starts. The
        // first round has nothing before it to report.
        if ( level._sh_current_round > 0 && level._sh_round_start_ms > 0 )
        {
            level._sh_split_round = level._sh_current_round;
            level._sh_split_ms = gettime() - level._sh_round_start_ms;
            level notify( "sh_split" );
        }

        level._sh_current_round = level.round_number;
        level._sh_round_start_ms = gettime();

        if ( level._sh_total_start_ms <= 0 && level.round_number > 1 && !isdefined( level.srStart ) )
            level._sh_total_start_ms = level._sh_round_start_ms;
    }
}

_sh_count_monitor()
{
    level endon( "end_game" );

    for ( ;; )
    {
        wait 0.1;

        players = getplayers();
        if ( players.size == 0 )
        {
            wait 0.9;
            continue;
        }

        // dog_intermission is set between dog waves; the dog_round flag covers
        // the whole round. Read straight off level.flag - this script has no
        // includes, and custom maps do not all define the flag.
        dog_round = ( isdefined( level.dog_intermission ) && level.dog_intermission )
                 || ( isdefined( level.flag ) && isdefined( level.flag["dog_round"] ) && level.flag["dog_round"] );

        live_z = 0;
        live_d = 0;
        enemies = GetAiSpeciesArray( "axis", "all" );
        if ( isdefined( enemies ) )
        {
            for ( i = 0; i < enemies.size; i++ )
            {
                if ( !isdefined( enemies[i] ) )
                    continue;
                if ( ( isdefined( enemies[i].isdog ) && enemies[i].isdog )
                  || ( isdefined( enemies[i].animname ) && enemies[i].animname == "zombie_dog" ) )
                    live_d++;
                else
                    live_z++;
            }
        }

        remaining = 0;
        if ( isdefined( level.zombie_total ) && level.zombie_total > 0 )
            remaining = level.zombie_total;

        // The spawn queue is dogs on a dog round and zombies otherwise; the game
        // does not say which queued spawns will be dogs on a mixed round.
        if ( dog_round )
        {
            level._sh_z = live_z;
            level._sh_d = live_d + remaining;
        }
        else
        {
            level._sh_z = live_z + remaining;
            level._sh_d = live_d;
        }
        level._sh_a = live_z;
        level._sh_dog_round = dog_round;
    }
}


// ════════════════════════════════════════════════════════════════════════════
//  PLAYERS
// ════════════════════════════════════════════════════════════════════════════

_sh_connect_monitor()
{
    level endon( "end_game" );

    // main() runs early in the map load; the strings go in once it is under way.
    wait 0.05;
    _sh_strings();

    players = getplayers();
    for ( i = 0; i < players.size; i++ )
        players[i] thread _sh_build();

    for ( ;; )
    {
        level waittill( "connected", player );
        player thread _sh_build();
    }
}

_sh_chat_monitor()
{
    level endon( "end_game" );

    for ( ;; )
    {
        level waittill( "say", text, player );

        if ( !isdefined( text ) || !isdefined( player ) )
            continue;
        if ( !isdefined( player._sh_ready ) || !player._sh_ready )
            continue; // HUD not built yet

        command = _sh_sanitize( text );
        if ( command == ".counter" )
        {
            player._sh_counter_on = !player._sh_counter_on;
            if ( isdefined( player.pers ) )
                player.pers["zc_enabled"] = player._sh_counter_on;
            player _sh_refresh( 0.20 );
        }
        else if ( command == ".timer" )
        {
            player._sh_timer_on = !player._sh_timer_on;
            if ( isdefined( player.pers ) )
                player.pers["rt_enabled"] = player._sh_timer_on;
            player _sh_refresh( 0.20 );
        }
    }
}

_sh_sanitize( text )
{
    if ( !isdefined( text ) )
        return "";

    for ( i = 0; i < 64; i++ )
    {
        if ( text == "" )
            return "";

        first = getSubStr( text, 0, 1 );
        if ( first == " " || first == "\t" )
        {
            text = getSubStr( text, 1, 1024 );
            continue;
        }
        break;
    }

    return text;
}


// ════════════════════════════════════════════════════════════════════════════
//  HUD
// ════════════════════════════════════════════════════════════════════════════

_sh_build()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    self waittill( "spawned_player" );

    if ( isdefined( self._sh_ready ) && self._sh_ready )
        return;

    self _sh_layout_init();
    x = self._sh_x;
    tx = x;

    // Counter: a big number with a small label in front of it.
    self._sh_zval = _sh_text( self, "right", x, "default", 2.0, 0.95, 0.95, 0.92 );
    self._sh_zval setvalue( 0 );
    self._sh_zlab = _sh_text( self, "right", x, "default", 1.0, 0.86, 0.86, 0.82 );
    self._sh_zlab settext( "ZOMBIES" );
    self _sh_place_label( 1, self._sh_zlab );

    self._sh_aval = _sh_text( self, "right", x, "default", 1.6, 0.74, 0.76, 0.78 );
    self._sh_aval setvalue( 0 );
    self._sh_alab = _sh_text( self, "right", x, "default", 1.0, 0.74, 0.76, 0.78 );
    self._sh_alab settext( "ALIVE" );
    self._sh_alab.x = x - self._sh_alive_w - 5;

    self._sh_dval = _sh_text( self, "right", x, "default", 2.0, 0.94, 0.70, 0.24 );
    self._sh_dval setvalue( 0 );
    self._sh_dlab = _sh_text( self, "right", x, "default", 1.0, 0.94, 0.70, 0.24 );
    self._sh_dlab settext( "DOGS" );
    self _sh_place_label( 1, self._sh_dlab );

    // Run clock m:ss - minutes, a separator that reads ":" or ":0" (so a
    // single-digit second keeps its zero), and seconds.
    self._sh_secs = _sh_text( self, "right", tx,      "default", 1.3, 0.95, 0.95, 0.92 );
    self._sh_sep  = _sh_text( self, "right", tx - 8,  "default", 1.3, 0.95, 0.95, 0.92 );
    self._sh_mins = _sh_text( self, "right", tx - 20, "default", 1.3, 0.95, 0.95, 0.92 );
    self._sh_sep settext( ":0" );
    self._sh_padded = true;
    self._sh_secs setvalue( 0 );
    self._sh_mins setvalue( 0 );

    // Split: "ROUND 12  1:23", right-aligned like the rest. The round number
    // and its label are placed from the time's width when it is shown.
    stx = x;
    self._sh_slab  = _sh_text( self, "right", x,        "default", 1.0, 0.86, 0.86, 0.82 );
    self._sh_slab settext( "ROUND" );
    self._sh_sround = _sh_text( self, "right", x,       "default", 1.0, 0.86, 0.86, 0.82 );
    self._sh_sround setvalue( 0 );
    self._sh_ssecs = _sh_text( self, "right", stx,      "default", 1.0, 0.66, 0.83, 1.00 );
    self._sh_ssep  = _sh_text( self, "right", stx - 5,  "default", 1.0, 0.66, 0.83, 1.00 );
    self._sh_smins = _sh_text( self, "right", stx - 13, "default", 1.0, 0.66, 0.83, 1.00 );
    self._sh_ssep settext( ":0" );
    self._sh_ssecs setvalue( 0 );
    self._sh_smins setvalue( 0 );

    self._sh_elems = [];
    self._sh_elems[0] = self._sh_zval;
    self._sh_elems[1] = self._sh_zlab;
    self._sh_elems[2] = self._sh_dval;
    self._sh_elems[3] = self._sh_dlab;
    self._sh_elems[4] = self._sh_secs;
    self._sh_elems[5] = self._sh_sep;
    self._sh_elems[6] = self._sh_mins;
    self._sh_elems[7] = self._sh_slab;
    self._sh_elems[8] = self._sh_sround;
    self._sh_elems[9] = self._sh_ssecs;
    self._sh_elems[10] = self._sh_ssep;
    self._sh_elems[11] = self._sh_smins;
    self._sh_elems[12] = self._sh_aval;
    self._sh_elems[13] = self._sh_alab;
    for ( i = 0; i < self._sh_elems.size; i++ )
        self._sh_elems[i].alpha = 0;

    self._sh_counter_on = true;
    if ( isdefined( self.pers ) && isdefined( self.pers["zc_enabled"] ) )
        self._sh_counter_on = self.pers["zc_enabled"];
    self._sh_timer_on = true;
    if ( isdefined( self.pers ) && isdefined( self.pers["rt_enabled"] ) )
        self._sh_timer_on = self.pers["rt_enabled"];

    self._sh_zshow = true;
    self._sh_ashow = false;
    self._sh_dshow = false;
    self._sh_split_on = false;
    self._sh_ready = true;

    self thread _sh_cleanup();
    self _sh_refresh( 0 );
    self thread _sh_tick_loop();
    self thread _sh_split_loop();
}

_sh_cleanup()
{
    elems = self._sh_elems;
    self waittill( "disconnect" );

    for ( i = 0; i < elems.size; i++ )
    {
        if ( isdefined( elems[i] ) )
            elems[i] destroy();
    }
}

// Puts every row where it belongs for what is on show, and fades each element
// to its alpha. Rows stack from the top: zombies, alive, dogs, clock, split.
_sh_refresh( t )
{
    y = self._sh_y;

    za = 0;
    aa = 0;
    da = 0;
    if ( self._sh_counter_on )
    {
        if ( self._sh_zshow )
        {
            self._sh_zval.y = y;
            self._sh_zlab.y = y + self._sh_lab_dy;
            y += self._sh_row_h;
            za = 1;
        }
        if ( self._sh_zshow && self._sh_ashow )
        {
            self._sh_aval.y = y;
            self._sh_alab.y = y + self._sh_alive_dy;
            y += self._sh_alive_h;
            aa = 1;
        }
        if ( self._sh_dshow )
        {
            self._sh_dval.y = y;
            self._sh_dlab.y = y + self._sh_lab_dy;
            y += self._sh_row_h;
            da = 1;
        }
        y += 2;
    }
    _sh_fade( self._sh_zval, za, t );
    _sh_fade( self._sh_zlab, za * 0.8, t );
    _sh_fade( self._sh_aval, aa * 0.9, t );
    _sh_fade( self._sh_alab, aa * 0.7, t );
    _sh_fade( self._sh_dval, da, t );
    _sh_fade( self._sh_dlab, da * 0.85, t );

    ca = 0;
    sa = 0;
    if ( self._sh_timer_on )
    {
        if ( level._sh_total_start_ms > 0 )
            ca = 0.9;
        if ( self._sh_split_on )
            sa = 1;
    }
    self._sh_secs.y = y;
    self._sh_sep.y = y;
    self._sh_mins.y = y;
    _sh_fade( self._sh_secs, ca, t );
    _sh_fade( self._sh_sep, ca, t );
    _sh_fade( self._sh_mins, ca, t );
    y += self._sh_clock_h;

    self._sh_slab.y = y;
    self._sh_sround.y = y;
    self._sh_ssecs.y = y;
    self._sh_ssep.y = y;
    self._sh_smins.y = y;
    _sh_fade( self._sh_slab, sa * 0.8, t );
    _sh_fade( self._sh_sround, sa * 0.8, t );
    _sh_fade( self._sh_ssecs, sa, t );
    _sh_fade( self._sh_ssep, sa, t );
    _sh_fade( self._sh_smins, sa, t );
}

_sh_fade( e, a, t )
{
    if ( t > 0 )
        e fadeovertime( t );
    e.alpha = a;
}

// Counter 10 times a second, clock once a second.
_sh_tick_loop()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    prev_z = -1;
    prev_a = -1;
    prev_d = -1;
    clock_started = false;
    ticks = 0;

    for ( ;; )
    {
        wait 0.1;

        z = level._sh_z;
        a = level._sh_a;
        d = level._sh_d;

        // A dog round with no zombies left shows the dogs on their own; ALIVE only
        // while there are zombies left in the round.
        zshow = !( level._sh_dog_round && z == 0 );
        ashow = zshow && z > 0;
        dshow = level._sh_dog_round || d > 0;
        if ( zshow != self._sh_zshow || ashow != self._sh_ashow || dshow != self._sh_dshow )
        {
            self._sh_zshow = zshow;
            self._sh_ashow = ashow;
            self._sh_dshow = dshow;
            self _sh_refresh( 0.25 );
        }

        if ( z != prev_z )
        {
            if ( prev_z < 0 || _sh_digits( z ) != _sh_digits( prev_z ) )
                self _sh_place_label( _sh_digits( z ), self._sh_zlab );
            prev_z = z;
            self._sh_zval setvalue( z );
            if ( z <= 5 )
                self._sh_zval.color = ( 0.92, 0.22, 0.14 );
            else
                self._sh_zval.color = ( 0.95, 0.95, 0.92 );
            if ( self._sh_counter_on )
                self._sh_zval thread _sh_pulse( self );
        }

        // The alive count moves constantly, so it changes quietly (no pulse).
        if ( a != prev_a )
        {
            if ( prev_a < 0 || _sh_digits( a ) != _sh_digits( prev_a ) )
                self._sh_alab.x = self._sh_x - _sh_digits( a ) * self._sh_alive_w - 5;
            prev_a = a;
            self._sh_aval setvalue( a );
        }

        if ( d != prev_d )
        {
            if ( prev_d < 0 || _sh_digits( d ) != _sh_digits( prev_d ) )
                self _sh_place_label( _sh_digits( d ), self._sh_dlab );
            prev_d = d;
            self._sh_dval setvalue( d );
            if ( self._sh_counter_on && dshow )
                self._sh_dval thread _sh_pulse( self );
        }

        ticks++;
        if ( ticks < 10 )
            continue;
        ticks = 0;

        if ( level._sh_total_start_ms <= 0 )
            continue;
        if ( !clock_started )
        {
            clock_started = true;
            self _sh_refresh( 0.3 );
        }
        self _sh_show_time( gettime() - level._sh_total_start_ms );
    }
}

// The clock is right-aligned: seconds at the edge, then the separator (":" or
// ":0", so a single-digit second keeps its zero), then the minutes.
_sh_show_time( ms )
{
    total = int( ms / 1000 );
    if ( total < 0 )
        total = 0;

    m = int( total / 60 );
    s = total - m * 60;

    self._sh_mins setvalue( m );
    self._sh_secs setvalue( s );

    tx = self._sh_x;
    padded = s < 10;
    if ( padded != self._sh_padded )
    {
        self._sh_padded = padded;
        if ( padded )
        {
            self._sh_sep settext( ":0" );
            self._sh_sep.x = tx - 8;
        }
        else
        {
            self._sh_sep settext( ":" );
            self._sh_sep.x = tx - 16;
        }
    }
}

_sh_split_loop()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    for ( ;; )
    {
        level waittill( "sh_split" );
        self thread _sh_split_show();
    }
}

// The round that just finished shows under the clock for a few seconds. A
// second round ending meanwhile restarts it.
_sh_split_show()
{
    self endon( "disconnect" );
    self notify( "sh_split_new" );
    self endon( "sh_split_new" );
    level endon( "end_game" );

    total = int( level._sh_split_ms / 1000 );
    if ( total < 0 )
        total = 0;
    m = int( total / 60 );
    s = total - m * 60;

    // Right to left: the time at the edge, the round number before it, then
    // "ROUND". One label-size digit is about 5.3 wide.
    w = self._sh_small_w;
    stx = self._sh_x;
    rx = stx - ( ( _sh_digits( m ) + 2 ) * w + 3 ) - 8;
    self._sh_sround.x = rx;
    self._sh_slab.x = rx - _sh_digits( level._sh_split_round ) * w - 4;
    if ( s < 10 )
    {
        self._sh_ssep settext( ":0" );
        self._sh_ssep.x = stx - 5;
    }
    else
    {
        self._sh_ssep settext( ":" );
        self._sh_ssep.x = stx - 11;
    }
    self._sh_sround setvalue( level._sh_split_round );
    self._sh_smins setvalue( m );
    self._sh_ssecs setvalue( s );

    self._sh_split_on = true;
    self _sh_refresh( 0.3 );

    wait level._sh_split_seconds;

    self._sh_split_on = false;
    self _sh_refresh( 0.6 );
}

// A quick tick on the number when it changes.
_sh_pulse( player )
{
    self notify( "sh_pulse" );
    self endon( "sh_pulse" );
    player endon( "disconnect" );

    self changefontscaleovertime( 0.05 );
    self.fontscale = 2.3;
    wait 0.05;

    if ( !isdefined( self ) )
        return;

    self changefontscaleovertime( 0.15 );
    self.fontscale = 2.0;
}

_sh_text( player, align, x, font, scale, r, g, b )
{
    e = newclienthudelem( player );
    e.foreground = 1;
    e.hidewhendead = 0;
    e.hidewheninmenu = 1;
    e.horzalign = "right";
    e.vertalign = "top";
    e.alignx = align;
    e.aligny = "top";
    e.x = x;
    e.y = 0;
    e.font = font;
    e.fontscale = scale;
    e.color = ( r, g, b );
    e.alpha = 1;
    e.sort = 7;
    return e;
}
