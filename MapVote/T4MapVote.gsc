/**
 * [Shep] Map vote for T4 (World at War) zombies - same rules as the BO3 servers (shep_mapvote.gsc):
 *
 *   .map        starts a vote and lists the OTHER maps in this server's rotation
 *               (sv_maprotation), e.g.  .1 Verruckt   .2 Shi No Numa
 *   .1 .2 ...   vote for that map; typing another number changes your vote (last one counts)
 *
 * A map wins as soon as it has a majority of the players on the server (solo = instant). After
 * 60 s with no winner the vote fails. 5-minute cooldown after any vote, and a player can only
 * start a vote once every 10 minutes. Only installed on servers whose rotation has 2+ maps.
 *
 * A passed vote changes map straight away with "map <name>"; players reconnect.
 * The rotation then carries on after the voted map as normal.
 *
 * Every vote is written to the games log as "CUKMV ..." lines. For testing over RCON:
 *   set cuk_mv_test list   logs the options this server would offer
 *   set cuk_mv_test 2      acts as if option 2 won a vote (changes map)
 */

init()
{
    level.cuk_mv_vote_secs = 60;
    level.cuk_mv_cooldown_ms = 300000;         // after any vote
    level.cuk_mv_player_cooldown_ms = 600000;  // between votes started by the same player
    level.cuk_mv_active = false;
    level.cuk_mv_last_end = 0;
    level.cuk_mv_changing = false;
    level.cuk_mv_choice_of = [];               // player entity number -> option index
    level.cuk_mv_started_by = [];              // player entity number -> gettime() of their last vote start

    level thread CukMvListen("say");
    level thread CukMvListen("say_team");
    level thread CukMvTestHook();
}

// ---------------------------------------------------------------- rotation

// Splits sv_maprotation into entries ("execgts x.cfg map y" or "map y"), each with the map code.
CukMvEntries()
{
    words = CukMvSplit(getdvar("sv_maprotation"));
    entries = [];
    prefix = "";
    for (i = 0; i < words.size; i++)
    {
        if (words[i] == "map" && i + 1 < words.size)
        {
            e = spawnstruct();
            e.code = words[i + 1];
            e.cmd = prefix + "map " + e.code;
            e.cfg = CukMvCfgOf(prefix);
            e.name = CukMvName(e.code, e.cfg);
            entries[entries.size] = e;
            prefix = "";
            i++;
        }
        else
            prefix = prefix + words[i] + " ";
    }
    return entries;
}

// Options = the rotation in order, minus the map being played now.
CukMvBuildOptions()
{
    level.cuk_mv_entries = CukMvEntries();
    level.cuk_mv_options = [];
    current = getdvar("mapname");
    for (i = 0; i < level.cuk_mv_entries.size; i++)
    {
        if (level.cuk_mv_entries[i].code == current)
            continue;
        level.cuk_mv_entries[i].index = i;
        level.cuk_mv_options[level.cuk_mv_options.size] = level.cuk_mv_entries[i];
    }
}

// "execgts zm_classic_prison.cfg " -> "zm_classic_prison"
CukMvCfgOf(prefix)
{
    words = CukMvSplit(prefix);
    for (i = 0; i < words.size; i++)
        if (words[i].size > 4 && getsubstr(words[i], words[i].size - 4, words[i].size) == ".cfg")
            return getsubstr(words[i], 0, words[i].size - 4);
    return "";
}

CukMvName(code, cfg)
{
    switch (cfg)
    {
        case "zm_classic_transit":    return "TranZit";
        case "zm_standard_transit":   return "Bus Depot (Survival)";
        case "zm_standard_town":      return "Town (Survival)";
        case "zm_standard_farm":      return "Farm (Survival)";
        case "zm_classic_prison":     return "Mob of the Dead";
        case "zm_classic_rooftop":    return "Die Rise";
        case "zm_classic_processing": return "Buried";
        case "zm_classic_tomb":       return "Origins";
        case "zm_standard_nuked":     return "Nuketown";
    }
    switch (code)
    {
        case "nazi_zombie_prototype":
        case "zombie_cod5_prototype": return "Nacht der Untoten";
        case "nazi_zombie_asylum":
        case "zombie_cod5_asylum":    return "Verruckt";
        case "nazi_zombie_sumpf":
        case "zombie_cod5_sumpf":     return "Shi No Numa";
        case "nazi_zombie_factory":
        case "zombie_cod5_factory":   return "Der Riese";
        case "zombie_theater":        return "Kino der Toten";
        case "zombie_pentagon":       return "Five";
        case "zombie_cosmodrome":     return "Ascension";
        case "zombie_coast":          return "Call of the Dead";
        case "zombie_temple":         return "Shangri-La";
        case "zombie_moon":           return "Moon";
        case "zm_transit":            return "TranZit";
        case "zm_prison":             return "Mob of the Dead";
        case "zm_highrise":           return "Die Rise";
        case "zm_buried":             return "Buried";
        case "zm_tomb":               return "Origins";
        case "zm_nuked":              return "Nuketown";
    }
    return code;
}

// ---------------------------------------------------------------- chat

CukMvListen(note)
{
    for (;;)
    {
        level waittill(note, text, player);
        if (!isdefined(text) || !isdefined(player))
            continue;
        t = CukMvTrim(CukMvLower("" + text));
        if (t == ".map" || t == ".maps" || t == ".mapvote")
            CukMvStart(player);
        else if (level.cuk_mv_active && t.size >= 2 && t.size <= 3 && getsubstr(t, 0, 1) == ".")
        {
            n = CukMvNumber(getsubstr(t, 1, t.size));
            if (n >= 1 && n <= level.cuk_mv_options.size)
                CukMvVote(player, n - 1);
        }
    }
}

// ---------------------------------------------------------------- voting

CukMvStart(player)
{
    if (level.cuk_mv_changing)
        return;
    CukMvBuildOptions();   // built on use, so the rotation is read once the map has loaded
    if (level.cuk_mv_options.size == 0)
    {
        player iprintln("^3This server only has one map.");
        return;
    }
    if (level.cuk_mv_active)
    {
        player iprintln("^3A map vote is already running - type the number of the map you want.");
        player thread CukMvShowOptions();
        return;
    }
    if (level.cuk_mv_last_end > 0 && gettime() - level.cuk_mv_last_end < level.cuk_mv_cooldown_ms)
    {
        player iprintln("^3Map vote cooldown. Try again in ^5" + CukMvSecsLeft(level.cuk_mv_last_end, level.cuk_mv_cooldown_ms) + "^3 seconds.");
        return;
    }
    key = "" + player getentitynumber();
    if (isdefined(level.cuk_mv_started_by[key]) && gettime() - level.cuk_mv_started_by[key] < level.cuk_mv_player_cooldown_ms)
    {
        player iprintln("^3You started a map vote recently. Try again in ^5" + CukMvSecsLeft(level.cuk_mv_started_by[key], level.cuk_mv_player_cooldown_ms) + "^3 seconds.");
        return;
    }
    level.cuk_mv_started_by[key] = gettime();
    level.cuk_mv_active = true;
    level.cuk_mv_choice_of = [];
    logprint("CUKMV start by " + CukMvPname(player) + " players=" + getplayers().size + "\n");
    CukMvSayAll("^3" + CukMvPname(player) + "^7 wants to change map! Need ^5" + CukMvRequired() + "^7 votes - type the number:");
    players = getplayers();
    for (i = 0; i < players.size; i++)
        players[i] thread CukMvShowOptions();
    level thread CukMvTimeout();
}

CukMvShowOptions()
{
    self endon("disconnect");
    for (i = 0; i < level.cuk_mv_options.size; i++)
    {
        wait 0.4;
        self iprintln("^5." + (i + 1) + "^7  " + level.cuk_mv_options[i].name);
    }
}

CukMvVote(player, idx)
{
    key = "" + player getentitynumber();
    changed = isdefined(level.cuk_mv_choice_of[key]);
    level.cuk_mv_choice_of[key] = idx;
    votes = CukMvCount(idx);
    required = CukMvRequired();
    word = "voted for";
    if (changed)
        word = "changed vote to";
    logprint("CUKMV vote " + CukMvPname(player) + " -> " + level.cuk_mv_options[idx].code + " " + votes + "/" + required + "\n");
    CukMvSayAll("^5" + CukMvPname(player) + "^7 " + word + " ^5" + level.cuk_mv_options[idx].name + "^7 (^5" + votes + "^7/^5" + required + "^7)");
    if (votes >= required)
        level thread CukMvPass(idx);
}

// votes for an option from players still on the server
CukMvCount(idx)
{
    n = 0;
    players = getplayers();
    for (i = 0; i < players.size; i++)
    {
        key = "" + players[i] getentitynumber();
        if (isdefined(level.cuk_mv_choice_of[key]) && level.cuk_mv_choice_of[key] == idx)
            n++;
    }
    return n;
}

CukMvTimeout()
{
    level endon("cuk_mv_ended");
    wait level.cuk_mv_vote_secs;
    if (!level.cuk_mv_active)
        return;
    level.cuk_mv_active = false;
    level.cuk_mv_last_end = gettime();
    level.cuk_mv_choice_of = [];
    logprint("CUKMV failed\n");
    CukMvSayAll("^3Map vote failed^7 - no map got a majority. Staying on this map.");
}

CukMvPass(idx)
{
    if (level.cuk_mv_changing)
        return;
    level.cuk_mv_changing = true;
    level.cuk_mv_active = false;
    level.cuk_mv_last_end = gettime();
    level notify("cuk_mv_ended");
    m = level.cuk_mv_options[idx];
    logprint("CUKMV passed -> " + m.cmd + "\n");
    CukMvSayAll("^2Vote passed!^7 Changing to ^5" + m.name + "^7 in 5 seconds...");
    wait 5;

    // the voted map plays now; afterwards the rotation continues with the maps after it
    rest = "";
    for (i = m.index + 1; i < level.cuk_mv_entries.size; i++)
        rest = rest + level.cuk_mv_entries[i].cmd + " ";
    setdvar("sv_maprotationcurrent", rest);
    cmdexec("map " + m.code);
}

CukMvRequired()
{
    n = getplayers().size;
    if (n < 1)
        n = 1;
    return int(n / 2) + 1;
}

// ---------------------------------------------------------------- RCON test hook

CukMvTestHook()
{
    setdvar("cuk_mv_test", "");
    for (;;)
    {
        wait 1;
        v = getdvar("cuk_mv_test");
        if (v == "")
            continue;
        setdvar("cuk_mv_test", "");
        CukMvBuildOptions();
        if (v == "list")
        {
            logprint("CUKMV test map=" + getdvar("mapname") + " options=" + level.cuk_mv_options.size + " lower=" + CukMvLower(".MaP") + " num=" + CukMvNumber("12") + "\n");
            for (i = 0; i < level.cuk_mv_options.size; i++)
                logprint("CUKMV test ." + (i + 1) + " " + level.cuk_mv_options[i].name + " = " + level.cuk_mv_options[i].cmd + "\n");
            continue;
        }
        n = CukMvNumber(v);
        if (n >= 1 && n <= level.cuk_mv_options.size)
            level thread CukMvPass(n - 1);
    }
}

// ---------------------------------------------------------------- helpers

// "3" -> 3, anything that isn't 1-2 digits -> -1
CukMvNumber(s)
{
    if (s.size == 0 || s.size > 2)
        return -1;
    digits = "0123456789";
    n = 0;
    for (i = 0; i < s.size; i++)
    {
        d = -1;
        for (k = 0; k < 10; k++)
            if (digits[k] == s[i])
                d = k;
        if (d < 0)
            return -1;
        n = n * 10 + d;
    }
    return n;
}

CukMvLower(s)
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

CukMvTrim(s)
{
    while (s.size > 0 && getsubstr(s, 0, 1) == " ")
        s = getsubstr(s, 1, s.size);
    while (s.size > 0 && getsubstr(s, s.size - 1, s.size) == " ")
        s = getsubstr(s, 0, s.size - 1);
    return s;
}

// splits on spaces (no strtok, so the same code runs on T4, T5 and T6)
CukMvSplit(s)
{
    words = [];
    word = "";
    for (i = 0; i < s.size; i++)
    {
        c = getsubstr(s, i, i + 1);
        if (c == " " || c == "\t")
        {
            if (word != "")
                words[words.size] = word;
            word = "";
        }
        else
            word = word + c;
    }
    if (word != "")
        words[words.size] = word;
    return words;
}

CukMvSecsLeft(since, length)
{
    left = int((length - (gettime() - since) + 999) / 1000);
    if (left < 1)
        left = 1;
    return left;
}

CukMvPname(player)
{
    if (isdefined(player) && isdefined(player.name))
        return player.name;
    return "Someone";
}

CukMvSayAll(msg)
{
    players = getplayers();
    for (i = 0; i < players.size; i++)
        if (isdefined(players[i]))
            players[i] iprintln(msg);
}
