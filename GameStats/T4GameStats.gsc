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
 * Box spins and downs also go one line each to scriptdata/gameevents.txt (31 Oct 2026):
 *     <runId>|<mapname>|<round>|<port>|<id>|<name>|box|<weapon or "teddy">
 *     <runId>|<mapname>|<round>|<port>|<id>|<name>|down|<x>,<y>,<z>
 * A box line is the weapon the spin offered, taken or not; "teddy" moved the box.
 * Floor plans for the heatmaps (1 Nov 2026):
 *     ...|0|-|grid|<cx>,<cy>,<cz>,<n>;...   time spent per 64x64x128-unit cell, every 5 minutes
 *     ...|0|-|mark|<type>:<name>:<x>,<y>,<z>   perks, PaP, box spots and wall buys, once per game
 * Cells are offset by 65536 so they are never negative: cx = int((x + 65536) / 64).
 * Live radar (1 Nov 2026), the four stock maps only: every second, one line per player into the
 * game log in the format IW4MAdmin's Live Radar reads, the team field holding up, down or dead:
 *     LiveRadar;<guid hex>;<origin>;<angles>;<state>;0;0;0;none;<health>;<alive>;0
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
    weapon = self [[level.gsHarryBoxDecide]](player);
    if (isDefined(player) && isPlayer(player) && isDefined(weapon))
        GsEvent(player, "box", "" + weapon);
    return weapon;
}

InitGameStats() {
    level.gsFile = "scriptdata/gamestats.txt";
    level.gsEventFile = "scriptdata/gameevents.txt";
    level.gsRunId = randomInt(1000000) + "-" + getTime();
    level.gsMapToken = getDvar("mapname");
    level.gsSessions = [];

    level thread GsWatchPlayers();
    level thread GsWatchEnd();
    level thread GsFloorSample();
    level thread GsFloorFlush();
    level thread GsLogMarks();
    level thread GsRadar();
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
    self thread GsWatchDowns();

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
    self thread GsLogSpin(player);

    disableDetourOnce(level.gsChestSpawn);
    if (isDefined(fireSale))
        self [[level.gsChestSpawn]](chest, player, fireSale);
    else
        self [[level.gsChestSpawn]](chest, player);
}

GsChestSpawnSumpf(chest, player) {
    if (isDefined(player) && isPlayer(player) && isDefined(player.gsSession))
        player.gsSession.box++;
    self thread GsLogSpin(player);

    disableDetourOnce(level.gsChestSpawnSumpf);
    self [[level.gsChestSpawnSumpf]](chest, player);
}

// The spin ends with "randomization_done" on the weapon spawn origin (self),
// which then holds the weapon in weapon_string. On a teddy bear WaW keeps a
// weapon name there but sets the "moving_chest_now" flag first.
GsLogSpin(player) {
    self waittill("randomization_done");
    if (!isDefined(player) || !isPlayer(player))
        return;
    weapon = "teddy";
    if (!(isDefined(level.flag) && isDefined(level.flag["moving_chest_now"]) && level.flag["moving_chest_now"])
        && isDefined(self.weapon_string))
        weapon = self.weapon_string;
    GsEvent(player, "box", weapon);
}

// player.downs counts every down; where the player was when it went up.
GsWatchDowns() {
    self endon("disconnect");
    last = GsNum(self.downs);
    for (;;) {
        wait 0.2;
        now = GsNum(self.downs);
        if (now > last)
            GsEvent(self, "down", int(self.origin[0]) + "," + int(self.origin[1]) + "," + int(self.origin[2]));
        last = now;
    }
}

// Every 2 s, one count for the cell each playing player stands in.
GsFloorSample() {
    level.gsFloor = [];
    for (;;) {
        wait 2;
        if (GsGameOver())
            return;
        players = getplayers();
        for (i = 0; i < players.size; i++) {
            p = players[i];
            if (!isDefined(p) || !isDefined(p.sessionstate) || p.sessionstate != "playing")
                continue;
            key = int((p.origin[0] + 65536) / 64) + "," + int((p.origin[1] + 65536) / 64) + "," + int((p.origin[2] + 65536) / 128);
            if (!isDefined(level.gsFloor[key]))
                level.gsFloor[key] = 0;
            level.gsFloor[key] = level.gsFloor[key] + 1;
        }
    }
}

// Live radar lines, stock maps only. The guid goes out in hex because the radar plugin parses it that way.
GsRadar() {
    map = getDvar("mapname");
    if (map != "nazi_zombie_prototype" && map != "nazi_zombie_asylum" && map != "nazi_zombie_sumpf" && map != "nazi_zombie_factory")
        return;
    for (;;) {
        wait 1;
        if (GsGameOver())
            return;
        players = getplayers();
        for (i = 0; i < players.size; i++) {
            p = players[i];
            if (!isDefined(p))
                continue;
            alive = isDefined(p.sessionstate) && p.sessionstate == "playing";
            state = "up";
            if (!alive)
                state = "dead";
            else if (isDefined(p.revivetrigger))
                state = "down";
            logPrint("LiveRadar;" + GsHex(p getGuid()) + ";" + p.origin + ";" + p getPlayerAngles() + ";" + state
                + ";0;0;0;none;" + GsNum(p.health) + ";" + GsNum(alive) + ";0\n");
        }
    }
}

GsHex(value) {
    n = int(value);
    if (n <= 0)
        return "0";
    digits = "0123456789abcdef";
    out = "";
    for (i = 0; i < 16 && n > 0; i++) {
        out = digits[n % 16] + out;
        n = int(n / 16);
    }
    return out;
}

// The counts go out every 5 minutes (and at game over), 40 cells a line.
GsFloorFlush() {
    for (;;) {
        for (t = 0; t < 300 && !GsGameOver(); t++)
            wait 1;
        cells = level.gsFloor;
        level.gsFloor = [];
        if (isDefined(cells)) {
            keys = getArrayKeys(cells);
            data = "";
            n = 0;
            for (i = 0; i < keys.size; i++) {
                if (n > 0)
                    data = data + ";";
                data = data + keys[i] + "," + cells[keys[i]];
                n++;
                if (n == 40 || i == keys.size - 1) {
                    GsLevelLine("grid", data);
                    data = "";
                    n = 0;
                }
            }
        }
        if (GsGameOver())
            return;
    }
}

// Where the perk machines, Pack-a-Punch, box spots and wall buys are.
GsLogMarks() {
    wait 10;
    vending = getEntArray("zombie_vending", "targetname");
    for (i = 0; i < vending.size; i++) {
        if (isDefined(vending[i].script_noteworthy))
            GsMark("perk", vending[i].script_noteworthy, vending[i].origin);
    }
    pap = getEntArray("zombie_vending_upgrade", "targetname");
    for (i = 0; i < pap.size; i++)
        GsMark("pap", "specialty_weapupgrade", pap[i].origin);
    for (t = 0; t < 1200 && !isDefined(level.chests); t++)
        wait 1;
    if (isDefined(level.chests)) {
        for (i = 0; i < level.chests.size; i++) {
            if (isDefined(level.chests[i]))
                GsMark("box", "box", level.chests[i].origin);
        }
    }
    wallbuys = getEntArray("weapon_upgrade", "targetname");
    for (i = 0; i < wallbuys.size; i++) {
        if (isDefined(wallbuys[i].zombie_weapon_upgrade))
            GsMark("wall", wallbuys[i].zombie_weapon_upgrade, wallbuys[i].origin);
    }
}

GsMark(type, name, origin) {
    GsLevelLine("mark", type + ":" + name + ":" + int(origin[0]) + "," + int(origin[1]) + "," + int(origin[2]));
}

GsLevelLine(type, data) {
    line = level.gsRunId + "|" + level.gsMapToken + "|" + GsRound() + "|" + getDvar("net_port") + "|0|-|" + type + "|" + data;
    file = fs_fopen(level.gsEventFile, "append");
    if (isDefined(file) && file != 0) {
        fs_writeline(file, line);
        fs_fclose(file);
    }
}

GsEvent(player, type, data) {
    if (GsGameOver() || !isDefined(level.gsEventFile))
        return;
    id = "" + player getGuid();
    if (isDefined(player.persistentClientId))
        id = "" + player.persistentClientId;
    name = "";
    if (isDefined(player.name))
        name = GsCleanName(player.name);
    line = level.gsRunId + "|" + level.gsMapToken + "|" + GsRound() + "|" + getDvar("net_port") + "|"
         + id + "|" + name + "|" + type + "|" + data;
    file = fs_fopen(level.gsEventFile, "append");
    if (isDefined(file) && file != 0) {
        fs_writeline(file, line);
        fs_fclose(file);
    }
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
