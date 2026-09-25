// T4 ZM - Run Timer (ported from the T6 counter's timer panel)
//
// Shows how long the current game has been running, which is the figure the
// speedrun boards rank runs on. When a round ends, that round's split drops in
// underneath for a few seconds and then tidies itself away again, leaving just
// the run clock.
//
// Type .timer in chat to hide or show it.
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
    level._rt_split_time = "";
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
            _rt_publish_split( level._rt_current_round, gettime() - level._rt_round_start_ms );

        level._rt_current_round = level.round_number;
        level._rt_round_start_ms = gettime();

        if ( level._rt_total_start_ms <= 0 && level.round_number > 0 )
            level._rt_total_start_ms = level._rt_round_start_ms;
    }
}

_rt_publish_split( round, elapsed_ms )
{
    level._rt_split_round = round;
    level._rt_split_time = _rt_format_time( elapsed_ms );
    level notify( "rt_split" );
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
    player.rt_split_showing = false;

    // Same visual language and width as the BO1/BO2 panels.
    px = 20;
    py = 24;
    w = 80;
    // Just the title and the run clock; the split row below brings its own
    // background, and only while it is on screen.
    h = 30;

    ar = 1.00;
    ag = 0.55;
    ab = 0.05;

    player.rt_px = px;
    player.rt_py = py;
    player.rt_time_x = px + 75;

    player.rt_bg     = _rt_bar( player, px + 0, py + 0,  w, h, 0.04, 0.04, 0.07, 0.72, 5 );
    player.rt_accent = _rt_bar( player, px + w, py + 0,  4, h, ar, ag, ab, 0.90, 6 );
    player.rt_sep    = _rt_bar( player, px + 4, py + 13, w - 8, 1, ar, ag, ab, 0.40, 6 );

    player.rt_title = _rt_text_left( player, px + 5, py + 2, 1.0, ar, ag, ab, 7 );
    player.rt_title settext( "RUN" );

    player.rt_total_label = _rt_text_left( player, px + 5, py + 17, 1.0, 0.58, 0.58, 0.63, 7 );
    player.rt_total_label settext( "TOTAL" );

    player.rt_total_time = _rt_text_right( player, player.rt_time_x, py + 17, 1.0, 1.00, 1.00, 1.00, 7 );
    player.rt_total_time settext( "--:--" );

    // Split row: same width, directly under the panel, hidden until a round
    // ends. Its own bar and accent so the panel appears to grow.
    player.rt_split_bg = _rt_bar( player, px + 0, py + 30, w, 14, 0.04, 0.04, 0.07, 0.72, 5 );
    player.rt_split_bg.alpha = 0;

    player.rt_split_accent = _rt_bar( player, px + w, py + 30, 4, 14, ar, ag, ab, 0.90, 6 );
    player.rt_split_accent.alpha = 0;

    player.rt_split_label = _rt_text_left( player, px + 5, py + 31, 1.0, ar, ag, ab, 7 );
    player.rt_split_label settext( "R0" );
    player.rt_split_label.alpha = 0;

    player.rt_split_time = _rt_text_right( player, player.rt_time_x, py + 31, 1.0, 0.90, 0.94, 1.00, 7 );
    player.rt_split_time settext( "--:--" );
    player.rt_split_time.alpha = 0;

    if ( !player.rt_enabled )
        player _rt_set_visible( 0, 0 );

    player thread _rt_tick_loop();
    player thread _rt_split_loop();
}

// The clock is redrawn server side once a second. Only the one text element
// changes, and only while the panel is actually on screen.
_rt_tick_loop()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    last = "";

    for ( ;; )
    {
        wait 1;

        if ( !isdefined( self.rt_total_time ) )
            continue;
        if ( !self.rt_enabled )
            continue;

        if ( level._rt_total_start_ms <= 0 )
            text = "--:--";
        else
            text = _rt_format_time( gettime() - level._rt_total_start_ms );

        if ( text != last )
        {
            last = text;
            self.rt_total_time settext( text );
        }
    }
}

// Shows the round that just finished, then tidies itself away so only the run
// clock is left. A second round ending while it is up simply restarts it.
_rt_split_loop()
{
    self endon( "disconnect" );
    level endon( "end_game" );

    for ( ;; )
    {
        level waittill( "rt_split" );

        if ( !isdefined( self.rt_split_label ) )
            continue;

        self.rt_split_label settext( "R" + level._rt_split_round );
        self.rt_split_time settext( level._rt_split_time );

        if ( !self.rt_enabled )
            continue;

        self thread _rt_split_show_then_hide();
    }
}

_rt_split_show_then_hide()
{
    self endon( "disconnect" );
    self notify( "rt_split_showing" );
    self endon( "rt_split_showing" );
    level endon( "end_game" );

    self.rt_split_showing = true;
    self _rt_split_set_visible( 1, 0.15 );

    wait level._rt_split_seconds;

    self _rt_split_set_visible( 0, 0.4 );
    self.rt_split_showing = false;
}

_rt_split_set_visible( visible, fade_time )
{
    if ( !isdefined( self.rt_split_bg ) )
        return;

    bg_alpha = 0;
    accent_alpha = 0;
    text_alpha = 0;

    if ( visible )
    {
        bg_alpha = 0.72;
        accent_alpha = 0.90;
        text_alpha = 1;
    }

    self.rt_split_bg fadeovertime( fade_time );
    self.rt_split_bg.alpha = bg_alpha;
    self.rt_split_accent fadeovertime( fade_time );
    self.rt_split_accent.alpha = accent_alpha;
    self.rt_split_label fadeovertime( fade_time );
    self.rt_split_label.alpha = text_alpha;
    self.rt_split_time fadeovertime( fade_time );
    self.rt_split_time.alpha = text_alpha;
}

_rt_set_visible( visible, fade_time )
{
    if ( !isdefined( self.rt_bg ) )
        return;

    alpha = 0;
    bg_alpha = 0;
    accent_alpha = 0;
    sep_alpha = 0;

    if ( visible )
    {
        alpha = 1;
        bg_alpha = 0.72;
        accent_alpha = 0.90;
        sep_alpha = 0.40;
    }

    self.rt_bg fadeovertime( fade_time );
    self.rt_bg.alpha = bg_alpha;
    self.rt_accent fadeovertime( fade_time );
    self.rt_accent.alpha = accent_alpha;
    self.rt_sep fadeovertime( fade_time );
    self.rt_sep.alpha = sep_alpha;

    self.rt_title fadeovertime( fade_time );
    self.rt_title.alpha = alpha;
    self.rt_total_label fadeovertime( fade_time );
    self.rt_total_label.alpha = alpha;
    self.rt_total_time fadeovertime( fade_time );
    self.rt_total_time.alpha = alpha;

    // The split row follows the panel, but only while it is actually up.
    if ( !visible || !isdefined( self.rt_split_showing ) || !self.rt_split_showing )
        self _rt_split_set_visible( 0, fade_time );
    else
        self _rt_split_set_visible( 1, fade_time );
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

// Runs pass an hour often enough that the clock has to carry hours.
_rt_format_time( elapsed_ms )
{
    if ( elapsed_ms < 0 )
        elapsed_ms = 0;

    total_seconds = int( elapsed_ms / 1000 );
    hours = int( total_seconds / 3600 );
    minutes = int( ( total_seconds - ( hours * 3600 ) ) / 60 );
    seconds = total_seconds - ( hours * 3600 ) - ( minutes * 60 );

    second_text = "" + seconds;
    if ( seconds < 10 )
        second_text = "0" + seconds;

    if ( hours <= 0 )
        return minutes + ":" + second_text;

    minute_text = "" + minutes;
    if ( minutes < 10 )
        minute_text = "0" + minutes;

    return hours + ":" + minute_text + ":" + second_text;
}
