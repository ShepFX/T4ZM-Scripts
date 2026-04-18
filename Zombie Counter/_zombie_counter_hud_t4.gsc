// T4 ZM - Enemy Counter (ported from T5/T6)
// Drop into scripts/sp/zom/ (or wherever the server loads standalone scripts).

#include common_scripts\utility;
#include maps\_utility;
#include maps\_zombiemode_utility;


// ════════════════════════════════════════════════════════════════════════════
//  ENTRY POINT
// ════════════════════════════════════════════════════════════════════════════

init()
{
    level thread _zc_connect_monitor();
}


// ════════════════════════════════════════════════════════════════════════════
//  PLAYER CONNECTION
// ════════════════════════════════════════════════════════════════════════════

_zc_connect_monitor()
{
    level endon( "end_game" );

    players = get_players();
    for ( i = 0; i < players.size; i++ )
        players[i] thread _zc_build_hud();

    for ( ;; )
    {
        // T4/Plutonium ZM: join event is "connecting"
        level waittill( "connecting", player );
        player thread _zc_build_hud();
    }
}


// ════════════════════════════════════════════════════════════════════════════
//  HUD HELPERS
// ════════════════════════════════════════════════════════════════════════════

_zc_hud( player, x, y, scale, r, g, b, srt )
{
    e = newclienthudelem( player );
    e.foreground     = 1;
    e.hidewhendead   = 0;
    e.hidewheninmenu = 0;
    e.horzalign  = "left";
    e.vertalign  = "top";
    e.alignx     = "left";
    e.aligny     = "top";
    e.x          = x;
    e.y          = y;
    e.fontscale  = scale;
    e.font       = "default";
    e.color      = ( r, g, b );
    e.alpha      = 1.0;
    e.sort       = srt;
    return e;
}

_zc_bar( player, x, y, w, h, r, g, b, a, srt )
{
    e = newclienthudelem( player );
    e.foreground     = 1;
    e.hidewhendead   = 0;
    e.hidewheninmenu = 0;
    e.horzalign  = "left";
    e.vertalign  = "top";
    e.alignx     = "left";
    e.aligny     = "top";
    e.x     = x;
    e.y     = y;
    e.sort  = srt;
    e setshader( "white", w, h );
    e.color = ( r, g, b );
    e.alpha = a;
    return e;
}


// ════════════════════════════════════════════════════════════════════════════
//  ENEMY ENUMERATION (T4)
// ════════════════════════════════════════════════════════════════════════════

// T4 ZM identifies hellhounds by animname = "zombie_dog" across all ZM maps
// (Der Riese, Shi No Numa, Verruckt). Nacht has no dogs.
_zc_is_dog( ent )
{
    if ( !isdefined( ent ) )
        return false;
    if ( !isdefined( ent.animname ) )
        return false;
    return ( ent.animname == "zombie_dog" );
}


// ════════════════════════════════════════════════════════════════════════════
//  HUD CONSTRUCTION & UPDATE LOOP
// ════════════════════════════════════════════════════════════════════════════

_zc_build_hud()
{
    self endon( "disconnect" );
    level endon( "end_game" );
    player = self;

    // Wait for full spawn before creating client hud elems.
    self waittill( "spawned_player" );

    // Padding offsets - bump to shift whole HUD.
    px = 20;
    py = 24;

    // Accent colour (green).
    ar = 0.25;
    ag = 0.85;
    ab = 0.30;

    // Box sized for header + default font rows.
    bw = 105;
    bh = 50;
    bh_dog = 66;

    bg = _zc_bar( player, px + 0, py + 0, bw, bh, 0.04, 0.04, 0.07, 0.72, 5 );
    ac = _zc_bar( player, px + bw, py + 0, 4, bh, ar, ag, ab, 0.90, 6 );
    _zc_bar( player, px + 4, py + 16, bw - 8, 1, ar, ag, ab, 0.40, 6 );

    hdr = _zc_hud( player, px + 5, py + 2, 1.0, ar, ag, ab, 7 );
    hdr settext( "ENEMY TRACKER" );
    hdr.fontscale = 1.0;

    zrow = _zc_hud( player, px + 5, py + 20, 1.0, 0.58, 0.58, 0.63, 7 );
    zrow settext( "ZOMBIES 0" );
    zrow.fontscale = 1.0;

    drow = _zc_hud( player, px + 5, py + 35, 1.0, 1.00, 0.78, 0.12, 7 );
    drow settext( "DOGS 0" );
    drow.fontscale = 1.0;
    drow.alpha = 0.0;

    srow = _zc_hud( player, px + 5, py + 35, 1.0, 0.50, 0.88, 0.50, 7 );
    srow settext( "SPAWNED 0" );
    srow.fontscale = 1.0;

    prev_zleft   = -1;
    prev_dleft   = -1;
    prev_spawned = -1;
    prev_dog_vis = -1;

    for ( ;; )
    {
        wait 0.35;

        // T4: "dog_round" flag set on Der Riese / Shi No Numa / Verruckt.
        // Nacht has no dogs so flag is never init'd. T4 has no flag_exists(),
        // so probe level.flag[] directly - flag() would error on missing key.
        is_dog_round = false;
        if ( isdefined( level.flag ) && isdefined( level.flag["dog_round"] ) )
            is_dog_round = flag( "dog_round" );

        live_z = 0;
        live_d = 0;
        enemies = GetAiSpeciesArray( "axis", "all" );
        if ( isdefined( enemies ) )
        {
            for ( i = 0; i < enemies.size; i++ )
            {
                if ( !isdefined( enemies[i] ) )
                    continue;
                if ( _zc_is_dog( enemies[i] ) )
                    live_d++;
                else
                    live_z++;
            }
        }

        if ( isdefined( level.zombie_total ) )
            remaining = level.zombie_total;
        else
            remaining = 0;
        if ( remaining < 0 )
            remaining = 0;

        if ( is_dog_round )
        {
            total_z = live_z;
            total_d = live_d + remaining;
        }
        else
        {
            total_z = live_z + remaining;
            total_d = live_d;
        }

        // SPAWNED = currently alive on the map right now
        spawned = live_z;

        // ZOMBIES
        if ( total_z != prev_zleft )
        {
            prev_zleft = total_z;
            zrow settext( "ZOMBIES " + total_z );
            zrow.fontscale = 1.0;
            if ( total_z <= 5 )
                zrow.color = ( 1.0, 0.25, 0.05 );
            else
                zrow.color = ( 0.58, 0.58, 0.63 );
            zrow thread _zc_pulse( player );
        }

        // Dog row fade
        if ( is_dog_round || total_d > 0 )
            dog_vis = 1;
        else
            dog_vis = 0;
        if ( dog_vis != prev_dog_vis )
        {
            prev_dog_vis = dog_vis;
            drow fadeovertime( 0.25 );
            drow.alpha = dog_vis;
            if ( dog_vis )
            {
                srow.y = py + 51;
                bg setshader( "white", bw, bh_dog );
                ac setshader( "white",  4, bh_dog );
            }
            else
            {
                srow.y = py + 35;
                bg setshader( "white", bw, bh );
                ac setshader( "white",  4, bh );
            }
        }

        // DOGS
        if ( total_d != prev_dleft )
        {
            prev_dleft = total_d;
            drow settext( "DOGS " + total_d );
            drow.fontscale = 1.0;
            drow thread _zc_pulse( player );
        }

        // SPAWNED
        if ( spawned != prev_spawned )
        {
            prev_spawned = spawned;
            srow settext( "SPAWNED " + spawned );
            srow.fontscale = 1.0;
            srow thread _zc_pulse( player );
        }
    }
}


// ════════════════════════════════════════════════════════════════════════════
//  PULSE ANIMATION
// ════════════════════════════════════════════════════════════════════════════

_zc_pulse( player )
{
    self notify( "zc_pulse" );
    self endon(  "zc_pulse" );
    player endon( "disconnect" );

    base = self.fontscale;
    self changefontscaleovertime( 0.12 );
    self.fontscale = base * 1.25;
    wait 0.12;

    if ( !isdefined( self ) )
        return;

    self changefontscaleovertime( 0.28 );
    self.fontscale = base;
}
