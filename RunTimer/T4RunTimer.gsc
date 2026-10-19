// T4 ZM - Run Timer (ported from the T6 counter's timer panel)
//
// Shows how long the current game has been running, which is the figure the
// speedrun boards rank runs on. When a round ends, the same row shows that
// round's split ("R12  1:23") for a few seconds, then goes back to the run
// clock.
//
// Type .timer in chat to hide or show it.
//
// Kept to seven HUD elements per player. A player can only see a limited
// number of script HUD elements at once (about 31 on this engine), shared
// with the game's own perk icons; the BO1 version with 21 elements pushed
// perk icons and the enemy counter off screen at random.
//
// Nothing calls settext() with text that changes: every distinct string takes
// a configstring slot for the rest of the map, and running out disconnects
// everyone ("G_FindConfigstringIndex: overflow"). The only strings used are
// the fixed "RUN", "R", ":" and ":0"; every number goes through setvalue().
// (A client-side count-up timer would be neater, but on the WaW/BO1
// single-player engine it is set and then never ticks.)
//
// WaW has no enemy counter, so the panel sits on its own in the top left.



// ════════════════════════════════════════════════════════════════════════════
//  ENTRY POINT
// ════════════════════════════════════════════════════════════════════════════

// Plutonium calls whichever of these the script defines, so both are here and
// the work is guarded to make a double call harmless.
main()
{
    _rt_boot();
}

init()
{
    _rt_boot();
}

_rt_boot()
{
    if ( isdefined( level._rt_booted ) && level._rt_booted )
        return;
    level._rt_booted = true;

    level._rt_enabled_default = true;

    // Total run time: set once when the first round starts and never reset.
    level._rt_total_start_ms = 0;

    level._rt_round_start_ms = 0;
    level._rt_current_round = 0;

    level._rt_split_round = 0;
    level._rt_split_ms = 0;
    level._rt_split_seconds = 6;

    level thread _rt_round_monitor();
    level thread _rt_connect_monitor();
    level thread _rt_chat_monitor();
}


// ════════════════════════════════════════════════════════════════════════════
//  ROUND TRACKING
//  Polled rather than hooked to a round-start notify: notify names vary
//  between stock and custom maps, but level.round_number is present
//  everywhere. One comparison a second.
// ════════════════════════════════════════════════════════════════════════════

_rt_round_monitor()
{
    level endon( "end_game" );

    for ( ;; )
    {
        wait 1;

        if ( !isdefined( level.round_number ) )
            continue;
        if ( level.round_number == level._rt_current_round )
            continue;

        // A round ended: publish its split before the next one starts. The
        // first round has nothing before it to report.
        if ( level._rt_current_round > 0 && level._rt_round_start_ms > 0 )
        {
            level._rt_split_round = level._rt_current_round;
            level._rt_split_ms = gettime() - level._rt_round_start_ms;
            level notify( "rt_split" );
        }

        level._rt_current_round = level.round_number;
        level._rt_round_start_ms = gettime();

        if ( level._rt_total_start_ms <= 0 && level.round_number > 0 )
            level._rt_total_start_ms = level._rt_round_start_ms;
    }
}


// ════════════════════════════════════════════════════════════════════════════
//  PLAYERS
// ════════════════════════════════════════════════════════════════════════════

_rt_connect_monitor()
{
    level endon( "end_game" );

    players = getplayers();
    for ( i = 0; i < players.size; i++ )
        players[i] thread _rt_build_hud();

    for ( ;; )
    {
        level waittill( "connected", player );
        player thread _rt_build_hud();
    }
}

_rt_chat_monitor()
{
    level endon( "end_game" );

    for ( ;; )
    {
        level waittill( "say", text, player );

        if ( !isdefined( text ) || !isdefined( player ) )
            continue;
        if ( !isdefined( player.rt_bg ) )
            continue; // HUD not built yet
        if ( _rt_sanitize( text ) != ".timer" )
            continue;

        player.rt_enabled = !player.rt_enabled;
        player _rt_set_visible( player.rt_enabled, 0.20 );
    }
}

_rt_sanitize( text )
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
//  One row: "RUN" and the clock (m:ss, the minutes carry on past 60). The
//  clock is three elements - minutes, a separator that reads ":" or ":0" (so
//  a single-digit second keeps its zero), and seconds.
// ════════════════════════════════════════════════════════════════════════════

_rt_build_hud()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    player = self;
    player waittill( "spawned_player" );

    if ( isdefined( player.rt_ready ) && player.rt_ready )
        return;

    player.rt_ready = true;

    player.rt_enabled = level._rt_enabled_default;
    player.rt_split_until = 0;

    px = 20;
    py = 24;
    w = 80;
    h = 15;

    ar = 1.00;
    ag = 0.55;
    ab = 0.05;

    player.rt_py = py;
    player.rt_tx = px + 75;

    player.rt_bg     = _rt_bar( player, px + 0, py, w, h, 0.04, 0.04, 0.07, 0.72, 5 );
    player.rt_accent = _rt_bar( player, px + w, py, 4, h, ar, ag, ab, 0.90, 6 );

    player.rt_title = _rt_text_left( player, px + 5, py + 2, 1.0, ar, ag, ab, 7 );
    player.rt_title settext( "RUN" );

    // The split's round number, only on screen while a split is.
    player.rt_round = _rt_text_left( player, px + 13, py + 2, 1.0, ar, ag, ab, 7 );
    player.rt_round setvalue( 0 );
    player.rt_round.alpha = 0;

    player.rt_secs = _rt_text_right( player, player.rt_tx,      py + 2, 1.0, 1.00, 1.00, 1.00, 7 );
    player.rt_sep  = _rt_text_right( player, player.rt_tx - 6,  py + 2, 1.0, 1.00, 1.00, 1.00, 7 );
    player.rt_mins = _rt_text_right( player, player.rt_tx - 15, py + 2, 1.0, 1.00, 1.00, 1.00, 7 );
    player.rt_sep settext( ":0" );
    player.rt_padded = true;
    player.rt_secs setvalue( 0 );
    player.rt_mins setvalue( 0 );

    if ( !player.rt_enabled )
        player _rt_set_visible( 0, 0 );

    player thread _rt_tick_loop();
    player thread _rt_split_loop();
}

// Puts a time on the clock. Digits are about 6 wide in this font: the
// separator sits after two digits of seconds, or after one when it carries
// the ":0" pad.
_rt_show_time( ms )
{
    total = int( ms / 1000 );
    if ( total < 0 )
        total = 0;

    m = int( total / 60 );
    s = total - m * 60;

    self.rt_mins setvalue( m );
    self.rt_secs setvalue( s );

    padded = s < 10;
    if ( padded != self.rt_padded )
    {
        self.rt_padded = padded;
        if ( padded )
        {
            self.rt_sep settext( ":0" );
            self.rt_sep.x = self.rt_tx - 6;
        }
        else
        {
            self.rt_sep settext( ":" );
            self.rt_sep.x = self.rt_tx - 12;
        }
    }
}

_rt_clock_color( r, g, b )
{
    self.rt_mins.color = ( r, g, b );
    self.rt_sep.color = ( r, g, b );
    self.rt_secs.color = ( r, g, b );
}

// Redraws the run clock once a second, except while a split is showing.
_rt_tick_loop()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    for ( ;; )
    {
        wait 1;

        if ( gettime() < self.rt_split_until )
            continue;
        if ( level._rt_total_start_ms <= 0 )
            continue;

        self _rt_show_time( gettime() - level._rt_total_start_ms );
    }
}

_rt_split_loop()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    for ( ;; )
    {
        level waittill( "rt_split" );
        self thread _rt_split_show();
    }
}

// The round that just finished takes over the row ("R12  1:23", light blue),
// then the run clock comes back. A second round ending meanwhile restarts it.
_rt_split_show()
{
    self endon( "disconnect" );
    self notify( "rt_split_new" );
    self endon( "rt_split_new" );
    level endon( "end_game" );

    self.rt_split_until = gettime() + level._rt_split_seconds * 1000;

    self.rt_title settext( "R" );
    self.rt_round setvalue( level._rt_split_round );
    if ( self.rt_enabled )
        self.rt_round.alpha = 1;
    self _rt_clock_color( 0.62, 0.86, 1.00 );
    self _rt_show_time( level._rt_split_ms );

    wait level._rt_split_seconds;

    self.rt_split_until = 0;
    self.rt_title settext( "RUN" );
    self.rt_round.alpha = 0;
    self _rt_clock_color( 1.00, 1.00, 1.00 );
    if ( level._rt_total_start_ms > 0 )
        self _rt_show_time( gettime() - level._rt_total_start_ms );
}

_rt_set_visible( visible, fade_time )
{
    if ( !isdefined( self.rt_bg ) )
        return;

    alpha = 0;
    bg_alpha = 0;
    accent_alpha = 0;
    round_alpha = 0;

    if ( visible )
    {
        alpha = 1;
        bg_alpha = 0.72;
        accent_alpha = 0.90;
        if ( gettime() < self.rt_split_until )
            round_alpha = 1;
    }

    self.rt_bg fadeovertime( fade_time );
    self.rt_bg.alpha = bg_alpha;
    self.rt_accent fadeovertime( fade_time );
    self.rt_accent.alpha = accent_alpha;
    self.rt_round fadeovertime( fade_time );
    self.rt_round.alpha = round_alpha;

    elems = [];
    elems[0] = self.rt_title;
    elems[1] = self.rt_mins;
    elems[2] = self.rt_sep;
    elems[3] = self.rt_secs;
    for ( i = 0; i < elems.size; i++ )
    {
        elems[i] fadeovertime( fade_time );
        elems[i].alpha = alpha;
    }
}


// ════════════════════════════════════════════════════════════════════════════
//  HELPERS
// ════════════════════════════════════════════════════════════════════════════

_rt_text_left( player, x, y, scale, r, g, b, srt )
{
    e = newclienthudelem( player );
    e.foreground = 1;
    e.hidewhendead = 0;
    e.hidewheninmenu = 1;
    e.horzalign = "left";
    e.vertalign = "top";
    e.alignx = "left";
    e.aligny = "top";
    e.x = x;
    e.y = y;
    e.fontscale = scale;
    e.color = ( r, g, b );
    e.alpha = 1;
    e.sort = srt;
    return e;
}

_rt_text_right( player, x, y, scale, r, g, b, srt )
{
    e = newclienthudelem( player );
    e.foreground = 1;
    e.hidewhendead = 0;
    e.hidewheninmenu = 1;
    e.horzalign = "left";
    e.vertalign = "top";
    e.alignx = "right";
    e.aligny = "top";
    e.x = x;
    e.y = y;
    e.fontscale = scale;
    e.color = ( r, g, b );
    e.alpha = 1;
    e.sort = srt;
    return e;
}

_rt_bar( player, x, y, w, h, r, g, b, a, srt )
{
    e = newclienthudelem( player );
    e.foreground = 1;
    e.hidewhendead = 0;
    e.hidewheninmenu = 1;
    e.horzalign = "left";
    e.vertalign = "top";
    e.alignx = "left";
    e.aligny = "top";
    e.x = x;
    e.y = y;
    e.sort = srt;
    e setshader( "white", w, h );
    e.color = ( r, g, b );
    e.alpha = a;
    return e;
}
