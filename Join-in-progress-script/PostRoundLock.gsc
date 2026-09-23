/**
 * Round locker for T4 (World at War) Zombies - same rules as the BO1 and BO2
 * servers (T5PostRoundLock / T6PostRoundLockVote):
 *
 *   .lock      from round 1 starts a lock vote; a majority of the players on
 *              locks the server (a solo player locks it straight away).
 *              Votes stay open 60 seconds, 5-minute cooldown between votes.
 *   round 20   the server locks itself regardless.
 *
 * Locking sets a random 4-digit password; it clears when the game ends.
 * Replaces the earlier T4RoundLocker, which only auto-locked at round 20 and
 * had no chat command.
 */

#include common_scripts\utility;
#include maps\_utility;
#include maps\_zombiemode_utility;
#include maps\_loadout;

init()
{
    level.min_lock_round = 1;
    level.force_lock_round = 20;
    level.lock_vote_duration = 60;
    level.lock_vote_cooldown_ms = 300000; // 5 minutes.

    level.locked = false;
    level.pin = "";
    level.lock_vote_active = false;
    level.lock_vote_started_at = 0;
    level.lock_vote_voters = [];
    level.last_lock_vote_time = 0;

    setDvar("password", "");
    setDvar("g_password", "");

    level thread MonitorForcedRoundLock();
    level thread ListenForChatCommands();
    level thread ResetPasswordOnEnd();
    level thread ResetPasswordOnGameEnded();
}

MonitorForcedRoundLock()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("between_round_over");

        if (level.locked)
            continue;

        if (IsForcedLockAvailable())
            LockServer("round");
    }
}

ListenForChatCommands()
{
    level endon("game_ended");
    level thread ListenForGlobalChat();
    level thread ListenForTeamChat();
}

ListenForGlobalChat()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("say", text, player);
        HandleChatCommand(text, player);
    }
}

ListenForTeamChat()
{
    level endon("game_ended");

    for (;;)
    {
        level waittill("say_team", text, player);
        HandleChatCommand(text, player);
    }
}

HandleChatCommand(text, player)
{
    if (!isDefined(text) || !isDefined(player))
        return;

    command = SanitizeChat(text);

    if (command == ".lock")
        HandleLockVote(player);
    else if (command == ".unlock")
        player iPrintLn("^3Server lock clears automatically at game end.");
}

HandleLockVote(player)
{
    if (level.locked)
    {
        player iPrintLn("^3Server is already locked until game end.");
        return;
    }

    if (!IsLockingAvailable())
    {
        player iPrintLn("^3Lock voting is available from round ^5" + level.min_lock_round);
        return;
    }

    if (!level.lock_vote_active)
    {
        if (!CanStartLockVote())
        {
            remaining = GetLockVoteCooldownRemaining();
            player iPrintLn("^3Lock vote cooldown active. Try again in ^5" + remaining + "^3 seconds.");
            return;
        }

        StartLockVote(player);
    }

    RegisterLockVote(player);
}

StartLockVote(player)
{
    level.lock_vote_active = true;
    level.lock_vote_started_at = getTime();
    level.last_lock_vote_time = level.lock_vote_started_at;
    level.lock_vote_voters = [];

    BroadcastIprintln("^3Lock vote started by ^5" + GetPlayerName(player) + "^7. Type ^5.lock^7 to vote. Need ^5" + GetRequiredVoteCount() + "^7 votes.");
    level thread LockVoteTimeout();
}

RegisterLockVote(player)
{
    if (HasPlayerVoted(player))
    {
        player iPrintLn("^3You already voted to lock.");
        return;
    }

    level.lock_vote_voters[level.lock_vote_voters.size] = player;

    votes = level.lock_vote_voters.size;
    required = GetRequiredVoteCount();
    BroadcastIprintln("^2Lock vote: ^5" + votes + "^7/^5" + required + "^7");

    if (votes >= required)
        LockServer("vote");
}

LockVoteTimeout()
{
    level endon("game_ended");
    level endon("lock_vote_ended");

    wait level.lock_vote_duration;

    if (!level.lock_vote_active || level.locked)
        return;

    votes = level.lock_vote_voters.size;
    required = GetRequiredVoteCount();
    level.lock_vote_active = false;
    level.lock_vote_voters = [];

    BroadcastIprintln("^3Lock vote failed: ^5" + votes + "^7/^5" + required + "^7 votes.");
}

LockServer(reason)
{
    if (level.locked)
        return;

    level.locked = true;
    level.pin = GeneratePin();
    level.lock_vote_active = false;
    level.lock_vote_voters = [];
    level notify("lock_vote_ended");

    setDvar("g_password", level.pin);
    setDvar("password", level.pin);

    if (isDefined(reason) && reason == "round")
        BroadcastIprintln("^1Server Locked^7 | Round ^5" + level.force_lock_round + "^7 reached | Clears at game end");
    else
        BroadcastIprintln("^1Server Locked^7 | Vote passed | Clears at game end");
}

ResetPasswordOnEnd()
{
    level endon("post_round_lock_reset");
    level waittill("end_game");
    UnlockServer();
    level notify("post_round_lock_reset");
}

ResetPasswordOnGameEnded()
{
    level endon("post_round_lock_reset");
    level waittill("game_ended");
    UnlockServer();
    level notify("post_round_lock_reset");
}

UnlockServer()
{
    setDvar("g_password", "");
    setDvar("password", "");
    level.locked = false;
    level.pin = "";
    level.lock_vote_active = false;
    level.lock_vote_voters = [];
    level notify("lock_vote_ended");
}

CanStartLockVote()
{
    if (level.last_lock_vote_time <= 0)
        return true;

    return (getTime() - level.last_lock_vote_time) >= level.lock_vote_cooldown_ms;
}

GetLockVoteCooldownRemaining()
{
    elapsed = getTime() - level.last_lock_vote_time;
    remaining = level.lock_vote_cooldown_ms - elapsed;

    if (remaining < 0)
        remaining = 0;

    return int((remaining + 999) / 1000);
}

GetRequiredVoteCount()
{
    players = getplayers();
    count = players.size;

    if (count < 1)
        count = 1;

    return int(count / 2) + 1;
}

HasPlayerVoted(player)
{
    for (i = 0; i < level.lock_vote_voters.size; i++)
    {
        if (!isDefined(level.lock_vote_voters[i]))
            continue;

        if (level.lock_vote_voters[i] == player)
            return true;
    }

    return false;
}

IsLockingAvailable()
{
    return isDefined(level.round_number) && level.round_number >= level.min_lock_round;
}

IsForcedLockAvailable()
{
    return isDefined(level.round_number) && level.round_number >= level.force_lock_round;
}

GeneratePin()
{
    pin = "";
    for (i = 0; i < 4; i++)
        pin += randomInt(10);
    return pin;
}

BroadcastIprintln(message)
{
    players = getplayers();

    for (i = 0; i < players.size; i++)
    {
        if (!isDefined(players[i]))
            continue;

        players[i] iPrintLn(message);
    }
}

GetPlayerName(player)
{
    if (!isDefined(player))
        return "Someone";

    if (isDefined(player.name))
        return player.name;

    if (isDefined(player.playerName))
        return player.playerName;

    return "Someone";
}

SanitizeChat(text)
{
    if (!isDefined(text))
        return "";

    for (i = 0; i < 64; i++)
    {
        if (text == "")
            return "";

        firstChar = getSubStr(text, 0, 1);
        if (firstChar == " " || firstChar == "\t")
        {
            text = getSubStr(text, 1, 1024);
            continue;
        }

        break;
    }

    return text;
}
