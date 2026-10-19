/**
 * Game stats logger (T4 / World at War Zombies).
 *
 * Appends one line per player to scriptdata/gamestats.txt (beside speedrun.txt)
 * with what they did in the game: kills, headshots, downs, revives, bleed-outs
 * and points. A player's line is written when they leave, and for everyone
 * still in when the game ends, so every session is counted once.
 *
 * File format - one line per player session:
 *     <runId>|<mapname>|<round>|<reason>|<port>|<id>|<name>|<kills>|<headshots>|
 *     <downs>|<revives>|<bleedouts>|<points>|<joinRound>|<ms>|<box>|<perks>|
 *     <pap>|<powerups>|<powerupTypes>
 *
 *     runId      random id for this game (same idea as the speedrun log)
 *     round      the round when the line was written
 *     reason     "end" - still in when the game ended - or "left"
 *     id         IW4MAdmin client id (the GUID until IW4MAdmin has set it)
 *     bleedouts  times the player bled out and spectated until the next round
 *     points     total points earned this game, not what they had left
 *     joinRound  the round they joined in
 *     ms         time in the game
 *     box        paid box spins, teddy bears included
 *     perks      perks bought from a machine
 *     pap        weapons Pack-a-Punched
 *     powerups   power-ups grabbed; powerupTypes is "nuke=2/full_ammo=1"
 *
 * The custom maps each ship their own copies of the zombiemode scripts, so the
 * extras use what all of them share: the box's treasure_chest_weapon_spawn (or
 * Harrybo21's harrybo21_mysterybox_decide_weapon) and powerup_grab are
 * wrapped (the original still runs), perks come from the
 * buyer's "perk_used" (stock-based maps) or "machine_used" (Harrybo21 perks),
 * or, on maps that send neither (Verruckt), from the stock perks a player gains,
 * and Pack-a-Punch is a new "_upgraded" weapon in the player's hands.
 *
 * A session with no kills that lasted under 30 seconds is not written, so
 * someone connecting and leaving straight away adds nothing.
 *
 * World at War has no bleed-out notify and most maps never notify "end_game":
 * a bled-out player just turns spectator until the next round, and game over
 * sets level.intermission. Both are watched instead.
 */

main() {
    // Wrapped here, before the map's own threads start calling them. A map
    // without one of these functions just goes without that count.
    level.gsChestSpawn = getFunction("maps/_zombiemode_weapons", "treasure_chest_weapon_spawn");
    if (isDefined(level.gsChestSpawn))
        replaceFunc(level.gsChestSpawn, ::GsChestSpawn, -1);
    // Shi No Numa has its own copy of the box script.
    level.gsChestSpawnSumpf = getFunction("maps/_zombiemode_weapons_sumpf", "treasure_chest_weapon_spawn");
    if (isDefined(level.gsChestSpawnSumpf))
        replaceFunc(level.gsChestSpawnSumpf, ::GsChestSpawnSumpf, -1);
    level.gsPowerupGrab = getFunction("maps/_zombiemode_powerups", "powerup_grab");
    if (isDefined(level.gsPowerupGrab))
        replaceFunc(level.gsPowerupGrab, ::GsPowerupGrab, -1);

    level thread GsWrapHarryBox();
    level thread InitGameStats();
}

// Harrybo21's mystery box (Stairway) replaces the stock box and never calls
// treasure_chest_weapon_spawn. It picks the weapon in
// harrybo21_mysterybox_decide_weapon once per paid spin. Only looked up once
// that box has set itself up, so other maps never touch it.
GsWrapHarryBox() {
    for (i = 0; i < 600 && !isDefined(level.mystery_boxes); i++)
        wait 0.1;
    if (!isDefined(level.mystery_boxes))
        return;
    level.gsHarryBoxDecide = getFunction("maps/_zombiemode_mysterybox", "harrybo21_mysterybox_decide_weapon");
    if (isDefined(level.gsHarryBoxDecide))
        replaceFunc(level.gsHarryBoxDecide, ::GsHarryBoxDecide, -1);
}

GsHarryBoxDecide(player) {
    if (isDefined(player) && isPlayer(player) && isDefined(player.gsSession))
        player.gsSession.box++;

    disableDetourOnce(level.gsHarryBoxDecide);
    return self [[level.gsHarryBoxDecide]](player);
}

InitGameStats() {
    level.gsFile = "scriptdata/gamestats.txt";
    level.gsRunId = randomInt(1000000) + "-" + getTime();
    level.gsMapToken = getDvar("mapname");
    level.gsSessions = [];

    level thread GsWatchPlayers();
    level thread GsWatchEnd();
}

// New player entities get their own tracking thread. Polled rather than
// waiting on a connect notify, which not every map's scripts send.
GsWatchPlayers() {
    for (;;) {
        players = getplayers();
        for (i = 0; i < players.size; i++) {
            if (isDefined(players[i]) && !isDefined(players[i].gsSession))
                players[i] thread GsTrackPlayer();
        }
        wait 1;
    }
}

GsTrackPlayer() {
    session = spawnStruct();
    session.guid = "" + self getGuid();
    session.joinRound = GsRound();
    session.joinTime = getTime();
    session.bleedouts = 0;
    session.box = 0;
    session.perks = 0;
    session.perksGained = 0;
    session.freePerkAt = -100000;
    session.pap = 0;
    session.papSeen = [];
    session.powerups = 0;
    session.powerupTypes = [];
    session.written = false;
    self.gsSession = session;
    level.gsSessions[level.gsSessions.size] = session;

    self thread GsWatchBleedouts(session);
    self thread GsWatchLeave(session);
    self thread GsWatchPerks(session, "perk_used");
    self thread GsWatchPerks(session, "machine_used");
    self thread GsWatchPerksHeld(session);
    self thread GsWatchPap(session);

    // Keep a copy of the numbers, so a player who drops is still logged with
    // what they had - their entity is gone by the time "disconnect" arrives.
    self endon("disconnect");
    for (;;) {
        GsSnapshotOf(self, session);
        wait 1;
    }
}

GsWatchBleedouts(session) {
    self endon("disconnect");

    last = "";
    for (;;) {
        state = "";
        if (isDefined(self.sessionstate))
            state = self.sessionstate;

        // Only "playing" to "spectator" counts: a player joining mid-round
        // starts as a spectator, and game over moves everyone to intermission.
        if (state == "spectator" && last == "playing" && !GsGameOver())
            session.bleedouts++;

        last = state;
        wait 0.25;
    }
}

// The buyer gets "perk_used" from stock-based perk machines and "machine_used"
// from Harrybo21's, once the bottle is paid for. Pack-a-Punch sends
// "perk_used" to the machine, not the player, so it doesn't count here.
GsWatchPerks(session, note) {
    self endon("disconnect");
    for (;;) {
        self waittill(note);
        session.perks++;
    }
}

// Every stock perk a player gains, bought or not, minus the ones a perk
// power-up they grabbed in the last 3 seconds gave them. Only used when no
// perk notify arrived (GsPerks): Verruckt's machines send none. A down takes
// perks away, so buying one back counts again. A spectator's HasPerk answers
// for the player they are watching, so only a player in the game counts.
GsWatchPerksHeld(session) {
    self endon("disconnect");
    perks = [];
    perks[0] = "specialty_armorvest";
    perks[1] = "specialty_quickrevive";
    perks[2] = "specialty_fastreload";
    perks[3] = "specialty_rof";
    held = [];
    for (i = 0; i < perks.size; i++)
        held[i] = false;
    for (;;) {
        wait 0.25;
        playing = isDefined(self.sessionstate) && self.sessionstate == "playing";
        for (i = 0; i < perks.size; i++) {
            has = false;
            if (playing)
                has = self HasPerk(perks[i]);
            if (has && !held[i] && getTime() - session.freePerkAt > 3000)
                session.perksGained++;
            held[i] = has;
        }
    }
}

// The machine notify count where the map sends one, else perks gained.
GsPerks(session) {
    if (session.perks > 0)
        return session.perks;
    return session.perksGained;
}

// A weapon with "upgraded" in its name that the player hasn't held before this
// game. Last stand takes weapons away and gives them back on revive, so each
// upgraded weapon counts once per game, and nothing counts while downed.
GsWatchPap(session) {
    self endon("disconnect");
    for (;;) {
        wait 0.25;
        if (isDefined(self.revivetrigger))
            continue;
        weapons = self GetWeaponsListPrimaries();
        if (!isDefined(weapons))
            continue;
        for (i = 0; i < weapons.size; i++) {
            w = weapons[i];
            if (!isDefined(w) || !isSubStr(w, "upgraded") || isDefined(session.papSeen[w]))
                continue;
            session.papSeen[w] = true;
            session.pap++;
        }
    }
}

// Runs in place of the map's treasure_chest_weapon_spawn, which starts once the
// spin is paid for, then hands over to the original.
GsChestSpawn(chest, player, fireSale) {
    if (isDefined(player) && isPlayer(player) && isDefined(player.gsSession))
        player.gsSession.box++;

    disableDetourOnce(level.gsChestSpawn);
    if (isDefined(fireSale))
        self [[level.gsChestSpawn]](chest, player, fireSale);
    else
        self [[level.gsChestSpawn]](chest, player);
}

GsChestSpawnSumpf(chest, player) {
    if (isDefined(player) && isPlayer(player) && isDefined(player.gsSession))
        player.gsSession.box++;

    disableDetourOnce(level.gsChestSpawnSumpf);
    self [[level.gsChestSpawnSumpf]](chest, player);
}

// Runs in place of the map's powerup_grab, watching who walks into the drop.
GsPowerupGrab() {
    level thread GsWatchDrop(self);
    disableDetourOnce(level.gsPowerupGrab);
    self [[level.gsPowerupGrab]]();
}

// powerup_grab gives a drop to the first player within 64 units and deletes
// it 0.1 s later; a drop nobody takes sends "powerup_timedout" first. So the
// last player seen in range when it vanishes, without a time-out, grabbed it.
GsWatchDrop(powerup) {
    state = spawnStruct();
    state.timedOut = false;
    powerup thread GsDropTimeout(state);

    name = "other";
    if (isDefined(powerup.powerup_name))
        name = GsCleanName(powerup.powerup_name);

    grabber = undefined;
    while (isDefined(powerup)) {
        players = getplayers();
        for (i = 0; i < players.size; i++) {
            if (isDefined(players[i]) && distance(players[i].origin, powerup.origin) < 64) {
                grabber = players[i];
                break;
            }
        }
        wait 0.05;
    }

    if (state.timedOut || !isDefined(grabber) || !isDefined(grabber.gsSession))
        return;
    session = grabber.gsSession;
    session.powerups++;
    if (isSubStr(name, "perk"))
        session.freePerkAt = getTime();
    if (!isDefined(session.powerupTypes[name]))
        session.powerupTypes[name] = 0;
    session.powerupTypes[name] = session.powerupTypes[name] + 1;
}

GsDropTimeout(state) {
    self waittill("powerup_timedout");
    state.timedOut = true;
}

GsPowerupTypes(session) {
    out = "";
    names = getArrayKeys(session.powerupTypes);
    for (i = 0; i < names.size; i++) {
        if (out != "")
            out += "/";
        out += names[i] + "=" + session.powerupTypes[names[i]];
    }
    return out;
}

GsWatchLeave(session) {
    self waittill("disconnect");
    if (!session.written && !GsGameOver())
        GsWrite(session, "left");
}

GsWatchEnd() {
    level thread GsEndNotify();
    while (!GsGameOver())
        wait 0.25;

    players = getplayers();
    for (i = 0; i < players.size; i++) {
        if (isDefined(players[i]) && isDefined(players[i].gsSession))
            GsSnapshotOf(players[i], players[i].gsSession);
    }
    for (i = 0; i < level.gsSessions.size; i++) {
        if (!level.gsSessions[i].written && !isDefined(level.gsSessions[i].left))
            GsWrite(level.gsSessions[i], "end");
    }
}

// Der Riese-based maps do notify "end_game".
GsEndNotify() {
    level waittill("end_game");
    level.gsEnded = true;
}

GsGameOver() {
    if (isDefined(level.gsEnded))
        return true;
    return isDefined(level.intermission) && level.intermission;
}

GsSnapshotOf(player, session) {
    name = undefined;
    if (isDefined(player.playername))
        name = player.playername;
    else if (isDefined(player.name))
        name = player.name;
    if (isDefined(name))
        session.name = GsCleanName(name);

    if (isDefined(player.persistentClientId))
        session.id = "" + player.persistentClientId;
    else if (!isDefined(session.id))
        session.id = session.guid;

    session.kills = GsNum(player.kills);
    session.headshots = GsNum(player.headshots);
    session.downs = GsNum(player.downs);
    session.revives = GsNum(player.revives);
    if (isDefined(player.score_total))
        session.points = GsNum(player.score_total);
    else
        session.points = GsNum(player.score);
    session.lastSeen = getTime();
}

GsWrite(session, reason) {
    session.written = true;
    if (reason == "left")
        session.left = true;

    if (!isDefined(session.lastSeen) || !isDefined(session.name))
        return;
    ms = session.lastSeen - session.joinTime;
    if (ms < 30000 && session.kills == 0)
        return;

    line = level.gsRunId + "|" + level.gsMapToken + "|" + GsRound() + "|" + reason + "|"
         + getDvar("net_port") + "|" + session.id + "|" + session.name + "|"
         + session.kills + "|" + session.headshots + "|" + session.downs + "|"
         + session.revives + "|" + session.bleedouts + "|" + session.points + "|"
         + session.joinRound + "|" + ms + "|" + session.box + "|" + GsPerks(session) + "|"
         + session.pap + "|" + session.powerups + "|" + GsPowerupTypes(session);

    file = fs_fopen(level.gsFile, "append");
    if (isDefined(file) && file != 0) {
        fs_writeline(file, line);
        fs_fclose(file);
    }
}

GsRound() {
    if (isDefined(level.round_number))
        return level.round_number;
    return 0;
}

GsNum(value) {
    if (isDefined(value))
        return int(value);
    return 0;
}

// Strip the characters the line format uses so a name can never break parsing.
// Bounded as well as tested - see SrCleanName in T4Speedrun.gsc.
GsCleanName(name) {
    out = "";
    for (i = 0; i < 64 && i < name.size; i++) {
        c = name[i];
        if (!isDefined(c))
            break;
        if (c != "|" && c != ":" && c != "," && c != ";")
            out += c;
    }
    if (out == "")
        return "Player";
    return out;
}
