/**
 * Speedrun logger (T4 / World at War Zombies).
 *
 * Appends one line to scriptdata/speedrun.txt (beside highrounds.txt) each
 * time a game reaches a milestone round, with the game time it took. The
 * website turns those lines into "fastest to round N" boards per map and
 * player count.
 *
 * File format - one line per event, appended by the game. The website trims the
 * file back to the lines still on a board after each read, so it never grows:
 *     <runId>|<mapname>|<kind>|<target>|<ms>|<players>|<id:name,id:name>|<port>
 *
 *     runId    random id for this game, so the site can tell two games apart
 *     mapname  getDvar("mapname"), because one server can rotate several maps
 *     kind     always "round" on this game (T5/T6 also log "ee")
 *     target   the round reached
 *     ms       milliseconds from the start of round 1 to the event
 *     players  squad size (see the roster rule below) - the board it goes on
 *
 * The clock starts when round 1 actually begins after the intro, so every run
 * on a map is measured the same way. World at War has no "start_of_round"
 * notify, but round_think() stamps level.round_start_time at that moment, so
 * that is what is watched. A game that did not begin at round 1 is not timed.
 *
 * Squad rules: everyone in the game before round 2 begins is the roster, and
 * the run is logged for that squad size with those names, even if some leave
 * before a milestone. A new player joining from round 2 onward ends timing for
 * that game - otherwise a solo run could land on the 2P board, or a three-man
 * carry to round 28 could be logged as a 1P time. A roster member who drops
 * and rejoins is still on the roster.
 *
 * World at War maps have no main quest, so only rounds are logged.
 */

main() {
    level thread InitSpeedrun();
}

InitSpeedrun() {
    level.srFile = "scriptdata/speedrun.txt";
    level.srRunId = randomInt(1000000) + "-" + getTime();
    level.srMapToken = getDvar("mapname");

    level.srMilestones = [];
    level.srMilestones[level.srMilestones.size] = 10;
    level.srMilestones[level.srMilestones.size] = 20;
    level.srMilestones[level.srMilestones.size] = 30;
    level.srMilestones[level.srMilestones.size] = 40;
    level.srMilestones[level.srMilestones.size] = 50;
    level.srMilestones[level.srMilestones.size] = 70;
    level.srMilestones[level.srMilestones.size] = 100;

    SrWriteBootLineIfNew();

    level thread SrWaitForStart();
    level thread SrWatchRounds();
}

SrWaitForStart() {
    level endon("end_game");

    for (;;) {
        wait 0.05;

        if (!isDefined(level.round_start_time) || level.round_start_time <= 0)
            continue;

        // A server that starts games above round 1 cannot be compared with
        // one that does not, so leave the run untimed.
        if (!isDefined(level.round_number) || level.round_number != 1)
            return;

        level.srStart = level.round_start_time;
        level.srRoster = [];
        level.srRosterLocked = false;
        return;
    }
}

SrWatchRounds() {
    level endon("end_game");

    lastRound = -1;
    sinceRoster = 0;

    for (;;) {
        wait 0.05;

        if (!isDefined(level.srStart) || isDefined(level.srInvalid))
            continue;

        // Once a second is plenty for the roster; the round is what needs
        // watching closely. A round change scans immediately as well, so the
        // round-2 lock happens on the exact tick.
        sinceRoster++;
        if (sinceRoster >= 20) {
            sinceRoster = 0;
            SrUpdateRoster();
        }

        if (!isDefined(level.round_number) || level.round_number == lastRound)
            continue;

        lastRound = level.round_number;
        SrUpdateRoster();

        if (lastRound >= 2)
            level.srRosterLocked = true;

        if (SrIsMilestone(lastRound))
            SrLog("round", "" + lastRound);
    }
}

// Before round 2 anyone present joins the roster. After that a face that is
// not on it ends timing for this game.
SrUpdateRoster() {
    players = getplayers();
    for (i = 0; i < players.size; i++) {
        // World at War / Black Ops zombies are built on single-player, where a
        // player's name is .playername; .name is not set at all. Fall back to
        // .name only in case a build ever fills it. A player with neither is
        // still connecting - the next pass picks them up, and the roster does
        // not lock until round 2.
        if (!isDefined(players[i]))
            continue;
        name = undefined;
        if (isDefined(players[i].playername))
            name = players[i].playername;
        else if (isDefined(players[i].name))
            name = players[i].name;
        if (!isDefined(name))
            continue;

        guid = "" + players[i] getGuid();
        slot = SrRosterIndex(guid);

        if (slot < 0) {
            if (level.srRosterLocked) {
                level.srInvalid = true;
                iPrintLn("^3Speedrun timing ended - a new player joined after round 1");
                return;
            }
            slot = level.srRoster.size;
            level.srRoster[slot] = spawnStruct();
            level.srRoster[slot].guid = guid;
        }

        // Keep the latest name and the IW4MAdmin id, which arrives a few
        // seconds after connecting, so a player who leaves is still credited.
        level.srRoster[slot].name = SrCleanName(name);
        if (isDefined(players[i].persistentClientId))
            level.srRoster[slot].id = "" + players[i].persistentClientId;
        else if (!isDefined(level.srRoster[slot].id))
            level.srRoster[slot].id = guid;
    }
}

SrRosterIndex(guid) {
    for (i = 0; i < level.srRoster.size; i++) {
        if (level.srRoster[i].guid == guid)
            return i;
    }
    return -1;
}

SrIsMilestone(rnd) {
    for (i = 0; i < level.srMilestones.size; i++) {
        if (level.srMilestones[i] == rnd)
            return true;
    }
    return false;
}

SrLog(kind, target) {
    elapsed = getTime() - level.srStart;
    SrUpdateRoster();
    if (isDefined(level.srInvalid) || level.srRoster.size == 0)
        return;

    line = level.srRunId + "|" + level.srMapToken + "|" + kind + "|" + target + "|"
         + elapsed + "|" + level.srRoster.size + "|" + SrPlayerBlocks() + "|"
         + getDvar("net_port");

    SrAppend(line);

    iPrintLn("^7Round " + target + " in ^2" + SrFormatTime(elapsed));
}

SrPlayerBlocks() {
    blocks = "";
    for (i = 0; i < level.srRoster.size; i++) {
        block = level.srRoster[i].id + ":" + level.srRoster[i].name;

        if (blocks == "")
            blocks = block;
        else
            blocks = blocks + "," + block;
    }
    return blocks;
}

// Strip the characters the line format uses so a name can never break parsing.
SrCleanName(name) {
    if (!isDefined(name))
        return "Player";

    // The count is bounded as well as tested. A connecting player has no name
    // yet, name.size is undefined, and an unbounded loop here is killed by the
    // engine - taking the calling thread, and the whole run, with it.
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

SrFormatTime(ms) {
    total = int(ms / 1000);
    h = int(total / 3600);
    m = int((total % 3600) / 60);
    s = total % 60;

    if (h > 0)
        return h + ":" + SrPad(m) + ":" + SrPad(s);
    return m + ":" + SrPad(s);
}

SrPad(n) {
    if (n < 10)
        return "0" + n;
    return "" + n;
}

// Writing a marker line the first time the file is created proves the append
// path works on this server before anyone reaches a milestone. The site
// ignores "boot" lines.
SrWriteBootLineIfNew() {
    file = fs_fopen(level.srFile, "read");
    if (isDefined(file) && file != 0) {
        fs_fclose(file);
        return;
    }
    SrAppend(level.srRunId + "|" + level.srMapToken + "|boot|0|0|0||" + getDvar("net_port"));
}

SrAppend(line) {
    file = fs_fopen(level.srFile, "append");
    if (isDefined(file) && file != 0) {
        fs_writeline(file, line);
        fs_fclose(file);
    }
}
