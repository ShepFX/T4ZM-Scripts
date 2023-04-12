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
        SetDvar("password", "Fucker");
        SetDvar("g_password", "Fucker");
        break;
    }
  }
}
