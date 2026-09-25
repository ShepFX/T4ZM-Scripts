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
 *     <downs>|<revives>|<bleedouts>|<points>|<joinRound>|<ms>
 *
 *     runId      random id for this game (same idea as the speedrun log)
 *     round      the round when the line was written
 *     reason     "end" - still in when the game ended - or "left"
 *     id         IW4MAdmin client id (the GUID until IW4MAdmin has set it)
 *     bleedouts  times the player bled out and spectated until the next round
 *     points     total points earned this game, not what they had left
 *     joinRound  the round they joined in
 *     ms         time in the game
 *
 * A session with no kills that lasted under 30 seconds is not written, so
 * someone connecting and leaving straight away adds nothing.
 *
 * World at War has no bleed-out notify and most maps never notify "end_game":
 * a bled-out player just turns spectator until the next round, and game over
 * sets level.intermission. Both are watched instead.
 */

main() {
    level thread InitGameStats();
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
    session.written = false;
    self.gsSession = session;
    level.gsSessions[level.gsSessions.size] = session;

    self thread GsWatchBleedouts(session);
    self thread GsWatchLeave(session);

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
         + session.joinRound + "|" + ms;

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
