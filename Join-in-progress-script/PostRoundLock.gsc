#include common_scripts\utility; 
#include maps\_utility;
#include maps\_zombiemode_utility;
#include maps\_loadout;


Init()
{
SetDvar("password", "");
SetDvar("g_password", "");


level thread SetPasswordsOnRound(10);
}

SetPasswordsOnRound(roundNumber)
{
while ( true )
{
level waittill( "between_round_over");


    if (level.round_number >= roundNumber)
    {
        pin = generate_random_password();
        setDvar( "g_password", pin );

        players = getPlayers();
        for ( i = 0; i < players.size; i++ )
        {
            players[ i ] setClientDvar( "password", pin );
            players[ i ] iPrintLn( "Server is now locked. Use password " + pin + " to rejoin." );
        }
    }
}
}

generate_random_password()
{
str = "";
for ( i = 0; i < 4; i++ )
{
str = str + randomInt( 10 );
}
return str;
}
