// Private servers (Discord /server): from round 20 nobody new can join. The password the bot sent
// is swapped for a random one nobody knows; players already in keep playing. The real password
// comes back when the game ends, so a restarted game on the same server takes it again.
// The same file runs on T4, T5 and T6 (no includes, builtins only). Added by cuk-private.

init()
{
    level.priv_lock_round = 20;
    level.priv_locked = false;

    // the real password, kept in a dvar so a map restart doesn't mistake a locked one for it
    // (T4 private servers also take the password as sv_privatePassword)
    if ( getDvar( "cuk_priv_pw" ) == "" )
    {
        setDvar( "cuk_priv_pw", getDvar( "g_password" ) );
        setDvar( "cuk_priv_pw2", getDvar( "sv_privatePassword" ) );
    }
    else
        priv_restore();

    level thread priv_lock_watch();
    level thread priv_unlock_on( "end_game" );
    level thread priv_unlock_on( "game_ended" );
}

priv_lock_watch()
{
    level endon( "game_ended" );
    level endon( "end_game" );

    for ( ;; )
    {
        level waittill( "between_round_over" );

        if ( !level.priv_locked && isDefined( level.round_number ) && level.round_number >= level.priv_lock_round )
        {
            level.priv_locked = true;
            pin = "";
            for ( i = 0; i < 8; i++ )
                pin += randomInt( 10 );
            setDvar( "g_password", pin );
            if ( getDvar( "cuk_priv_pw2" ) != "" )
                setDvar( "sv_privatePassword", pin );

            players = getplayers();
            for ( i = 0; i < players.size; i++ )
            {
                if ( isDefined( players[i] ) )
                    players[i] iprintln( "^1Server locked^7 | Round ^5" + level.priv_lock_round + "^7 reached, nobody new can join" );
            }
        }
    }
}

priv_unlock_on( note )
{
    level waittill( note );
    priv_restore();
    level.priv_locked = false;
}

priv_restore()
{
    setDvar( "g_password", getDvar( "cuk_priv_pw" ) );
    if ( getDvar( "cuk_priv_pw2" ) != "" )
        setDvar( "sv_privatePassword", getDvar( "cuk_priv_pw2" ) );
}
