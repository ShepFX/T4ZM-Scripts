/**
 * Shep restart vote for T4 (World at War) zombies - same rules as the .map vote (T4MapVote.gsc):
 *
 *   .restart          starts a vote to restart the current map (counts as your yes)
 *   .restart / .yes   agree with a running vote
 *
 * It passes as soon as a majority of the players on the server agree (solo = instant). After
 * 60 s without a majority the vote fails. 5-minute cooldown after any vote, and a player can only
 * start a vote once every 10 minutes. It won't start while a .map vote is running.
 *
 * Every vote is written to the games log as "SHEPRV ..." lines. For testing over RCON:
 *   set shep_rv_test pass   acts as if a vote passed (reloads the map)
 */

init()
{
    level.shep_rv_vote_secs = 60;
    level.shep_rv_cooldown_ms = 300000;         // after any vote
    level.shep_rv_player_cooldown_ms = 600000;  // between votes started by the same player
    level.shep_rv_active = false;
    level.shep_rv_last_end = 0;
    level.shep_rv_restarting = false;
    level.shep_rv_yes = [];                     // player entity number -> true
    level.shep_rv_started_by = [];              // player entity number -> gettime() of their last vote start

    level thread ShepRvListen("say");
    level thread ShepRvListen("say_team");
    level thread ShepRvTestHook();
}

ShepRvListen(note)
{
    for (;;)
    {
        level waittill(note, text, player);
        if (!isdefined(text) || !isdefined(player))
            continue;
        t = ShepRvTrim(ShepRvLower("" + text));
        if (t == ".restart")
        {
            if (level.shep_rv_active)
                ShepRvYes(player);
            else
                ShepRvStart(player);
        }
        else if (t == ".yes" && level.shep_rv_active)
            ShepRvYes(player);
    }
}

ShepRvStart(player)
{
    if (level.shep_rv_restarting)
        return;
    if ((isdefined(level.cuk_mv_active) && level.cuk_mv_active) || (isdefined(level.cuk_mv_changing) && level.cuk_mv_changing))
    {
        player iprintln("^3A map vote is running - wait for it to finish.");
        return;
    }
    if (level.shep_rv_last_end > 0 && gettime() - level.shep_rv_last_end < level.shep_rv_cooldown_ms)
    {
        player iprintln("^3Restart vote cooldown. Try again in ^5" + ShepRvSecsLeft(level.shep_rv_last_end, level.shep_rv_cooldown_ms) + "^3 seconds.");
        return;
    }
    key = "" + player getentitynumber();
    if (isdefined(level.shep_rv_started_by[key]) && gettime() - level.shep_rv_started_by[key] < level.shep_rv_player_cooldown_ms)
    {
        player iprintln("^3You started a restart vote recently. Try again in ^5" + ShepRvSecsLeft(level.shep_rv_started_by[key], level.shep_rv_player_cooldown_ms) + "^3 seconds.");
        return;
    }
    level.shep_rv_started_by[key] = gettime();
    level.shep_rv_active = true;
    level.shep_rv_yes = [];
    logprint("SHEPRV start by " + ShepRvPname(player) + " players=" + getplayers().size + "\n");
    ShepRvSayAll("^3" + ShepRvPname(player) + "^7 wants to ^3restart the map^7! Need ^5" + ShepRvRequired() + "^7 votes - type ^5.yes^7 to agree.");
    level thread ShepRvTimeout();
    ShepRvYes(player);
}

ShepRvYes(player)
{
    key = "" + player getentitynumber();
    if (isdefined(level.shep_rv_yes[key]))
    {
        player iprintln("^3You already voted to restart.");
        return;
    }
    level.shep_rv_yes[key] = true;
    votes = ShepRvCount();
    required = ShepRvRequired();
    logprint("SHEPRV yes " + ShepRvPname(player) + " " + votes + "/" + required + "\n");
    ShepRvSayAll("^5" + ShepRvPname(player) + "^7 voted to restart (^5" + votes + "^7/^5" + required + "^7)");
    if (votes >= required)
        level thread ShepRvPass();
}

// yes votes from players still on the server
ShepRvCount()
{
    n = 0;
    players = getplayers();
    for (i = 0; i < players.size; i++)
        if (isdefined(level.shep_rv_yes["" + players[i] getentitynumber()]))
            n++;
    return n;
}

ShepRvTimeout()
{
    level endon("shep_rv_ended");
    wait level.shep_rv_vote_secs;
    if (!level.shep_rv_active)
        return;
    level.shep_rv_active = false;
    level.shep_rv_last_end = gettime();
    level.shep_rv_yes = [];
    logprint("SHEPRV failed\n");
    ShepRvSayAll("^3Restart vote failed^7 - not enough votes. The game carries on.");
}

ShepRvPass()
{
    if (level.shep_rv_restarting)
        return;
    level.shep_rv_restarting = true;
    level.shep_rv_active = false;
    level.shep_rv_last_end = gettime();
    level.cuk_mv_changing = true;   // stops a .map vote starting meanwhile
    level notify("shep_rv_ended");
    logprint("SHEPRV passed map=" + getdvar("mapname") + "\n");
    ShepRvSayAll("^2Vote passed!^7 Restarting the map in 5 seconds...");
    wait 5;
    // reloads the same map, like a passed .map vote (players reconnect)
    cmdexec("map " + getdvar("mapname"));
}

ShepRvRequired()
{
    n = getplayers().size;
    if (n < 1)
        n = 1;
    return int(n / 2) + 1;
}

ShepRvTestHook()
{
    setdvar("shep_rv_test", "");
    for (;;)
    {
        wait 1;
        v = getdvar("shep_rv_test");
        if (v == "")
            continue;
        setdvar("shep_rv_test", "");
        logprint("SHEPRV test " + v + " lower=" + ShepRvLower(".ReStArT") + " trim=[" + ShepRvTrim("  .yes ") + "] required=" + ShepRvRequired() + "\n");
        if (v == "pass")
            level thread ShepRvPass();
    }
}

ShepRvLower(s)
{
    up = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    lo = "abcdefghijklmnopqrstuvwxyz";
    out = "";
    for (i = 0; i < s.size; i++)
    {
        c = s[i];
        for (k = 0; k < 26; k++)
        {
            if (up[k] == c)
            {
                c = lo[k];
                break;
            }
        }
        out = out + c;
    }
    return out;
}

ShepRvTrim(s)
{
    while (s.size > 0 && getsubstr(s, 0, 1) == " ")
        s = getsubstr(s, 1, s.size);
    while (s.size > 0 && getsubstr(s, s.size - 1, s.size) == " ")
        s = getsubstr(s, 0, s.size - 1);
    return s;
}

ShepRvSecsLeft(since, length)
{
    left = int((length - (gettime() - since) + 999) / 1000);
    if (left < 1)
        left = 1;
    return left;
}

ShepRvPname(player)
{
    if (isdefined(player) && isdefined(player.name))
        return player.name;
    return "Someone";
}

ShepRvSayAll(msg)
{
    players = getplayers();
    for (i = 0; i < players.size; i++)
        if (isdefined(players[i]))
            players[i] iprintln(msg);
}
