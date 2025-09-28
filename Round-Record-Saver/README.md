

🌟 Features
Persistent Records: High-round records are loaded from and saved to a file (scriptdata/highrounds.txt), ensuring they persist across server restarts.

Per-Map & Per-Player Count Tracking: Records are tracked separately for each map and for player counts of 1, 2, 3, and 4.

Automatic Record Monitoring: The script constantly monitors for a new high round at the end of each round.

In-Game Announcements:

Announces all current high-round records on map load.

Announces current high-round records to players as they connect to the game.

Broadcasts a celebratory message when a new high-round record is broken.

Announces the current high-round record at the beginning of rounds that don't break a record.

Robust File Handling: Includes logic for reading and writing to the high-rounds file, handling data serialization (using | and ; delimiters), and gracefully initializing data for new maps.

🛠️ Setup and Installation
Prerequisites
This script requires a GSC environment (e.g., a custom Call of Duty mod) that supports the following global and file system functions:

level thread <function>: To start functions on the level entity.

level waittill("<notify>"): To wait for specific notifications.

getDvar("mapname"): To retrieve the current map name.

getplayers(): To get an array of all active players.

self endon("disconnect"): To stop a thread when the player disconnects.

wait <seconds>: To pause execution.

iprintln / BroadcastIprintln: To send in-game messages.

File system functions: fs_fopen, fs_length, fs_read, fs_fclose, fs_writeline.

Data manipulation functions: isDefined, int(), spawnStruct, getArrayKeys.

Integration Steps
Place the Script: Save the provided code as a GSC file (e.g., highrounds.gsc) in your project's script directory.

Call the Initialization: Ensure your main map script calls the main() function of this module. This is typically done in the map's main function:

Code snippet

// In your main map script (e.g., mapname.gsc)
main() {
    // ... other initialization ...
    level thread highrounds::main(); // Assuming your file is named highrounds.gsc
    // ...
}
File System: Create the necessary directory for the records file if it doesn't exist: scriptdata/. The script will attempt to create the highrounds.txt file automatically when saving.

🗃️ Data Structure
In-Game Data (level.highRoundsByMap)
The high-round records are stored in a nested array/struct on the level entity:

level.highRoundsByMap = 
{
    // Key is the map name (e.g., "zm_mapname")
    "mapname_a": 
    [ 
        // Index is the player count (1 to 4)
        1: { 
            round: <integer>,       // The high round number
            players: <array>        // Array of player names (strings)
        },
        2: { ... },
        3: { ... },
        4: { ... }
    ],
    "mapname_b": { ... }
}
File Format (scriptdata/highrounds.txt)
The file stores each record on a separate line using the pipe (|) and semicolon (;) delimiters.

Format:
[mapname]|[playerCount]|[playerNames]|[round]

Example:

zm_mapname_a|1|PlayerA|60
zm_mapname_a|2|PlayerA;PlayerB|85
zm_mapname_b|4|PlayerX;PlayerY;PlayerZ;PlayerW|100
zm_mapname_c|1|None|0 
Player names are joined by a semicolon (;).

If no player names are available or the record is 0, the player name field is set to None.

The playerCount must be an integer from 1 to 4.

⚙️ Core Functions
Function	Purpose
main()	The entry point for the module. Starts the InitHighRoundVars thread.
InitHighRoundVars()	Initializes file path, data structure, loads records, initializes current map data, and starts the persistent monitoring threads (AnnounceAllCurrentRecords, MonitorForNewHighRounds, MonitorPlayerConnections).
MonitorForNewHighRounds()	Waits for the "between_round_over" notify. Checks if the current round beats the high round for the current player count. If so, it updates the record, announces it, and saves the file.
LoadHighRoundsFromFile()	Reads and parses the highrounds.txt file, populating level.highRoundsByMap.
SaveHighRoundsToFile()	Serializes all data in level.highRoundsByMap and writes it back to highrounds.txt.
AnnounceRecordsOnJoin()	Called when a player connects. Waits 10 seconds and then prints all 1-to-4 player high rounds for the current map to the joining player.
StrSplit(input, delimiter)	Custom function to split a string by a given delimiter.

Thanks To - Aymoss + HGM






