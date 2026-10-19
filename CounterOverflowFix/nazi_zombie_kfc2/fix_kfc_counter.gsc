#include common_scripts\utility;
#include maps\_utility;

/*
 * KFC's "Zombies Left: N" counter called settext() with a new string for
 * every count, and each distinct string takes a configstring for the rest of the
 * map. Around 800 different counts the server dies with
 * "G_FindConfigstringIndex: overflow (381)". Same counter here, but the words
 * are the label and the number goes through setvalue(), which takes no slots.
 */
main()
{
	level.kfcEnemyCount = getFunction( "maps/_zombiemode_utility", "get_enemy_count" );
	level.kfcEyeGlowStop = getFunction( "maps/_zombiemode_spawner", "zombie_eye_glow_stop" );
	level.kfcCloseDamage = getFunction( "maps/_zombiemode_spawner", "play_closedamage_dialog" );

	replaceFunc( getFunction( "maps/_zombiemode_spawner", "roundstart" ), ::fix_round_start, -1 );
	replaceFunc( getFunction( "maps/_zombiemode_spawner", "updatezombiecount" ), ::fix_update_zombie_count, -1 );
	replaceFunc( getFunction( "maps/_zombiemode_spawner", "zombie_death_event" ), ::fix_zombie_death_event, -1 );
}

fix_zombies_left()
{
	return level.zombie_total + [[ level.kfcEnemyCount ]]();
}

fix_round_start()
{
	level.zombieCounterText = "Zombies Left: ";
	level.ZombiesLeft.label = &"Zombies Left: ";
	level.ZombiesLeft SetText( "None Yet!" );
	fix_update_zombie_count( "intro_hud_done", 3 );
	while ( 1 )
	{
		fix_update_zombie_count( "between_round_over", 1 );
		wait( .1 );
	}
}

fix_update_zombie_count( notification, waiting )
{
	level waittill( notification );
	wait( waiting );
	level.ZombiesLeft SetValue( fix_zombies_left() );
}

// The mod's own zombie_death_event, with only the counter line changed.
fix_zombie_death_event( zombie )
{
	zombie waittill( "death" );
	level.ZombiesLeft SetValue( fix_zombies_left() );
	zombie thread [[ level.kfcEyeGlowStop ]]();
	playsoundatposition( "death_vocals", zombie.origin );
	if ( isdefined( zombie.attacker ) && isplayer( zombie.attacker ) && level.script != "nazi_zombie_prototype" )
	{
		if ( !isdefined( zombie.attacker.killcounter ) )
		{
			zombie.attacker.killcounter = 1;
		}
		else
		{
			zombie.attacker.killcounter++;
		}

		if ( IsDefined( zombie.sound_damage_player ) && zombie.sound_damage_player == zombie.attacker )
		{
			zombie.attacker thread [[ level.kfcCloseDamage ]]();
		}

		zombie.attacker notify( "zom_kill" );
	}

	if ( isdefined( zombie.attacker ) && isplayer( zombie.attacker ) )
	{
		damageloc = zombie.damagelocation;
		damagemod = zombie.damagemod;
		attacker = zombie.attacker;
		weapon = zombie.damageWeapon;

		bbPrint( "zombie_kills: round %d zombietype zombie damagetype %s damagelocation %s playername %s playerweapon %s playerx %f playery %f playerz %f zombiex %f zombiey %f zombiez %f",
				level.round_number, damagemod, damageloc, attacker.playername, weapon, attacker.origin, zombie.origin );
	}
}
