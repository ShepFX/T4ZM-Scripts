/**
 * Live round reporter (T4 / World at War Zombies).
 *
 * Writes the round currently being played to scriptdata/currentround.txt so the
 * website can show a live round, and blanks the file when the game ends so a
 * finished game never keeps displaying.
 *
 * File format - a single line:
 *     <round>|<players>|<port>|<hostname>
 * An empty file means no game in progress.
 *
 * The port is what lets the website tie this file to the right server: folder
 * names and server names do not reliably match (t4sp-mcdonalds is
 * "[CUK] Mcdonald's [EU]"), but a port is unique. The hostname is a fallback
 * in case net_port cannot be read.
 *
 * The round is polled rather than hooked to a round-start notify on purpose:
 * notify names vary between stock and custom maps, but level.round_number is
 * present everywhere. Polling costs one comparison a second.
 */

main() {
    level thread InitLiveRound();
}

InitLiveRound() {
    level.liveRoundFile = "scriptdata/currentround.txt";

    // Seconds between refreshes when the round has not changed. The rewrite
    // keeps the file's modified time current, which is how the website tells a
    // live game from a file left behind by a server that crashed.
    level.liveRoundHeartbeat = 60;

    WriteLiveRound("");

    level thread MonitorLiveRound();
    level thread ClearLiveRoundOn("end_game");
    level thread ClearLiveRoundOn("game_ended");
}

MonitorLiveRound() {
    level endon("end_game");
    level endon("game_ended");

    lastRound = -1;
    sinceWrite = 0;

    for (;;) {
        wait 1;
        sinceWrite++;

        if (!isDefined(level.round_number))
            continue;

        if (level.round_number != lastRound || sinceWrite >= level.liveRoundHeartbeat) {
            lastRound = level.round_number;
            sinceWrite = 0;

            // mapname is included because one server can host several maps,
            // and the website needs to know which map's record to compare this
            // round against.
            line = level.round_number + "|" + getplayers().size + "|"
                 + getDvar("net_port") + "|" + getDvar("sv_hostname") + "|"
                 + getDvar("mapname");

            WriteLiveRound(line);
        }
    }
}

ClearLiveRoundOn(notifyName) {
    level waittill(notifyName);
    WriteLiveRound("");
}

WriteLiveRound(text) {
    file = fs_fopen(level.liveRoundFile, "write");
    if (isDefined(file) && file != 0) {
        fs_writeline(file, text);
        fs_fclose(file);
    }
}
