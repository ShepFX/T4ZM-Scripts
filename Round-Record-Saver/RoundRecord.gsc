
main() {
    level thread InitHighRoundVars();
}


InitHighRoundVars() {
    level.highRoundFile = "scriptdata/highrounds.txt";
    level.highRoundsByMap = [];

    LoadHighRoundsFromFile();
    InitializeDataForCurrentMap();

    level thread AnnounceAllCurrentRecords(); 
    level thread MonitorForNewHighRounds();
    level thread MonitorPlayerConnections();
}


MonitorPlayerConnections() {
    for(;;) {
        level waittill("connected", player);
        player thread AnnounceRecordsOnJoin();
    }
}


AnnounceRecordsOnJoin() {
    self endon("disconnect");
    
    wait 10; 

    mapname = getDvar("mapname");
    if (!isDefined(level.highRoundsByMap[mapname])) return;

    self iprintln("--- High Rounds for this Map ---");
    wait 1;

    for (playerCount = 1; playerCount <= 4; playerCount++) {
        recordData = level.highRoundsByMap[mapname][playerCount];
        round = recordData.round;
        
        message = "";
        mode = GetGameModeString(playerCount);

        if (round > 0 && isDefined(recordData.players) && recordData.players.size > 0) {
            playersString = recordData.players[0];
            for(i = 1; i < recordData.players.size; i++){
                playersString += ", " + recordData.players[i];
            }
            message = "^5" + mode + "^7: Round ^5" + round + "^7 by ^5" + playersString;
        } else {
            message = "^5" + mode + "^7: No record set.";
        }
        
        self iprintln(message);
        wait 1;
    }
}



InitializeDataForCurrentMap() {
    mapname = getDvar("mapname");
    if (!isDefined(level.highRoundsByMap[mapname])) {
        level.highRoundsByMap[mapname] = [];
        for (i = 1; i <= 4; i++) {
            level.highRoundsByMap[mapname][i] = spawnStruct();
            level.highRoundsByMap[mapname][i].round = 0;
            level.highRoundsByMap[mapname][i].players = [];
        }
    }
}


LoadHighRoundsFromFile() {
    file = fs_fopen(level.highRoundFile, "read");
    if (isDefined(file) && file != 0) {
        fileLength = fs_length(file);
        if (fileLength > 0) {
            allContent = fs_read(file, fileLength);
            fs_fclose(file);
            
            lines = StrSplit(allContent, "\n");
            
            for (i = 0; i < lines.size; i++) {
                line = lines[i];
                if (!isDefined(line) || line == "") continue;

                parts = StrSplit(line, "|");
                
                if (parts.size == 4) {
                    mapname = parts[0];
                    playerCount = int(parts[1]);
                    playerNames = parts[2];
                    round = int(parts[3]);

                    if (!isDefined(level.highRoundsByMap[mapname])) {
                        level.highRoundsByMap[mapname] = [];
                        for (p = 1; p <= 4; p++) {
                            level.highRoundsByMap[mapname][p] = spawnStruct();
                            level.highRoundsByMap[mapname][p].round = 0;
                            level.highRoundsByMap[mapname][p].players = [];
                        }
                    }
                    
                    if (playerCount >= 1 && playerCount <= 4) {
                        level.highRoundsByMap[mapname][playerCount].round = round;
                        if (playerNames != "None") {
                            level.highRoundsByMap[mapname][playerCount].players = StrSplit(playerNames, ";");
                        } else {
                            level.highRoundsByMap[mapname][playerCount].players = [];
                        }
                    }
                }
            }
        }
        else {
            fs_fclose(file);
        }
    }
}


SaveHighRoundsToFile() {
    file = fs_fopen(level.highRoundFile, "write");
    if (isDefined(file) && file != 0) {
        mapNames = getArrayKeys(level.highRoundsByMap);

        for (m = 0; m < mapNames.size; m++) {
            mapname = mapNames[m];
            mapData = level.highRoundsByMap[mapname];

            for (playerCount = 1; playerCount <= 4; playerCount++) {
                currentData = mapData[playerCount];
                
                playersString = "None";
                if (isDefined(currentData.players) && currentData.players.size > 0) {
                    playersString = currentData.players[0];
                    for (p = 1; p < currentData.players.size; p++) {
                        playersString += ";" + currentData.players[p];
                    }
                }
                
                fs_writeline(file, mapname + "|" + playerCount + "|" + playersString + "|" + currentData.round);
            }
        }
        fs_fclose(file);
    }
}


MonitorForNewHighRounds() {
    mapname = getDvar("mapname");
    while (1) {
        level waittill("between_round_over");

        players = getplayers();
        numPlayers = players.size;
        currentRound = level.round_number;

        if (numPlayers < 1 || numPlayers > 4) {
            continue;
        }

        currentRecord = level.highRoundsByMap[mapname][numPlayers].round;

        if (currentRound > currentRecord) {
            playerNames = [];
            for (i = 0; i < numPlayers; i++) {
                playerNames[i] = GetPlayerName(players[i]);
            }

            level.highRoundsByMap[mapname][numPlayers].round = currentRound;
            level.highRoundsByMap[mapname][numPlayers].players = playerNames;
            
            AnnounceNewHighRound(playerNames, currentRound, numPlayers);
            SaveHighRoundsToFile();
        }
        else {
            AnnounceCurrentRecord(numPlayers);
        }
    }
}


AnnounceAllCurrentRecords() {
    wait 2;
    for (i = 1; i <= 4; i++) {
        AnnounceCurrentRecord(i);
        wait 0.2;
    }
}


AnnounceCurrentRecord(numPlayers) {
    if (numPlayers < 1 || numPlayers > 4) return;
    
    mapname = getDvar("mapname");
    if (!isDefined(level.highRoundsByMap[mapname])) return;

    recordData = level.highRoundsByMap[mapname][numPlayers];
    players = recordData.players;
    round = recordData.round;
    
    if (round > 0 && isDefined(players) && players.size > 0) {
        playersString = players[0];
        for(i = 1; i < players.size; i++){
            playersString += ", " + players[i];
        }

        mode = GetGameModeString(numPlayers);
        
        message = "^5" + mode + "^7 High Round: ^5" + round + "^7 (^5" + playersString + "^7)";
        BroadcastIprintln(message);
    }
}


AnnounceNewHighRound(players, round, numPlayers) {
    if (!isDefined(players)) players = [];
    if (!isDefined(round)) round = 0;

    playersString = "Unknown Player(s)";
    if (players.size > 0) {
        playersString = players[0];
        for (i = 1; i < players.size; i++) {
            playersString += ", " + players[i];
        }
    }
    
    mode = GetGameModeString(numPlayers);
    
    message = "Record Broken! ^5" + mode + "^7: ^5" + playersString + "^7 just hit round ^5" + round + "^7!";
    BroadcastIprintln(message);
}


BroadcastIprintln(message) {
    players = getplayers();
    for (i = 0; i < players.size; i++) {
        players[i] iprintln(message);
    }
}


GetPlayerName(player) {
    if (isDefined(player) && isDefined(player.playername)) {
        return player.playername;
    }
    return "Unknown";
}


GetGameModeString(numPlayers) {
    return numPlayers + "-Player";
}


StrSplit(input, delimiter) {
    parts = [];
    current = "";
    for (i = 0; i < input.size; i++) {
        if (input[i] == delimiter) {
            parts[parts.size] = current;
            current = "";
        }
        else {
            current += input[i];
        }
    }
    if (current != "") {
        parts[parts.size] = current;
    }
    return parts;
}
