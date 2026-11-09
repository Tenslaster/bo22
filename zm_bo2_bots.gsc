#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_zonemgr;
#include maps\mp\zombies\_zm_stats;
#include maps\mp\zombies\_zm_score;
#include maps\mp\zombies\_zm_perks;
#include maps\mp\zombies\_zm_weapons;
#include maps\mp\zombies\_zm_equipment;
#include maps\mp\zombies\_zm_powerups;
#include maps\mp\zombies\_zm_blockers;
#include maps\mp\zombies\_zm_laststand;
#include maps\mp\zombies\_zm_afterlife;
#include maps\mp\zombies\_zm_buildables;

#include scripts\zm\zm_bo2_bots_combat;
#include scripts\zm\zm_bo2_bots_map_tranzit;
#include scripts\zm\zm_bo2_bots_map_die_rise;
#include scripts\zm\zm_bo2_bots_map_mob;
#include scripts\zm\zm_bo2_bots_map_buried;
#include scripts\zm\zm_bo2_bots_map_nuketown;
#include scripts\zm\zm_bo2_bots_map_origins;

main()
{
	replacefunc(maps\mp\zombies\_zm_utility::track_players_intersection_tracker, ::track_players_intersection_tracker);
}

track_players_intersection_tracker()
{
    self endon("disconnect");
    self endon("death");
	
    level endon("end_game");
	
    wait 5;

    while(true)
    {
        killed_players = 0;
		
        players = get_players();

        for(i = 0; i < players.size; i++)
        {
            if(players[i] maps\mp\zombies\_zm_laststand::player_is_in_laststand() || "playing" != players[i].sessionstate)
                continue;

            for(j = 0; j < players.size; j++)
            {
                if(i == j || players[j] maps\mp\zombies\_zm_laststand::player_is_in_laststand() || "playing" != players[j].sessionstate)
                    continue;

                if(isdefined(level.player_intersection_tracker_override))
                {
                    if(players[i] [[level.player_intersection_tracker_override]](players[j]))
                        continue;
                }

                playeri_origin = players[i].origin;
				
                playerj_origin = players[j].origin;

                if(abs(playeri_origin[2] - playerj_origin[2]) > 60)
                    continue;

                distance_apart = distance2d(playeri_origin, playerj_origin);

                if(abs(distance_apart) > 18)
                    continue;

                if(getdvarint("kill_overlapping_players") == 0)
                {
                    return;
                }

                players[i] dodamage(1000, (0, 0, 0));
				
                players[j] dodamage(1000, (0, 0, 0));

                if(!killed_players)
                    players[i] playlocalsound(level.zmb_laugh_alias);

                players[i] maps\mp\zombies\_zm_stats::increment_map_cheat_stat("cheat_too_friendly");
                players[i] maps\mp\zombies\_zm_stats::increment_client_stat("cheat_too_friendly", 0);
                players[i] maps\mp\zombies\_zm_stats::increment_client_stat("cheat_total", 0);
                players[j] maps\mp\zombies\_zm_stats::increment_map_cheat_stat("cheat_too_friendly");
                players[j] maps\mp\zombies\_zm_stats::increment_client_stat("cheat_too_friendly", 0);
                players[j] maps\mp\zombies\_zm_stats::increment_client_stat("cheat_total", 0);
				
                killed_players = 1;
            }
        }

        wait 0.5;
    }
}

#define bot_action_stand "stand"
#define bot_action_crouch "crouch"
#define bot_action_prone "prone"

botaction(stance)
{
    switch(stance)
    {
        case bot_action_stand:
            self allowstand(true);
            self allowcrouch(false);
            self allowprone(false);
            break;
        
        case bot_action_crouch:
            self allowstand(false);
            self allowcrouch(true);
            self allowprone(false);
            break;
            
        case bot_action_prone:
            self allowstand(false);
            self allowcrouch(false);
            self allowprone(true);
            break;
            
        default:
            self allowstand(true);
            self allowcrouch(true);
            self allowprone(true);
            break;
    }
}

init()
{
    setdvar("kill_overlapping_players", 0);

    // Start explicitly in stay mode; wander is only enabled by the F6 command.
    if(!isdefined(level.bot_command_mode))
        level.bot_command_mode = "stay";

    bot_set_dvars();
    flag_wait("initial_blackscreen_passed");

    // Origins' stock capture-progress code excludes Plutonium test clients.
    // Install the map-only replacement before any generator can be started.
    if(getdvar("mapname") == "zm_tomb")
        bot_origins_install_capture_zone_hook();

    if(!isdefined(level.using_bot_weapon_logic))
        level.using_bot_weapon_logic = 1;
    if(!isdefined(level.using_bot_revive_logic))
        level.using_bot_revive_logic = 1;
    if(!isdefined(level.mystery_box_teddy_locations))
        level.mystery_box_teddy_locations = [];

    level.box_in_use_by_bot = undefined;
    init_zombie_cache();
    init_vending_cache();
    init_door_cache();
    init_debris_cache();

    bot_amount = getdvarintdefault("zm_bots", 7);
    for(i = 0; i < bot_amount; i++)
        spawn_bot();

    foreach(player in get_players())
    {
        if(!isdefined(player.pers["isbot"]))
        {
            player thread manual_bot_teleport_monitor();
            player thread bot_command_mode_monitor();
        }
    }
}

spawn_bot()
{
	bot = addtestclient();
	
	bot waittill("spawned_player");
	
	bot thread maps\mp\zombies\_zm::spawnspectator();
	
	if(isdefined(bot))
	{
		bot.pers["isbot"] = 1;
		
		bot thread onspawn();
	}
	
	wait 1;
	
	bot [[level.spawnplayer]]();
}

onspawn()
{
	self endon("disconnect");
	
	level endon("end_game");
	
    self thread bot_cleanup_on_disconnect();
	
	while(1)
	{
		self waittill("spawned_player");
		
		self notify("bot_relife");
		
		self thread bot_spawn();
		self thread bot_set_perks();
	}
}

bot_cleanup_on_disconnect()
{
    self waittill("disconnect");
	
    if(isdefined(level.box_in_use_by_bot) && level.box_in_use_by_bot == self)
    {
        level.box_in_use_by_bot = undefined;
    }
}

bot_spawn()
{
	self bot_spawn_init();
	
	self thread bot_main();
	self thread bot_movement_recovery_think();
	self thread bot_shield_sync_think();
	self thread bot_auto_buildables_think();
	self thread bot_auto_craftables_think();
	self thread bot_auto_quest_think();
	self thread bot_weapon_switch_think();
	self thread bot_weapon_failsafe_monitor();
}

bot_set_perks()
{
	self endon("disconnect");
	self endon("bot_relife");
	self endon("death");
	
	level endon("end_game");
	
	wait 1;
	
	while(1)
	{
		self setperk("specialty_rof");
		self setperk("specialty_deadshot");
		self setperk("specialty_fastreload");
		self setperk("specialty_flakjacket");
		
		self waittill("player_revived");
	}
}

init_zombie_cache()
{
	if(!isdefined(level.zombie_cache))
	{
		level.zombie_cache = [];
		
		level.zombie_cache_time = 0;
		
		level.zombie_cache_refresh = 1000;
	}
}

get_cached_zombies()
{
	init_zombie_cache();
	
	current_time = gettime();
	
	if(current_time - level.zombie_cache_time > level.zombie_cache_refresh)
	{
		level.zombie_cache = undefined;
		
		level.zombie_cache = getaispeciesarray(level.zombie_team, "all");
		
		level.zombie_cache_time = current_time;
	}
	
	return level.zombie_cache;
}

init_vending_cache()
{
    if(!isdefined(level.vending_cache))
    {
        level.vending_cache = getentarray("zombie_vending", "targetname");
		
        level.vending_cache_time = 0;
		
        level.vending_cache_refresh = 5000;
    }
}

get_cached_vending_machines()
{
    init_vending_cache();
    
    current_time = gettime();
    
    if(current_time - level.vending_cache_time > level.vending_cache_refresh)
    {
        level.vending_cache = getentarray("zombie_vending", "targetname");
		
        level.vending_cache_time = current_time;
    }
    
    return level.vending_cache;
}

init_door_cache()
{
    if(!isdefined(level.door_cache))
    {
        level.door_cache = getentarray("zombie_door", "targetname");
		
        level.door_cache_time = 0;
		
        level.door_cache_refresh = 10000;
    }
}

get_cached_doors()
{
    init_door_cache();
    
    current_time = gettime();
    
    if(current_time - level.door_cache_time > level.door_cache_refresh)
    {
        level.door_cache = getentarray("zombie_door", "targetname");
		
        level.door_cache_time = current_time;
    }
    
    return level.door_cache;
}

init_debris_cache()
{
    if(!isdefined(level.debris_cache))
    {
        level.debris_cache = getentarray("zombie_debris", "targetname");
		
        level.debris_cache_time = 0;
		
        level.debris_cache_refresh = 10000;
    }
}

get_cached_debris()
{
    init_debris_cache();
    
    current_time = gettime();
    
    if(current_time - level.debris_cache_time > level.debris_cache_refresh)
    {
        level.debris_cache = getentarray("zombie_debris", "targetname");
		
        level.debris_cache_time = current_time;
    }
    
    return level.debris_cache;
}

bot_set_dvars()
{
	if(isdefined(level.bot_command_mode) && level.bot_command_mode == "follow" && isdefined(level.bot_commander))
	{
		setdvar("g_playercollision", "everybody");
		setdvar("g_playerejection", "everybody");
	}
	else
	{
		setdvar("g_playercollision", "nobody");
		setdvar("g_playerejection", "nobody");
	}
	
	setdvar("bot_allowgrenades", "1");
	setdvar("bot_meleedist", "70");
	setdvar("bot_yawspeed", "4");
	setdvar("bot_sprintdistance", "256");
	setdvar("bot_pitchup", "-5");
	setdvar("bot_pitchdown", "10");
	setdvar("bot_fov", "160");
	setdvar("bot_targetleadbias", "2");
	setdvar("bot_strafechance", "1");
	setdvar("bot_minstrafetime", "3000");
	setdvar("bot_maxstrafetime", "6000");
	setdvar("bot_minreactiontime", "40");
	setdvar("bot_maxreactiontime", "70");
	setdvar("bot_minadstime", "3000");
	setdvar("bot_maxadstime", "5000");
	setdvar("bot_minfiretime", "100");
	setdvar("bot_maxfiretime", "250");
	setdvar("bot_mindeathtime", "250");
	setdvar("bot_maxdeathtime", "500");
	setdvar("bot_mincrouchtime", "100");
	setdvar("bot_maxcrouchtime", "400");
}

bot_spawn_init()
{
	time = gettime();
	
	if(!isdefined(self.bot))
	{
		self.bot = spawnstruct();
		
		self.bot.threat = spawnstruct();
	}
	
	self.bot.stay_pos = undefined;
	self.bot.is_meleeing = undefined;
	self.bot.is_getting_shield = undefined;
	self.bot.is_throwing_grenade = undefined;
	self.bot.is_building = undefined;
	self.bot.is_crafting = undefined;
	self.bot.is_perk_buying = undefined;
	self.bot.is_objective_using = undefined;
	self.bot.is_holding_generator = undefined;
	self.bot.buildable_scan_after = undefined;
	self.bot.craftable_scan_after = undefined;
	self.bot.quest_scan_after = undefined;
	self.bot.quest_busy = undefined;
	self.bot.movement_last_origin = self.origin;
	self.bot.movement_last_progress = time;
	self.bot.movement_air_since = undefined;
	self.bot.movement_fall_pending = undefined;
	self.bot.movement_recovery_after = undefined;
	self.bot.update_idle_lookat = time + randomintrange(1000, 3000);
	self.bot.think_interval = 0.1;
	self.bot.threat.entity = undefined;
	self.bot.threat.position = (0, 0, 0);
	self.bot.threat.time_first_sight = 0;
	self.bot.threat.time_recent_sight = 0;
	self.bot.threat.time_aim_interval = 0;
	self.bot.threat.time_aim_correct = 0;
}

bot_main()
{
	self endon("disconnect");
	self endon("bot_relife");
	self endon("death");
	
	level endon("end_game");

	self thread bot_wakeup_think();
	self thread bot_damage_think();
	self thread bot_give_ammo();
	self thread bot_reset_flee_goal();
	self thread bot_update_wander();
	
	for(;;)
	{
		self waittill("wakeup", damage, attacker, direction);
		
		if(self isremotecontrolling())
			continue;
		
		self bot_combat_think(damage, attacker, direction);
		
		if(isdefined(self.bot.is_using_box) && self.bot.is_using_box)
		{
			if(self getgoal("flee") || self hasgoal("flee"))
				self cancelgoal("flee");
			
			if(self getgoal("wander") || self hasgoal("wander"))
				self cancelgoal("wander");
			
			wait 0.05;
			
			continue;
		}

        // Keep generator defenders on the capture objective; they still fight
        // through bot_combat_think above this guard.
        if(is_true(self.bot.is_holding_generator) || is_true(self.bot.is_objective_using))
        {
            wait 0.05;
            continue;
        }
		
		self bot_update_lookat();
		self bot_stand_fix();
		
		if(is_true(level.using_bot_weapon_logic))
		{
            self bot_buy_wallbuy();
			self bot_pap_guns();
			self bot_buy_perks();
		}
		
		if(is_true(level.using_bot_revive_logic))
		{
			self bot_revive_teammates();
			self bot_self_revive_afterlife();
		}
		
		self bot_pickup_powerup();
		self bot_buy_box();
		self bot_buy_door();
		self bot_clear_debris();
		
		wait 0.05;
	}
}

bot_pickup_powerup()
{
	
	if(is_true(self.bot.is_perk_buying) || is_true(self.bot.is_building) || is_true(self.bot.is_crafting))
	{
		if(self getgoal("powerup") || self hasgoal("powerup"))
			self cancelgoal("powerup");
		return;
	}

	powerups = maps\mp\zombies\_zm_powerups::get_powerups(self.origin, 1000);
	
	if(!isdefined(powerups) || powerups.size == 0)
	{
		self cancelgoal("powerup");
		
		return;
	}
	
	foreach(powerup in powerups)
	{
		if(getdvar("mapname") == "zm_prison" && bot_mob_is_cell_block(powerup.origin))
		{
			self cancelgoal("powerup");
			
			continue;
		}
		
		if(!findpath(self.origin, powerup.origin, undefined, 0, 1))
		{
			self cancelgoal("powerup");
			
			continue;
		}
		
		if(distancesquared(self.origin, powerup.origin) > 1000000)
		{
			self cancelgoal("powerup");
			
			continue;
		}
		
		if(is_true(self.bot.is_buying) || is_true(self.bot.is_using_box) || is_true(self.bot.is_reviving) || is_true(self.bot.is_selfreviving))
		{
			self cancelgoal("powerup");
			
			continue;
		}
		
		if(isdefined(powerup.powerup_name) && (powerup.powerup_name == "double_points" || powerup.powerup_name == "insta_kill"))
		{
			zombies_left = level.zombie_total > 0 || get_current_zombie_count() > 0;
			
			if(!zombies_left)
			{
				self cancelgoal("powerup");
				
				continue;
			}
		}
		
		if(isdefined(powerup.powerup_name) && powerup.powerup_name == "nuke")
		{
			zombies_left = level.zombie_total > 0 || get_current_zombie_count() > 0;
			
			if(zombies_left)
			{
				self cancelgoal("powerup");
				
				continue;
			}
		}
		
		self addgoal(powerup.origin, 25, 2, "powerup");
		
		if(self atgoal("powerup") || distancesquared(self.origin, powerup.origin) < 25)
			self cancelgoal("powerup");
		
		return;
	}
}



bot_get_weapon_score(weapon)
{
    if(!isdefined(weapon) || weapon == "none")
		return 0;

	// Buried-only quest weapon priority lives in its map module.
	if(getdvar("mapname") == "zm_buried")
	{
		buried_score = bot_buried_weapon_score_override(weapon);
		if(isdefined(buried_score))
			return buried_score;
	}
    
	if(issubstr(weapon, "ray_gun") || 
	   issubstr(weapon, "mark2") || 
	   issubstr(weapon, "freezegun") || 
	   issubstr(weapon, "tesla") || 
	   issubstr(weapon, "thunder") || 
	   issubstr(weapon, "slipgun") || 
	   issubstr(weapon, "slowgun") || 
	   issubstr(weapon, "blunder") || 
	   issubstr(weapon, "staff"))
	
	   return 100;
		
	if(issubstr(weapon, "minigun") || 
	   issubstr(weapon, "titus") || 
	   
	   issubstr(weapon, "srm1216") || 
	   issubstr(weapon, "saiga12") || 
	   
	   issubstr(weapon, "c96_upgraded") || 
	   issubstr(weapon, "m1911_upgraded") || 
	   issubstr(weapon, "fnp45_upgraded"))
	   
	   return 99;
	
	if(issubstr(weapon, "mg08") || 
	   issubstr(weapon, "hamr") || 
	   issubstr(weapon, "lsat") || 
	   issubstr(weapon, "qbb95"))
	
	   return 98;
	
	if(issubstr(weapon, "rpd") || 
	   issubstr(weapon, "mk48"))
	
	   return 97;
    
	if(issubstr(weapon, "galil") || 
	   issubstr(weapon, "scar"))
	
	   return 96;
	
	if(issubstr(weapon, "mp44") || 
	   issubstr(weapon, "ak47") || 
	   issubstr(weapon, "an94") || 
	   issubstr(weapon, "hk416"))
	
	   return 95;
	
    if(issubstr(weapon, "thompson") || 
	   issubstr(weapon, "ak74u_extclip") || 
	   issubstr(weapon, "pdw57") || 
	   issubstr(weapon, "mp7") || 
	   issubstr(weapon, "evoskorpion") || 
	   issubstr(weapon, "peacekeeper") || 
	   
	   issubstr(weapon, "judge"))
	   
	   return 79;
	
    if(issubstr(weapon, "uzi") || 
	   issubstr(weapon, "mp5") || 
	   issubstr(weapon, "insas") || 
	   issubstr(weapon, "vector_extclip") || 
	   
	   issubstr(weapon, "beretta93r_extclip") || 
	   issubstr(weapon, "rnma"))
	   
	   return 78;
	
    if(issubstr(weapon, "ksg") || 
	   
	   issubstr(weapon, "mp40_stalker") || 
	   
	   issubstr(weapon, "fivesevendw") || 
	   issubstr(weapon, "python"))
	   
	   return 75;
	
	if(issubstr(weapon, "ballistic") || 
	   
	   issubstr(weapon, "m32") || 
	   
	   issubstr(weapon, "870mcs"))
	   
	   return 60;
	
	if(issubstr(weapon, "m14") || 
	   issubstr(weapon, "fal") || 
	   issubstr(weapon, "saritch") || 
	   
	   issubstr(weapon, "rottweil72") || 
	   
	   issubstr(weapon, "barretm82") || 
	   issubstr(weapon, "as50") || 
	   issubstr(weapon, "ballista") || 
	   issubstr(weapon, "dsr50") || 
	   issubstr(weapon, "metalstorm"))
	   
	   return 50;
	
    switch(weaponclass(weapon))
    {
		default:
		case "mg":
		case "spread":
			return 90;
		case "rifle":
			return 80;
		case "smg":
			return 70;
		case "rocketlauncher":
			return 60;
		case "pistol":
			return 50;
    }
}

fire_sale_active()
{
    return is_true(level.zombie_vars["zombie_powerup_fire_sale_on"]);
}

box_is_blocked(box, fire_sale)
{
    if(!isdefined(box) || !isdefined(box.origin))
        return true;

    if(is_true(box._box_open) || flag("moving_chest_now"))
        return true;

    if(isdefined(box.is_locked) && box.is_locked)
        return true;

    if(fire_sale && is_true(box.hidden))
        return true;

    return false;
}

bot_get_fire_sale_box(max_dist_sq)
{
    best_box = undefined;
	
    best_dist_sq = max_dist_sq;

    for(i = 0; i < level.chests.size; i++)
    {
        box = level.chests[i];

        if(box_is_blocked(box, true))
            continue;

        if(isdefined(box.chest_user) && box.chest_user != self)
            continue;

        dist_sq = distancesquared(self.origin, box.origin);

        if(dist_sq >= best_dist_sq)
            continue;

        if(!findpath(self.origin, box.origin, undefined, 0, 1))
            continue;

        best_box = box;
		
        best_dist_sq = dist_sq;
    }

    return best_box;
}

bot_buy_box()
{
	
	if(is_true(self.bot.is_perk_buying) || is_true(self.bot.is_building) || is_true(self.bot.is_crafting))
	{
		if(self getgoal("boxbuy") || self hasgoal("boxbuy"))
			self cancelgoal("boxbuy");
		return;
	}

    fire_sale = fire_sale_active();

    if(fire_sale)
        level.bot_fire_sale_seen = true;
    else if(is_true(level.bot_fire_sale_seen))
    {
        level.bot_fire_sale_seen = undefined;
		
        level.mystery_box_teddy_locations = [];
    }

    min_score = 950;

    if(fire_sale)
        min_score = 10;

    if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand() || self.score < min_score)
    {
        if(self getgoal("boxbuy") || self hasgoal("boxbuy"))
            self cancelgoal("boxbuy");

        return;
    }

    if(!fire_sale && isdefined(self.bot.last_box_interaction_time) && (gettime() - self.bot.last_box_interaction_time < self.bot.box_cooldown_duration))
    {
        if(self getgoal("boxbuy") || self hasgoal("boxbuy"))
            self cancelgoal("boxbuy");

        return;
    }
	
    if(is_true(self.bot.waiting_for_box_animation))
    {
        if((!isdefined(self.bot.box_payment_time) || (gettime() - self.bot.box_payment_time > 10000)))
        {
            self.bot.waiting_for_box_animation = undefined;
            self.bot.current_box = undefined;
            self.bot.is_using_box = undefined;
            self.bot.is_grabbing_box = undefined;

            if(level.box_in_use_by_bot == self)
                level.box_in_use_by_bot = undefined;
        }

        return;
    }

    if(!isdefined(level.chests) || level.chests.size == 0 || !isdefined(level.chest_index) || level.chest_index >= level.chests.size)
        return;

    if(!isdefined(level.bot_check_chest_index))
        level.bot_check_chest_index = level.chest_index;

    if(level.bot_check_chest_index != level.chest_index)
    {
        level.mystery_box_teddy_locations = [];

        level.bot_check_chest_index = level.chest_index;
    }

    detection_dist_sq = 1000000;

    interaction_dist_sq = 30625;

    current_box = undefined;

    if(fire_sale)
        current_box = self bot_get_fire_sale_box(detection_dist_sq);
    else
        current_box = level.chests[level.chest_index];

    if(!isdefined(current_box) || !isdefined(current_box.origin))
    {
        if(self getgoal("boxbuy") || self hasgoal("boxbuy"))
            self cancelgoal("boxbuy");

        return;
    }

    teddy_blocked = false;

    if(!fire_sale && isdefined(level.mystery_box_teddy_locations) && array_contains(level.mystery_box_teddy_locations, current_box.origin))
        teddy_blocked = true;

    if(box_is_blocked(current_box, fire_sale) ||
      (isdefined(current_box.chest_user) && current_box.chest_user != self) ||
      (!fire_sale && isdefined(level.box_in_use_by_bot) && level.box_in_use_by_bot != self) ||
      teddy_blocked)
    {
        if(self getgoal("boxbuy") || self hasgoal("boxbuy"))
            self cancelgoal("boxbuy");

        return;
    }

    dist_sq = distancesquared(self.origin, current_box.origin);

    if(self.score >= min_score && dist_sq < detection_dist_sq)
    {
        if(findpath(self.origin, current_box.origin, undefined, 0, 1))
        {
            if(is_true(self.bot.is_throwing_grenade) || is_true(self.bot.is_getting_shield) || is_true(self.bot.is_buying) || is_true(self.bot.is_reviving) || is_true(self.bot.is_selfreviving))
            {
                if(self getgoal("boxbuy") || self hasgoal("boxbuy"))
                    self cancelgoal("boxbuy");

                return;
            }

            if(dist_sq > interaction_dist_sq)
            {
                if(!self hasgoal("boxbuy") || distancesquared(self getgoal("boxbuy"), current_box.origin) > 30625)
                {
                    self addgoal(current_box.origin, 150, 2, "boxbuy");
                }

                return;
            }

            if(self hasgoal("boxbuy"))
                self cancelgoal("boxbuy");

            aim_offset = (randomfloatrange(-5,5), randomfloatrange(-5,5), randomfloatrange(-5,5));

            self lookat(current_box.origin + aim_offset);

            wait randomfloatrange(0.3, 0.8);

            if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand() || self.score < min_score ||
               box_is_blocked(current_box, fire_sale) || 
			   (isdefined(current_box.chest_user) && current_box.chest_user != self) || 
               fire_sale != fire_sale_active())
            {
                if(self getgoal("boxbuy") || self hasgoal("boxbuy"))
                    self cancelgoal("boxbuy");

                return;
            }

            self.bot.current_box = current_box;
            self.bot.is_using_box = true;
            current_box.chest_user = self;
			
            if(!fire_sale)
                level.box_in_use_by_bot = self;

            self.bot.box_use_in_fire_sale = fire_sale;

            self.bot.waiting_for_box_animation = true;

            self.bot.box_payment_time = gettime();

            self maps\mp\zombies\_zm_score::minus_to_player_score();

            self playsound("zmb_cha_ching");

            if(isdefined(current_box.unitrigger_stub) && isdefined(current_box.unitrigger_stub.trigger))
                current_box.unitrigger_stub.trigger notify("trigger", self);
            else if(isdefined(current_box.use_trigger))
                current_box.use_trigger notify("trigger", self);
            else
                current_box notify("trigger", self);

            self thread bot_monitor_box_animation(current_box);

            return;
        }
    }

    if(self hasgoal("boxbuy"))
        self cancelgoal("boxbuy");
}

bot_monitor_box_animation(box)
{
    self endon("disconnect");
    self endon("death");
	
	level endon("end_game");
	
    self endon("box_usage_complete");
	
    level thread bot_box_cleanup_watcher(self, box);
    
    wait 5;
    
    self.bot.waiting_for_box_animation = undefined;

    if(!isdefined(box) || self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
    {
		if(isdefined(box) && isdefined(box.chest_user) && box.chest_user == self)
			box.chest_user = undefined;
		
        self.bot.current_box = undefined;
        self.bot.is_using_box = undefined;
		
        if(level.box_in_use_by_bot == self)
			level.box_in_use_by_bot = undefined;
		
        self notify("box_usage_complete");
		
        return;
    }

    if(!is_true(box._box_open))
    {
        if(!is_true(self.bot.box_use_in_fire_sale))
        {
            if(!isdefined(level.mystery_box_teddy_locations))
                level.mystery_box_teddy_locations = [];

            if(!array_contains(level.mystery_box_teddy_locations, box.origin))
                level.mystery_box_teddy_locations[level.mystery_box_teddy_locations.size] = box.origin;
        }
		
		if(isdefined(box) && isdefined(box.chest_user) && box.chest_user == self)
			box.chest_user = undefined;
            
        self.bot.current_box = undefined;
        self.bot.is_using_box = undefined;
		
        if(level.box_in_use_by_bot == self)
			level.box_in_use_by_bot = undefined;
		
        self notify("box_usage_complete");
		
        return;
    }
    
    box.chest_user = self;
	
    self lookat(box.origin);
	
    wait 0.2;
    
    box_weapon = undefined;
	
    if(isdefined(box.zbarrier) && isdefined(box.zbarrier.weapon_string))
    {
        box_weapon = box.zbarrier.weapon_string;
    }
    else if(isdefined(box.weapon_string))
    {
        box_weapon = box.weapon_string;
    }

    weapons = self getweaponslistprimaries();
	
    worst_weapon = weapons[0];
	
    weapon_score = 999;
    
    if(isdefined(weapons) && weapons.size > 0)
    {
        foreach(weap in weapons)
        {
            score = bot_get_weapon_score(weap);
			
            if(score < weapon_score)
            {
                weapon_score = score;
				
                worst_weapon = weap;
            }
        }
    }

    if(isdefined(worst_weapon) && self getcurrentweapon() != worst_weapon)
    {
        self switchtoweapon(worst_weapon);
		
        wait 2;
    }

    if(bot_should_take_weapon(box_weapon, worst_weapon))
    {
		self.bot.is_grabbing_box = true;
		
		self allowattack(0);
		self pressads(0);
		
		wait 0.25;
		
		weapons_before = self getweaponslistprimaries();
		
		for(attempt = 0; attempt < 3; attempt++)
        {
			if(is_true(box._box_open) && !self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
            {
                if(isdefined(box.unitrigger_stub) && isdefined(box.unitrigger_stub.trigger))
				{
					self allowattack(0);
					self pressads(0);
					
                    box.unitrigger_stub.trigger notify("trigger", self);
				}
                else if(isdefined(box.use_trigger))
				{
					self allowattack(0);
					self pressads(0);
					
                    box.use_trigger notify("trigger", self);
				}
				else
				{
					self allowattack(0);
					self pressads(0);
					
					box notify("trigger", self);
				}
				
                wait 0.5;
				
                if(self bot_box_weapon_grabbed(box_weapon, weapons_before))
                    break;
                
                if(!is_true(box._box_open))
                    break;
            }
            else
            {
                break;
            }
        }
		
		self.bot.is_grabbing_box = undefined;
    }
    
	if(!is_true(self.bot.box_use_in_fire_sale))
	{
		self.bot.last_box_interaction_time = gettime();

		if(level.round_number <= 8)
			self.bot.box_cooldown_duration = randomintrange(90000, 180000);
		else if(level.round_number <= 15)
			self.bot.box_cooldown_duration = randomintrange(240000, 450000);
		else
			self.bot.box_cooldown_duration = randomintrange(480000, 900000);
	}
	
	self clearlookat();
	
	self.bot.current_box = undefined;
	self.bot.is_using_box = undefined;
    
    if(isdefined(box.chest_user) && box.chest_user == self)
        box.chest_user = undefined;
        
    if(level.box_in_use_by_bot == self)
        level.box_in_use_by_bot = undefined;
        
    self notify("box_usage_complete");
}

bot_box_cleanup_watcher(zm_bots, box)
{
	level endon("end_game");
	
    zm_bots endon("box_usage_complete");
	
    zm_bots waittill_any("death", "disconnect");
	
	zm_bots.bot.waiting_for_box_animation = undefined;
	zm_bots.bot.current_box = undefined;
    zm_bots.bot.is_using_box = undefined;
	zm_bots.bot.is_grabbing_box = undefined;
	
    if(isdefined(box) && isdefined(box.chest_user) && box.chest_user == zm_bots)
        box.chest_user = undefined;
	
    if(isdefined(level.box_in_use_by_bot) && level.box_in_use_by_bot == zm_bots)
        level.box_in_use_by_bot = undefined;
}

bot_weapon_in_list(list, weapon)
{
	if(!isdefined(list))
		return false;
	
	foreach(item in list)
	{
		if(item == weapon)
			return true;
	}
	
	return false;
}

bot_box_weapon_grabbed(box_weapon, weapons_before)
{
	if(isdefined(box_weapon) && self hasweapon(box_weapon))
		return true;
	
	weapons_after = self getweaponslistprimaries();
	
	if(!isdefined(weapons_after) || !isdefined(weapons_before))
		return false;
	
	if(weapons_after.size != weapons_before.size)
		return true;
	
	foreach(weap in weapons_after)
	{
		if(!bot_weapon_in_list(weapons_before, weap))
			return true;
	}
	
	return false;
}

bot_should_take_weapon(boxweapon, currentweapon)
{
	// Let Buried's module force the tactical Time Bomb pickup when its quest needs it.
	if(getdvar("mapname") == "zm_buried" && self bot_buried_should_take_box_weapon(boxweapon))
		return true;

	weapons = self getweaponslistprimaries();
	
	if(isdefined(boxweapon) && isdefined(weapons))
	{
		if(self hasperk("specialty_additionalprimaryweapon") && weapons.size < 3)
		{
			if(bot_get_weapon_score(boxweapon) >= 75)
				return true;
			
			return false;
		}
		
		if(weapons.size < 2)
		{
			if(bot_get_weapon_score(boxweapon) >= 50)
				return true;
			
			return false;
		}
	}
	
    score_current = bot_get_weapon_score(currentweapon);
    
    if(score_current >= 100)
    {
        if(isdefined(boxweapon) && bot_get_weapon_score(boxweapon) >= 100)
            return true;
            
        return false;
    }
    
    if(!isdefined(boxweapon))
    {
        if(score_current >= 90)
            return false;
        
        return true;
    }
	
    score_box = bot_get_weapon_score(boxweapon);

    return score_box >= score_current;
}

bot_buy_wallbuy()
{
	
	if(is_true(self.bot.is_perk_buying) || is_true(self.bot.is_building) || is_true(self.bot.is_crafting))
		return;

	self endon("disconnect");
	self endon("death");
	
	level endon("end_game");
	
    if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
	{
		self cancelgoal("weaponbuy");
		
		return;
	}
	
	if(level.round_number < 2)
	{
		self cancelgoal("weaponbuy");
		
		return;
	}
	
	weapon = self getcurrentweapon();
	
    if(bot_get_weapon_score(weapon) >= 75)
    {
        self cancelgoal("weaponbuy");
		
        return;
    }
	
	if(bot_get_weapon_score(weapon) <= 60)
	{
		if(isdefined(self.bot.next_weak_wallbuy_scan) && gettime() < self.bot.next_weak_wallbuy_scan)
			return;
		
		self.bot.next_weak_wallbuy_scan = gettime() + 8000;
	}
	else
	{
		if(isdefined(self.bot.next_wallbuy_scan) && gettime() < self.bot.next_wallbuy_scan)
			return;
		
		self.bot.next_wallbuy_scan = gettime() + 100000;
	}
	
	weapontobuy = undefined;
	
	if(!isdefined(level._spawned_wallbuys) || level._spawned_wallbuys.size == 0)
		return;
	
	wallbuys = array_randomize(level._spawned_wallbuys);
	
	upgrade_name = maps\mp\zombies\_zm_weapons::get_upgrade_weapon(weapon);
	
	foreach(wallbuy in wallbuys)
	{
		if(!isdefined(wallbuy) || !isdefined(wallbuy.origin))
			continue;
		
		if(!isdefined(wallbuy.trigger_stub))
			continue;
		
		if(!isdefined(wallbuy.trigger_stub.cost))
			continue;
		
		if(!isdefined(wallbuy.trigger_stub.zombie_weapon_upgrade))
			continue;
		
		if(distancesquared(wallbuy.origin, self.origin) < 1000000 && 
		   wallbuy.trigger_stub.cost <= self.score && 
		   bot_best_gun(wallbuy.trigger_stub.zombie_weapon_upgrade, weapon) && 
		   weapon != wallbuy.trigger_stub.zombie_weapon_upgrade && 
		   !is_offhand_weapon(wallbuy.trigger_stub.zombie_weapon_upgrade))
		{
			if(weapon == upgrade_name)
				return;
			
			weapontobuy = wallbuy;
			
			break;
		}
	}
	
	if(!isdefined(weapontobuy))
		return;
	
	has_path = findpath(self.origin, weapontobuy.origin, undefined, 0, 1);
	
	if(!has_path)
	{
		self bot_wallbuy_purchase(weapontobuy);
		
		return;
	}
	
	if(isdefined(self.bot.wallbuy_nav_expiry) && gettime() < self.bot.wallbuy_nav_expiry)
		return;
	
	self thread bot_navigate_and_buy_wallbuy(weapontobuy);
}

bot_navigate_and_buy_wallbuy(weapontobuy)
{
	self endon("disconnect");
	self endon("death");
	
	level endon("end_game");
	
	self.bot.wallbuy_nav_expiry = gettime() + 10000;
	
	self addgoal(weapontobuy.origin, 100, 2, "weaponbuy");
	
	maxtime = gettime() + randomintrange(10000, 15000);
	
	while(!self atgoal("weaponbuy") && distancesquared(self.origin, weapontobuy.origin) > 10000)
	{
		wait 1;
		
        if(self bot_mob_is_afterlife())
		{
			self cancelgoal("weaponbuy");
			
			return;
		}
		
		if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		{
			self cancelgoal("weaponbuy");
			
			return;
		}
		
        if(!self isonground() || self isonladder() || self ismantling())
		{
			self cancelgoal("weaponbuy");
			
			return;
		}
		
		if(gettime() > maxtime)
		{
			self cancelgoal("weaponbuy");
			
			return;
		}
		
        if(is_true(self.bot.is_throwing_grenade) || is_true(self.bot.is_getting_shield) || is_true(self.bot.is_buying) || is_true(self.bot.is_using_box) || is_true(self.bot.is_reviving) || is_true(self.bot.is_selfreviving))
		{
			self cancelgoal("weaponbuy");
			
			return;
		}
	}
	
	self cancelgoal("weaponbuy");
	
	self bot_wallbuy_purchase(weapontobuy);
}

bot_wallbuy_purchase(weapontobuy)
{
	weapon = self getcurrentweapon();
	
	if(weapon == "none")
		return;
	
	if(!isdefined(weapontobuy.trigger_stub))
		return;
	
	if(!isdefined(weapontobuy.trigger_stub.zombie_weapon_upgrade))
		return;
	
	if(self.score < weapontobuy.trigger_stub.cost)
		return;
	
	self.bot.is_buying = true;
	
	self allowattack(0);
	self pressads(0);
	
	self maps\mp\zombies\_zm_score::minus_to_player_score(weapontobuy.trigger_stub.cost);
	
	weapons = self getweaponslistprimaries();
	
	if(isdefined(weapons))
	{
		if(self hasperk("specialty_additionalprimaryweapon") && weapons.size >= 3)
			self takeweapon(weapon);
		
		if(weapons.size >= 2)
			self takeweapon(weapon);
	}
	
	self giveweapon(weapontobuy.trigger_stub.zombie_weapon_upgrade);
	self switchtoweapon(weapontobuy.trigger_stub.zombie_weapon_upgrade);
	self setspawnweapon(weapontobuy.trigger_stub.zombie_weapon_upgrade);
	
	self.bot.is_buying = undefined;
}

bot_best_gun(buyingweapon, currentweapon)
{
    if(maps\mp\zombies\_zm_weapons::get_weapon_cost(buyingweapon) > maps\mp\zombies\_zm_weapons::get_weapon_cost(currentweapon))
        return true;
        
    return false;
}

bot_pap_guns()
{
	
	if(is_true(self.bot.is_perk_buying) || is_true(self.bot.is_building) || is_true(self.bot.is_crafting))
		return;

	if(level.round_number >= 10)
	{
		if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
			return;
		
		if(!self bot_should_pack() || self.score < 5000)
		{
			if(self getgoal("pap") || self hasgoal("pap"))
				self cancelgoal("pap");
			
			return;
		}
		
		if(is_true(self.bot.is_throwing_grenade) || is_true(self.bot.is_getting_shield) || is_true(self.bot.is_buying) || is_true(self.bot.is_using_box) || is_true(self.bot.is_reviving) || is_true(self.bot.is_selfreviving))
			return;
		
		machines = get_cached_vending_machines();
		
		pack = undefined;
		
		foreach(machine in machines)
		{
			if(machine.script_noteworthy != "specialty_weapupgrade" && machine.script_noteworthy != "pack_a_punch" && !isdefined(machine.is_pap))
				continue;
			
			pack = machine;
			
			break;
		}
		
		if(!isdefined(pack) || !isdefined(pack.origin))
		{
			if(self getgoal("pap") || self hasgoal("pap"))
				self cancelgoal("pap");
			
			return;
		}
		
		weapon = self getcurrentweapon();
		
		upgrade_name = maps\mp\zombies\_zm_weapons::get_upgrade_weapon(weapon);
		
		if(issubstr(weapon, "slipgun") && !issubstr(weapon, "upgraded") && weapon == upgrade_name)
			upgrade_name = "slipgun_upgraded_zm";
		
		if(issubstr(weapon, "blunder") && !issubstr(weapon, "upgraded") && weapon == upgrade_name)
			upgrade_name = "blundergat_upgraded_zm";
		
		if(maps\mp\zombies\_zm_weapons::get_base_name(weapon) == upgrade_name)
		{
			if(self getgoal("pap") || self hasgoal("pap"))
				self cancelgoal("pap");
			
			return;
		}
		
		dist_sq = distancesquared(self.origin, pack.origin);
		
		if((getdvar("g_gametype") == "zstandard") || (isdefined(level.scr_zm_ui_gametype_group) && level.scr_zm_ui_gametype_group == "zsurvival"))
			detection_dist_sq = 1000000;
		else
			detection_dist_sq = 999999999;
		
		interaction_dist_sq = 10000;
		
		if(dist_sq >= detection_dist_sq)
		{
			if(self getgoal("pap") || self hasgoal("pap"))
				self cancelgoal("pap");
			
			return;
		}
		
		has_path = findpath(self.origin, pack.origin, undefined, 0, 1);
		
		if(!has_path)
		{
			self bot_pap_gun(weapon, upgrade_name);
			
			return;
		}
		
		if(dist_sq > interaction_dist_sq)
		{
			if(!self hasgoal("pap") || distancesquared(self getgoal("pap"), pack.origin) > 10000)
				self addgoal(pack.origin, 100, 3, "pap");
			
			return;
		}
		
		if(self hasgoal("pap"))
			self cancelgoal("pap");
		
		self lookat(pack.origin);
		
		wait randomfloatrange(0.3, 0.6);
		
		self bot_pap_gun(weapon, upgrade_name);
	}
}

bot_pap_gun(weapon, upgrade_name)
{
	self.bot.is_buying = true;
	
	self allowattack(0);
	self pressads(0);
	
	self maps\mp\zombies\_zm_score::minus_to_player_score(5000);
	
	self takeweapon(weapon);
	self giveweapon(upgrade_name, 0, self maps\mp\zombies\_zm_weapons::get_pack_a_punch_weapon_options(upgrade_name));
	self switchtoweapon(upgrade_name);
	self setspawnweapon(upgrade_name);
	
	self.bot.is_buying = undefined;
	
	self clearlookat();
}

bot_should_pack()
{
	weapon = self getcurrentweapon();
	
	if(issubstr(weapon, "slipgun") && !issubstr(weapon, "upgraded"))
		return 1;
	
	if(issubstr(weapon, "blunder") && !issubstr(weapon, "upgraded"))
		return 1;
	
	if(maps\mp\zombies\_zm_weapons::can_upgrade_weapon(weapon))
		return 1;
	
	return 0;
}

bot_buy_perks()
{
	if(!isdefined(self.bot.perk_purchase_time) || gettime() > self.bot.perk_purchase_time)
	{
		self.bot.perk_purchase_time = gettime() + 15000;

		if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand() ||
		   is_true(self.bot.is_perk_buying) || is_true(self.bot.is_building) ||
		   is_true(self.bot.is_crafting) || is_true(self.bot.is_buying) ||
		   is_true(self.bot.is_using_box) || self getgoal("weaponbuy") ||
		   self hasgoal("weaponbuy") || self getgoal("pap") || self hasgoal("pap") ||
		   self getgoal("boxbuy") || self hasgoal("boxbuy"))
			return;

		machines = get_cached_vending_machines();
		best_machine = undefined;
		best_perk = undefined;
		best_cost = 0;
		best_dist_sq = 999999999;

		// Read each machine's real map-configured cost. This automatically adapts
		// to solo Quick Revive pricing and custom/map-specific perk prices.
		foreach(machine in machines)
		{
			if(!isdefined(machine) || !isdefined(machine.origin) ||
			   !isdefined(machine.script_noteworthy) || !isdefined(machine.cost))
				continue;

			perk = machine.script_noteworthy;

			if(perk == "specialty_weapupgrade" || issubstr(perk, "_upgrade"))
				continue;

			if(isdefined(machine.bot_perk_retry_until) && gettime() < machine.bot_perk_retry_until)
				continue;

			if(isdefined(machine.bot_perk_buyer) && machine.bot_perk_buyer != self &&
			   isdefined(machine.bot_perk_buyer_until) && gettime() < machine.bot_perk_buyer_until &&
			   isalive(machine.bot_perk_buyer))
				continue;

			if(self hasperk(perk) || self maps\mp\zombies\_zm_perks::has_perk_paused(perk) || self.score < machine.cost)
				continue;

			dist_sq = distancesquared(self.origin, machine.origin);

			if(dist_sq >= best_dist_sq)
				continue;

			if(!findpath(self.origin, machine.origin, undefined, 0, 1))
				continue;

			best_machine = machine;
			best_perk = perk;
			best_cost = machine.cost;
			best_dist_sq = dist_sq;
		}

		if(!isdefined(best_machine))
			return;

		// Always use the stock vending trigger, even when already nearby. It
		// enforces map power, score, perk limits, and custom perk validation.
		self thread bot_navigate_and_buy_perk(best_machine, best_perk, best_cost);
	}
}

bot_navigate_and_buy_perk(machine, perk, cost)
{
	self endon("disconnect");
	self endon("bot_relife");
	self endon("death");
	level endon("end_game");

	if(is_true(self.bot.is_perk_buying) || is_true(self.bot.is_building) ||
	   is_true(self.bot.is_crafting) || !isdefined(machine) ||
	   !isdefined(machine.origin) || self hasperk(perk) ||
	   self.score < cost)
		return;

	if(!findpath(self.origin, machine.origin, undefined, 0, 1))
		return;

	self.bot.is_perk_buying = 1;
	machine.bot_perk_buyer = self;
	machine.bot_perk_buyer_until = gettime() + 25000;
	self addgoal(machine.origin, 125, 2, "perkbuy");

	deadline = gettime() + 20000;
	arrived = false;

	while(gettime() < deadline && isdefined(machine) && isdefined(machine.origin))
	{
		if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand() ||
		   is_true(self.bot.is_using_box) || is_true(self.bot.is_buying) ||
		   is_true(self.bot.is_reviving) || is_true(self.bot.is_selfreviving) ||
		   is_true(self.bot.is_throwing_grenade) || self getgoal("weaponbuy") ||
		   self hasgoal("weaponbuy") || self getgoal("pap") || self hasgoal("pap") ||
		   self getgoal("boxbuy") || self hasgoal("boxbuy"))
			break;

		if(self hasperk(perk) || self.score < cost)
			break;

		if(distancesquared(self.origin, machine.origin) <= 3600)
		{
			arrived = true;
			break;
		}

		wait 0.25;
	}

	self cancelgoal("perkbuy");

	if(arrived && isdefined(machine) && isdefined(machine.origin) &&
	   !self hasperk(perk) && self.score >= cost &&
	   !self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
	{
		self lookat(machine.origin + (0, 0, 32));
		self.bot.is_objective_using = 1;
		purchase_detected = false;
		use_deadline = gettime() + 7000;

		// Let the stock vending trigger handle purchase eligibility and consume
		// the correct amount of points; do not grant the perk directly.
		while(gettime() < use_deadline)
		{
			if(!isdefined(machine) || !isdefined(machine.origin) ||
			   self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
				break;

			if(self hasperk(perk) || (isdefined(self.perk_purchased) && self.perk_purchased == perk))
			{
				purchase_detected = true;
				break;
			}

			if(!self isonground() || self isonladder() || self ismantling())
			{
				wait 0.1;
				continue;
			}

			self pressusebutton(0.1);
			wait 0.05;
		}

		self.bot.is_objective_using = undefined;
		self clearlookat();

		if(!purchase_detected && isdefined(machine))
			machine.bot_perk_retry_until = gettime() + 20000;
		else if(isdefined(machine))
			machine.bot_perk_retry_until = undefined;
	}

	if(isdefined(machine) && isdefined(machine.bot_perk_buyer) && machine.bot_perk_buyer == self)
	{
		machine.bot_perk_buyer = undefined;
		machine.bot_perk_buyer_until = undefined;
	}

	self.bot.is_perk_buying = undefined;
}

bot_buy_door()
{
	
	if(is_true(self.bot.is_perk_buying) || is_true(self.bot.is_building) || is_true(self.bot.is_crafting))
		return false;

    doors = get_cached_doors();
	
    if(!isdefined(doors) || doors.size == 0)
        return false;
    
    closestdoor = undefined;
	
    closestdistsq = 90000;
	
    foreach(door in doors)
    {
		if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
			continue;
		
        if(!isdefined(door))
            continue;
		
        if(!isdefined(door.origin))
            continue;
		
        if(isdefined(door._door_open) && door._door_open)
            continue;
        
        if(isdefined(door.has_been_opened) && door.has_been_opened)
            continue;
		
        if(isdefined(door.script_noteworthy))
        {
            if(door.script_noteworthy == "electric_door" || door.script_noteworthy == "local_electric_door")
            {
                if(!flag("power_on"))
                    continue;
            }
        }
		
		if(!isdefined(door.zombie_cost) || door.zombie_cost <= 0)
			continue;
		
        if(self.score < door.zombie_cost)
            continue;
		
		if(isdefined(door.bot_door_claimer) && door.bot_door_claimer != self)
		{
			if(!isalive(door.bot_door_claimer) || (isdefined(door.bot_door_claim_time) && gettime() - door.bot_door_claim_time > 4000))
			{
				door.bot_door_claimer = undefined;
			}
			else
			{
				continue;
			}
		}
		
        dist_sq = distancesquared(self.origin, door.origin);
		
        if(dist_sq < closestdistsq)
        {
            closestdoor = door;
			
            closestdistsq = dist_sq;
        }
    }
	
    if(isdefined(closestdoor))
    {
		closestdoor.bot_door_claimer = self;
		
		closestdoor.bot_door_claim_time = gettime();
		
		if((isdefined(closestdoor._door_open) && closestdoor._door_open) || (isdefined(closestdoor.has_been_opened) && closestdoor.has_been_opened))
		{
			closestdoor.bot_door_claimer = undefined;
			
			return false;
		}
		
        self maps\mp\zombies\_zm_score::minus_to_player_score(closestdoor.zombie_cost);
        
        closestdoor thread bot_finish_door_open();
        
        self playsound("zmb_cha_ching");
		
        return true;
    }
	
	return false;
}

bot_finish_door_open()
{
    self endon("death");
    
    if(isdefined(self.door_buy))
    {
        self door_buy();
    }
    else
    {
        self maps\mp\zombies\_zm_blockers::door_opened(self.zombie_cost);
    }
    
    self._door_open = 1;
	
    self.has_been_opened = 1;
	
	self.bot_door_claimer = undefined;
}

bot_clear_debris()
{
	
	if(is_true(self.bot.is_perk_buying) || is_true(self.bot.is_building) || is_true(self.bot.is_crafting))
		return false;

	if(getdvar("mapname") == "zm_buried")
		return;
	
    debris = get_cached_debris();
    
    if(!isdefined(debris) || debris.size == 0)
        return false;
    
    closestdebris = undefined;
	
    closestdistsq = 90000;
    
    foreach(pile in debris)
    {
		if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
			continue;
		
        if(!isdefined(pile))
            continue;
		
        if(!isdefined(pile.origin))
            continue;
        
        if(isdefined(pile._door_open) && pile._door_open)
            continue;
        
        if(isdefined(pile.has_been_opened) && pile.has_been_opened)
            continue;
		
		if(!isdefined(pile.zombie_cost) || pile.zombie_cost <= 0)
			continue;
		
		if(!isdefined(pile.target))
			continue;
        
        if(self.score < pile.zombie_cost)
            continue;
        
        dist_sq = distancesquared(self.origin, pile.origin);
		
        if(dist_sq < closestdistsq)
        {
            closestdebris = pile;
			
            closestdistsq = dist_sq;
        }
    }
    
	if(isdefined(closestdebris))
	{
		self maps\mp\zombies\_zm_score::minus_to_player_score(closestdebris.zombie_cost);
		
		closestdebris notify("trigger", self);
		
		if(isdefined(closestdebris.trigger))
			closestdebris.trigger notify("trigger", self);
		
		targets = getentarray(closestdebris.target, "targetname");
		
		foreach(target in targets)
		{
			if(isdefined(target))
			{
				target notify("trigger", self);
			}
		}
		
		if(isdefined(closestdebris.script_flag))
		{
			tokens = strtok(closestdebris.script_flag, ",");
			
			for(i = 0; i < tokens.size; i++)
			{
				flag_set(tokens[i]);
			}
		}
		
		play_sound_at_pos("purchase", closestdebris.origin);
		
		junk = getentarray(closestdebris.target, "targetname");
		
		level notify("junk purchased");
		
		foreach(chunk in junk)
		{
			if(!isdefined(chunk))
				continue;
			
			chunk connectpaths();
			
			if(isdefined(chunk.script_linkto))
			{
				struct = getstruct(chunk.script_linkto, "script_linkname");
				
				if(isdefined(struct))
				{
					chunk thread maps\mp\zombies\_zm_blockers::debris_move(struct);
				}
				else
					chunk delete();
				
				continue;
			}
			
			chunk delete();
		}
		
		all_trigs = getentarray(closestdebris.target, "target");
		
		foreach(trig in all_trigs)
		{
			if(isdefined(trig))
				trig delete();
		}
		
		closestdebris._door_open = 1;
		
		closestdebris.has_been_opened = 1;
		
		return true;
	}
	
    return false;
}

bot_count_nearby_zombies(radius)
{
    return self bot_count_zombies_near_origin(self.origin, radius);
}

bot_count_zombies_near_origin(origin, radius)
{
    zombies = get_cached_zombies();

    if(!isdefined(zombies))
        return 0;

    radius_sq = radius * radius;
    count = 0;

    foreach(zombie in zombies)
    {
        if(!isdefined(zombie) || !isalive(zombie))
            continue;

        if(distancesquared(origin, zombie.origin) <= radius_sq)
            count++;
    }

    return count;
}

bot_revive_teammates()
{
    if(!maps\mp\zombies\_zm_laststand::player_any_player_in_laststand() || self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
    {
        if(self getgoal("revive") || self hasgoal("revive"))
        {
            if(isdefined(self.bot.revive_target))
            {
                if(isdefined(self.bot.revive_target.revive_claimer_count) && self.bot.revive_target.revive_claimer_count > 0)
                    self.bot.revive_target.revive_claimer_count--;
				
                self.bot.revive_target = undefined;
            }
                
            self cancelgoal("revive");
        }
            
        self.bot.is_reviving = false;
		
        return;
    }
    
    if(is_true(self.bot.is_reviving))
        return;
    
    if(!self hasgoal("revive"))
    {
        if(isdefined(self.bot.next_revive_scan) && gettime() < self.bot.next_revive_scan)
            return;

        self.bot.next_revive_scan = gettime() + 750;
        teammate = self get_closest_downed_teammate();
        
        if(!isdefined(teammate))
            return;

        if(isdefined(self.bot.revive_claim_blocked_until) && gettime() < self.bot.revive_claim_blocked_until)
		{
			if(distancesquared(self.origin, teammate.origin) < 160000)
				self.bot.revive_claim_blocked_until = 0;
			else
	            return;
		}
		
        if(!isdefined(teammate.revive_claimer_count))
            teammate.revive_claimer_count = 0;
		
        teammate.revive_claimer_count++;
		
		teammate.revive_last_claim_time = gettime();
		
        self.bot.revive_target = teammate;
		
        self.bot.revive_last_dist = undefined;
        
        self addgoal(teammate.origin, 50, 3, "revive");
    }
    else
    {
        if(isdefined(self.bot.revive_target) && !self.bot.revive_target maps\mp\zombies\_zm_laststand::player_is_in_laststand())
        {
            if(isdefined(self.bot.revive_target.revive_claimer_count) && self.bot.revive_target.revive_claimer_count > 0)
				self.bot.revive_target.revive_claimer_count--;
			
            self.bot.revive_target = undefined;
			
            self cancelgoal("revive");
			
            return;
        }
		
		if(isdefined(self.bot.revive_target) && !is_true(self.bot.is_reviving))
		{
			real_player_reviving = isdefined(self.bot.revive_target.revivetrigger) && is_true(self.bot.revive_target.revivetrigger.beingrevived);
			
			if(is_true(self.bot.revive_target.being_revived) || real_player_reviving)
			{
				if(isdefined(self.bot.revive_target.revive_claimer_count) && self.bot.revive_target.revive_claimer_count > 0)
					self.bot.revive_target.revive_claimer_count--;
				
				self.bot.revive_target = undefined;
				
				self cancelgoal("revive");
				
				return;
			}
		}
		
        if(self atgoal("revive") || distancesquared(self.origin, self getgoal("revive")) < 5625)
        {
            teammate = self.bot.revive_target;
            
            if(!isdefined(teammate))
            {
                self cancelgoal("revive");
				
                return;
            }
			
            self thread bot_simulate_revive(teammate);
			
			return;
        }
		
		if(!isdefined(self.bot.revive_progress_check_time) || gettime() >= self.bot.revive_progress_check_time)
		{
			self.bot.revive_progress_check_time = gettime() + 2000;
			
			teammate = self.bot.revive_target;
			
			if(isdefined(teammate))
			{
				current_dist = distance(self.origin, teammate.origin);
				
				made_progress = !isdefined(self.bot.revive_last_dist) || current_dist < self.bot.revive_last_dist - 100;
				
				self.bot.revive_last_dist = current_dist;
				
				surrounded = self bot_count_nearby_zombies(200) >= 3;
				
				if(!made_progress && surrounded)
				{
					if(isdefined(teammate.revive_claimer_count) && teammate.revive_claimer_count > 0)
						teammate.revive_claimer_count--;
					
					self.bot.revive_target = undefined;
					
					self.bot.revive_last_dist = undefined;
					
					self.bot.revive_claim_blocked_until = gettime() + 3000;
					
					self cancelgoal("revive");
					
					return;
				}
			}
		}
    }
}

bot_simulate_revive(teammate)
{
    self endon("disconnect");
	self endon("death");
	
	level endon("end_game");
    
    current_weapon = self getcurrentweapon();
    
    if(current_weapon == "none" || current_weapon == "revive_weapon_zm")
    {
        weapons = self getweaponslistprimaries();
		
        if(isdefined(weapons) && weapons.size > 0)
            current_weapon = weapons[0];
    }
    
    self.bot.is_reviving = true;
	
    teammate.being_revived = true;
    
    level thread bot_revive_cleanup_watcher(self, teammate);
    
    self cancelgoal("revive");
    
    self lookat(teammate.origin);
    
    while(isdefined(teammate) && teammate maps\mp\zombies\_zm_laststand::player_is_in_laststand() && !self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
    {
        self allowattack(0);
		self pressads(0);
		
        self bot_clear_enemy();
		
        if(distancesquared(self.origin, teammate.origin) > 10000)
            break;
        
        self lookat(teammate.origin);
		
        self pressusebutton(2);
		
        wait 0.05;
    }
    
    wait 0.6;
    
    if(!self maps\mp\zombies\_zm_laststand::player_is_in_laststand() && isdefined(current_weapon) && current_weapon != "none")
        self switchtoweapon(current_weapon);

    if(isdefined(teammate))
        teammate.being_revived = false;
	
    self.bot.is_reviving = false;
	
	self clearlookat();
}

bot_revive_cleanup_watcher(reviving_bot, teammate)
{
	level endon("end_game");
	
    while(true)
    {
        wait 0.1;
        
        if(!isdefined(reviving_bot) || !isalive(reviving_bot))
        {
            if(isdefined(teammate))
            {
                teammate.being_revived = false;
				
                if(isdefined(teammate.revive_claimer_count) && teammate.revive_claimer_count > 0)
                    teammate.revive_claimer_count--;
            }
			
            return;
        }
        
        if(!isdefined(teammate) || !teammate maps\mp\zombies\_zm_laststand::player_is_in_laststand())
        {
            if(isdefined(teammate))
            {
                teammate.being_revived = false;
				
                if(isdefined(teammate.revive_claimer_count) && teammate.revive_claimer_count > 0)
                    teammate.revive_claimer_count--;
            }
			
            return;
        }
        
        if(!is_true(reviving_bot.bot.is_reviving) && !reviving_bot hasgoal("revive"))
        {
            if(isdefined(teammate))
            {
                if(isdefined(teammate.revive_claimer_count) && teammate.revive_claimer_count > 0)
                    teammate.revive_claimer_count--;
            }
			
            return;
        }
    }
}

get_active_revive_point()
{
	if(!maps\mp\zombies\_zm_laststand::player_any_player_in_laststand())
		return undefined;

	best = undefined;
	
	best_distsq = 999999999;

	foreach(player in get_players())
	{
		if(!player maps\mp\zombies\_zm_laststand::player_is_in_laststand())
			continue;

		distsq = distancesquared(self.origin, player.origin);

		if(distsq < best_distsq)
		{
			best_distsq = distsq;
			
			best = player;
		}
	}

	return best;
}

get_closest_downed_teammate()
{
    if(!maps\mp\zombies\_zm_laststand::player_any_player_in_laststand())
        return;

    best_player = undefined;
    best_score = 999999999;

    foreach(player in get_players())
    {
        if(!isdefined(player) || !isdefined(player.origin))
            continue;

        if(!player maps\mp\zombies\_zm_laststand::player_is_in_laststand())
            continue;

        if((is_true(player.being_revived) || (isdefined(player.revivetrigger) && is_true(player.revivetrigger.beingrevived))) && self.bot.revive_target != player)
            continue;

        time_since_last_claim = gettime() - (isdefined(player.revive_last_claim_time) ? player.revive_last_claim_time : 0);
        claimer_count = isdefined(player.revive_claimer_count) ? player.revive_claimer_count : 0;

        if(claimer_count >= 2 && self.bot.revive_target != player && time_since_last_claim <= 10000)
            continue;

        // Don't assign a revive target the bot cannot path to.
        if(!findpath(self.origin, player.origin, undefined, 0, 1))
            continue;

        distance_to_player = distance(self.origin, player.origin);
        nearby_danger = self bot_count_zombies_near_origin(player.origin, 300);

        // Prefer reachable, nearby teammates with a safer approach and fewer assigned revivers.
        score = distance_to_player + (nearby_danger * 150) + (claimer_count * 500);

        if(self.bot.revive_target == player)
            score -= 250;

        if(score < best_score)
        {
            best_score = score;
            best_player = player;
        }
    }

    return best_player;
}

bot_self_revive_afterlife()
{
    if(!is_true(self.afterlife) || !isdefined(self.e_afterlife_corpse))
    {
        if(self getgoal("selfrevive") || self hasgoal("selfrevive"))
            self cancelgoal("selfrevive");

        self.bot.is_selfreviving = false;
        return;
    }

    // Mob bots should finish their Afterlife objectives first. The map AI
    // overrides this only when all supported ghost work is complete or mana
    // is low enough that returning becomes the survival priority.
    if(getdvar("mapname") == "zm_prison" &&
       self bot_mob_is_afterlife() &&
       !self bot_mob_afterlife_should_return())
    {
        if(self getgoal("selfrevive") || self hasgoal("selfrevive"))
            self cancelgoal("selfrevive");

        self.bot.is_selfreviving = false;
        return;
    }

    if(is_true(self.bot.is_selfreviving))
        return;

    corpse = self.e_afterlife_corpse;
    revive_origin = corpse.origin;

    if(getdvar("mapname") == "zm_prison")
    {
        // The corpse creates its own linked revive trigger shortly after it
        // spawns. Navigate to that actual trigger volume, not just the clone.
        if(!isdefined(corpse.revivetrigger) || !isdefined(corpse.revivetrigger.origin))
            return;

        revive_origin = corpse.revivetrigger.origin;
    }

    if(!self hasgoal("selfrevive"))
    {
        self addgoal(revive_origin, 42, 3, "selfrevive");
        return;
    }

    if(self atgoal("selfrevive") ||
       distancesquared(self.origin, revive_origin) <= 55 * 55)
        self thread bot_simulate_self_revive(corpse);
}

bot_simulate_self_revive(corpse)
{
    self endon("disconnect");
    self endon("death");

    level endon("end_game");

    self.bot.is_selfreviving = true;

    self cancelgoal("selfrevive");
	
    self lookat(corpse.origin);

    while(is_true(self.afterlife) && isdefined(self.e_afterlife_corpse) && self.e_afterlife_corpse == corpse)
    {
        self bot_clear_enemy();

        if(distancesquared(self.origin, corpse.origin) > 10000)
            break;

        self lookat(corpse.origin);

        self pressusebutton(2);

        wait 0.05;
    }
	
    self.bot.is_selfreviving = false;
	
    self clearlookat();
}

manual_bot_teleport_monitor()
{
    self endon("disconnect");
    level endon("end_game");

    // F7 is bound to Action Slot 3. One press teleports the whole bot group.
    self notifyonplayercommand("teleport_pressed", "+actionslot 3");

    for(;;)
    {
        self waittill("teleport_pressed");
        self execute_bot_teleport();
        wait 0.75;
    }
}

execute_bot_teleport()
{
    if(self isonground())
    {
        bots_to_teleport = [];
		
        players = get_players();
        
        foreach(player in players)
        {
            if(isdefined(player.bot))
                bots_to_teleport[bots_to_teleport.size] = player;
        }
        
        if(bots_to_teleport.size > 0)
        {
            offsets = [];
			
            offsets[0] = (50,   0,  0);
            offsets[1] = (-50,  0,  0);
            offsets[2] = (0,   50,  0);
            offsets[3] = (0,  -50,  0);
            
            self thread bot_staggered_teleport(bots_to_teleport, offsets);
        }
    }
    else 
    {
        self iprintln("You must be on the ground to teleport the bots.");
    }
}

bot_staggered_teleport(bots_to_teleport, offsets)
{
	self endon("disconnect");
    self endon("death");
	
    level endon("end_game");
    
    teleported = 0;
    
    for(i = 0; i < bots_to_teleport.size; i++)
    {
        bot = bots_to_teleport[i];
        
        if(!isdefined(bot))
            continue;
        
        offset = offsets[i % offsets.size];
        
        bot setorigin(self.origin + offset);
		
        teleported++;
        
        if(i < bots_to_teleport.size - 1)
            wait randomfloatrange(0.2, 0.4);
    }
    
    if(teleported > 0)
        self iprintln("Bots teleported! (" + teleported + "/" + bots_to_teleport.size + ")");
}

bot_command_mode_monitor()
{
    self endon("disconnect");
    level endon("end_game");

    // F6 is bound to Action Slot 4. Slots 1/2 stay exclusive to menu scrolling.
    self notifyonplayercommand("command_pressed", "+actionslot 4");

    for(;;)
    {
        self waittill("command_pressed");
        self bot_cycle_command_mode();
        wait 0.35;
    }
}

bot_cycle_command_mode()
{
    if(!isdefined(level.bot_command_mode))
        level.bot_command_mode = "stay";

    if(level.bot_command_mode == "stay")
        level.bot_command_mode = "wander";
    else if(level.bot_command_mode == "wander")
        level.bot_command_mode = "wander_further";
    else if(level.bot_command_mode == "wander_further")
        level.bot_command_mode = "follow";
	else
		level.bot_command_mode = "stay";
	
    level.bot_commander = self;
	
    foreach(player in get_players())
    {
        if(!isdefined(player.bot))
            continue;

        if(level.bot_command_mode == "stay")
            player.bot.stay_pos = player.origin;
        else
            player.bot.stay_pos = undefined;
    }
	
	bot_set_dvars();
	
    self iprintlnbold("Bots: " + level.bot_command_mode);
}

bot_update_wander()
{
	self endon("disconnect");
	self endon("bot_relife");
	self endon("death");
	
	level endon("end_game");
	
	for(;;)
	{
		wait 0.1;

        // A generator defender must not have its objective goal overwritten by
        // the normal stay/follow/wander controller.
        if(is_true(self.bot.is_holding_generator) || is_true(self.bot.is_objective_using))
        {
            if(self getgoal("wander") || self hasgoal("wander"))
                self cancelgoal("wander");

            wait 0.05;
            continue;
        }
		
		if(is_true(self.bot.is_building) || is_true(self.bot.is_crafting) || is_true(self.bot.is_perk_buying))
		{
			if(self getgoal("wander") || self hasgoal("wander"))
				self cancelgoal("wander");

			wait 0.1;
			continue;
		}

		if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		{
			if(self getgoal("wander") || self hasgoal("wander"))
				self cancelgoal("wander");
			
			wait 0.05;
			
			continue;
		}
		
        if(is_true(self.bot.is_buying) || is_true(self.bot.is_using_box) || is_true(self.bot.is_reviving) || is_true(self.bot.is_selfreviving))
		{
			if(self getgoal("wander") || self hasgoal("wander"))
				self cancelgoal("wander");
			
			wait 0.05;
			
			continue;
		}
		
		if(self getgoal("flee") || self hasgoal("flee"))
		{
			if(self getgoal("wander") || self hasgoal("wander"))
				self cancelgoal("wander");
			
			wait 0.05;
			
			continue;
		}
		
		downed = self get_active_revive_point();
		
		is_revive_claimer = isdefined(self.bot.revive_target) && isdefined(downed) && self.bot.revive_target == downed;
		
		if(isdefined(downed) && !is_revive_claimer)
		{
			guard_count = isdefined(downed.guard_claimer_count) ? downed.guard_claimer_count : 0;
			
			already_guarding_this = isdefined(self.bot.guard_target) && self.bot.guard_target == downed;
			
			if((guard_count < 2 || already_guarding_this) && distancesquared(self.origin, downed.origin) < 1000000)
			{
				if(!already_guarding_this)
				{
					if(isdefined(self.bot.guard_target) && isdefined(self.bot.guard_target.guard_claimer_count) && self.bot.guard_target.guard_claimer_count > 0)
						self.bot.guard_target.guard_claimer_count--;
					
					self.bot.guard_target = downed;
					
					downed.guard_claimer_count = guard_count + 1;
				}
				
				if(!isdefined(self.bot.guard_offset) || self.bot.guard_target != downed)
				{
					angle = randomfloatrange(0, 360);
					
					self.bot.guard_offset = (cos(angle) * 150, sin(angle) * 150, 0);
				}
				
				guard_spot = downed.origin + self.bot.guard_offset;
				
				if(!self hasgoal("wander") || distancesquared(self getgoal("wander"), guard_spot) > 40000)
				{
					self cancelgoal("wander");
					
					self addgoal(guard_spot, 100, 2, "wander");
				}
				
				wait 0.05;
				
				continue;
			}
		}
		else if(isdefined(self.bot.guard_target))
		{
			if(isdefined(self.bot.guard_target.guard_claimer_count) && self.bot.guard_target.guard_claimer_count > 0)
				self.bot.guard_target.guard_claimer_count--;
			
			self.bot.guard_target = undefined;
			
			self.bot.guard_offset = undefined;
		}
		
		player = undefined;
		
		// Follow the player who issued the command whenever possible.
		if(isdefined(level.bot_command_mode) && level.bot_command_mode == "follow" && isdefined(level.bot_commander))
		{
			commander = level.bot_commander;
			
			if(isdefined(commander.origin) && isalive(commander) && !isdefined(commander.bot) &&
			   !(isdefined(commander.pers) && isdefined(commander.pers["isbot"])))
				player = commander;
		}
		
		// If the commander is no longer available, fall back to a living human.
		if(!isdefined(player))
		{
			foreach(candidate in get_players())
			{
				if(!isdefined(candidate) || !isdefined(candidate.origin))
					continue;
				
				if((isdefined(candidate.pers) && isdefined(candidate.pers["isbot"])) || isdefined(candidate.bot))
					continue;
				
				if(!isalive(candidate))
					continue;
				
				player = candidate;
				break;
			}
		}
		
		if(isdefined(level.bot_command_mode) && level.bot_command_mode != "wander")
		{
			if(level.bot_command_mode == "stay" && isdefined(level.bot_commander))
			{
				if(!isdefined(self.bot.stay_pos))
					self.bot.stay_pos = self.origin;
				
				if(!self hasgoal("wander") || distancesquared(self getgoal("wander"), self.bot.stay_pos) > 16)
				{
					self cancelgoal("wander");
					
					self addgoal(self.bot.stay_pos, 40, 1, "wander");
				}
				
				wait 0.05;
				
				continue;
			}
		}
		
		if(isdefined(level.bot_command_mode) && level.bot_command_mode != "wander")
		{
			if(level.bot_command_mode == "follow" && isdefined(level.bot_commander))
			{
				if(isdefined(player))
				{
					dist_sq = distancesquared(self.origin, player.origin);
					current_time = gettime();
					
					// Stay close to the commander instead of continuously overshooting them.
					if(dist_sq < 5625)
					{
						self.bot.is_following = false;
						if(self getgoal("wander") || self hasgoal("wander"))
							self cancelgoal("wander");
						wait 0.05;
						continue;
					}
					
					if(isdefined(self.bot.follow_blocked) && current_time < self.bot.follow_blocked)
					{
						self.bot.is_following = false;
						wait 0.05;
						continue;
					}
					
					// Path checks are deliberately throttled; the commander moves every frame.
					if(!isdefined(self.bot.follow_path_check) || current_time >= self.bot.follow_path_check)
					{
						self.bot.follow_path_check = current_time + 1000;
						if(!findpath(self.origin, player.origin, undefined, 0, 1))
						{
							waypoint = self bot_movement_find_waypoint(player.origin, 900);
							if(isdefined(waypoint))
							{
								self.bot.is_following = true;
								self.bot.follow_blocked = current_time + 3000;
								self cancelgoal("wander");
								self addgoal(waypoint, 52, 2, "wander");
							}
							else
							{
								self.bot.is_following = false;
								self.bot.follow_blocked = current_time + 3500;
								if(self getgoal("wander") || self hasgoal("wander"))
									self cancelgoal("wander");
							}
						}
						else
						{
							self.bot.is_following = true;
							self.bot.follow_blocked = undefined;
						}
					}
					
					if(self.bot.is_following)
					{
						current_goal = self getgoal("wander");
						if(!isdefined(current_goal) || distancesquared(current_goal, player.origin) > 4096)
							self addgoal(player.origin, 75, 1, "wander");
					}
					
					wait 0.05;
					continue;
				}
				else
				{
					self.bot.is_following = false;
					if(self getgoal("wander") || self hasgoal("wander"))
						self cancelgoal("wander");
					wait 0.05;
					continue;
				}
			}
		}
		
		if(isdefined(level.bot_command_mode) && (level.bot_command_mode == "wander" || level.bot_command_mode == "wander_further"))
		{
			if((level.bot_command_mode == "wander" || level.bot_command_mode == "wander_further") && isdefined(level.bot_commander))
			{
				if(!isdefined(self.bot.last_wander_pos))
				{
					self.bot.last_wander_pos = self.origin;
					
					self.bot.wander_stay_time = gettime();
				}
				
				if(distancesquared(self.origin, self.bot.last_wander_pos) > 256) 
				{
					self.bot.last_wander_pos = self.origin;
					
					self.bot.wander_stay_time = gettime();
				}
				
				time_at_point = (gettime() - self.bot.wander_stay_time) / 1000;
				
				if(!self hasgoal("wander") || self atgoal("wander") || time_at_point >= 12)
				{
					if(level.bot_command_mode == "wander_further")
					{
						location = wander_further_get_wander_location(self.origin, 3000, self);
						
						if(isdefined(location) && location == self.origin)
							location = undefined;
					}
					else
					{
						location = self get_wander_location(self.origin, 1000);
					}
					
					if(isdefined(location))
					{
						self cancelgoal("wander");
						
						self addgoal(location, 100, 1, "wander");
						
						self.bot.last_wander_pos = self.origin;
						
						self.bot.wander_stay_time = gettime();
					}
				}
			}
		}
	}
}

// Recover only the general movement goal. Objective-specific goals remain owned
// by their quest/build/revive workers, and native launch/elevator movement is
// never interrupted while the bot is airborne or attached to a transport.
bot_movement_recovery_think()
{
	self endon("disconnect");
	self endon("bot_relife");
	self endon("death");
	level endon("end_game");

	wait 2;
	self.bot.movement_last_origin = self.origin;
	self.bot.movement_last_progress = gettime();

	for(;;)
	{
		wait 0.5;
		now = gettime();

		if(is_true(self.bot.is_objective_using) || is_true(self.bot.is_building) ||
		   is_true(self.bot.is_crafting) || is_true(self.bot.is_perk_buying) ||
		   is_true(self.bot.is_buying) || is_true(self.bot.is_using_box) ||
		   is_true(self.bot.is_reviving) || is_true(self.bot.is_selfreviving) ||
		   is_true(self.bot.is_parkour) || is_true(self.bot.is_parkouring) ||
		   is_true(self._padded) || is_true(self.lander))
		{
			self.bot.movement_last_origin = self.origin;
			self.bot.movement_last_progress = now;
			self.bot.movement_air_since = undefined;
			continue;
		}

		// Let the stock jump/landing, fall, ladder and mantle systems finish.
		// A long unplanned fall is remembered; after landing, the route is rebuilt.
		if(!self isonground() || self isonladder() || self ismantling())
		{
			if(!isdefined(self.bot.movement_air_since))
				self.bot.movement_air_since = now;
			else if(now - self.bot.movement_air_since >= 1800)
				self.bot.movement_fall_pending = 1;

			self.bot.movement_last_origin = self.origin;
			continue;
		}

		landed_after_fall = isdefined(self.bot.movement_air_since);
		if(landed_after_fall)
		{
			if(now - self.bot.movement_air_since >= 1800)
				self.bot.movement_fall_pending = 1;
			self.bot.movement_air_since = undefined;
			self.bot.movement_last_origin = self.origin;
			self.bot.movement_last_progress = now;
		}

		if(isdefined(self.bot.movement_recovery_after) && now < self.bot.movement_recovery_after)
			continue;

		if(!self hasgoal("wander"))
		{
			self.bot.movement_last_origin = self.origin;
			self.bot.movement_last_progress = now;
			self.bot.movement_fall_pending = undefined;
			continue;
		}

		goal = self getgoal("wander");
		if(!isdefined(goal) || distancesquared(self.origin, goal) <= 6400 || self atgoal("wander"))
		{
			self.bot.movement_last_origin = self.origin;
			self.bot.movement_last_progress = now;
			self.bot.movement_fall_pending = undefined;
			continue;
		}

		if(distancesquared(self.origin, self.bot.movement_last_origin) >= 900)
		{
			self.bot.movement_last_origin = self.origin;
			self.bot.movement_last_progress = now;
			continue;
		}

		stuck = now - self.bot.movement_last_progress >= 8000;
		if(!stuck && !is_true(self.bot.movement_fall_pending))
			continue;

		waypoint = self bot_movement_find_waypoint(goal, 1000);
		if(isdefined(waypoint))
		{
			self cancelgoal("wander");
			self addgoal(waypoint, 48, 2, "wander");
			self.bot.movement_recovery_after = now + 3500;
		}
		else
			self.bot.movement_recovery_after = now + 2500;

		self.bot.movement_fall_pending = undefined;
		self.bot.movement_last_origin = self.origin;
		self.bot.movement_last_progress = now;
	}
}

// Select a reachable navigation node that makes measurable progress toward
// the final target. This avoids random coordinates and rejects disabled zones.
bot_movement_find_waypoint(target_origin, search_radius)
{
	if(!isdefined(target_origin))
		return undefined;
	if(!isdefined(search_radius) || search_radius < 256)
		search_radius = 800;

	current_target_distance = distancesquared(self.origin, target_origin);
	nodes = getnodesinradius(self.origin, search_radius, 0, search_radius, "any", 256);
	if(!isdefined(nodes) || nodes.size == 0)
		return undefined;

	best = undefined;
	best_score = 999999999;
	checks = 0;
	foreach(node in nodes)
	{
		if(checks >= 32)
			break;
		if(!isdefined(node) || !isdefined(node.origin))
			continue;
		if(!check_point_in_playable_area(node.origin))
			continue;

		progress_distance = distancesquared(node.origin, target_origin);
		if(progress_distance >= current_target_distance - 14400)
			continue;

		if(isdefined(level.zones))
		{
			zone = maps\mp\zombies\_zm_zonemgr::get_zone_from_position(node.origin + (0, 0, 32), 1);
			if(isdefined(zone) && !maps\mp\zombies\_zm_zonemgr::zone_is_enabled(zone))
				continue;
		}

		checks++;
		if(!findpath(self.origin, node.origin, undefined, 0, 1))
			continue;

		score = progress_distance + distancesquared(self.origin, node.origin) * 0.2;
		if(score < best_score)
		{
			best_score = score;
			best = node.origin;
		}
	}

	return best;
}

wander_further_get_wander_location(origin, range, player)
{
	if(!isdefined(player) || !isdefined(player.bot))
		return undefined;

	if(!isdefined(player.bot.wander_retry) || gettime() >= player.bot.wander_retry)
	{
		timer = gettime();

		if(!isdefined(player.bot.wander_visited))
			player.bot.wander_visited = [];

		fresh = [];

		foreach(entry in player.bot.wander_visited)
		{
			if(isdefined(entry.expire) && entry.expire > timer)
				fresh[fresh.size] = entry;
		}

		player.bot.wander_visited = fresh;

		// Use actual navigation nodes: random 3D coordinates and zero-length
		// bullet traces do not reliably identify walkable destinations.
		nodes = getnodesinradius(origin, range, 0, range, "any", 256);

		if(!isdefined(nodes) || nodes.size == 0)
		{
			player.bot.wander_retry = timer + 1500;
			return undefined;
		}

		nodes = array_randomize(nodes);
		skipped_cooldown = false;
		checked_paths = 0;

		foreach(node in nodes)
		{
			if(checked_paths >= 24)
				break;

			if(!isdefined(node) || !isdefined(node.origin))
				continue;

			dist_sq = distancesquared(origin, node.origin);
			min_dist_sq = (range * 0.35) * (range * 0.35);

			if(dist_sq < min_dist_sq || dist_sq > (range * range))
				continue;

			if(!check_point_in_playable_area(node.origin))
				continue;

			if(isdefined(level.zones))
			{
				zone = maps\mp\zombies\_zm_zonemgr::get_zone_from_position(node.origin + (0, 0, 32), 1);

				if(isdefined(zone) && !maps\mp\zombies\_zm_zonemgr::zone_is_enabled(zone))
					continue;
			}

			if(player bot_wander_on_cooldown(node.origin, timer))
			{
				skipped_cooldown = true;
				continue;
			}

			checked_paths++;

			if(!findpath(origin, node.origin, undefined, 0, 1))
				continue;

			entry = spawnstruct();
			entry.origin = node.origin;
			entry.expire = timer + 45000;
			player.bot.wander_visited[player.bot.wander_visited.size] = entry;
			player.bot.wander_retry = undefined;

			return node.origin;
		}

		// Smaller-distance fallback for compact maps and map edges.
		fallback_checks = 0;
		foreach(node in nodes)
		{
			if(fallback_checks >= 12)
				break;

			if(!isdefined(node) || !isdefined(node.origin))
				continue;

			dist_sq = distancesquared(origin, node.origin);

			if(dist_sq < ((range * 0.15) * (range * 0.15)) || dist_sq > (range * range))
				continue;

			if(!check_point_in_playable_area(node.origin))
				continue;

			if(isdefined(level.zones))
			{
				zone = maps\mp\zombies\_zm_zonemgr::get_zone_from_position(node.origin + (0, 0, 32), 1);

				if(isdefined(zone) && !maps\mp\zombies\_zm_zonemgr::zone_is_enabled(zone))
					continue;
			}

			if(player bot_wander_on_cooldown(node.origin, timer))
			{
				skipped_cooldown = true;
				continue;
			}

			fallback_checks++;

			if(!findpath(origin, node.origin, undefined, 0, 1))
				continue;

			entry = spawnstruct();
			entry.origin = node.origin;
			entry.expire = timer + 30000;
			player.bot.wander_visited[player.bot.wander_visited.size] = entry;
			player.bot.wander_retry = undefined;

			return node.origin;
		}

		if(skipped_cooldown)
			player.bot.wander_visited = [];

		player.bot.wander_retry = timer + 1500;
	}

	return undefined;
}

get_wander_location(origin, range)
{
    if(isdefined(self.bot.wander_retry) && gettime() < self.bot.wander_retry)
        return undefined;

    if(!isdefined(self.bot.wander_visited))
        self.bot.wander_visited = [];

    timer = gettime();

    fresh = [];

    foreach(entry in self.bot.wander_visited)
    {
        if(entry.expire > timer)
            fresh[fresh.size] = entry;
    }

    self.bot.wander_visited = fresh;

    nodes = getnodesinradius(origin, range, range * 0.2, 1000, "any", 256);

    skipped_cooldown = false;

    if(isdefined(nodes) && nodes.size > 0)
    {
        nodes = array_randomize(nodes);

        tries = 0;

        foreach(node in nodes)
        {
            if(tries >= 8)
                break;

            if(self bot_wander_on_cooldown(node.origin, timer))
            {
                skipped_cooldown = true;

                continue;
            }

            if(isdefined(level.zones))
            {
                zone = maps\mp\zombies\_zm_zonemgr::get_zone_from_position(node.origin + (0, 0, 32), 1);

                if(isdefined(zone) && !maps\mp\zombies\_zm_zonemgr::zone_is_enabled(zone))
                    continue;
            }

            tries++;

            if(!findpath(origin, node.origin, undefined, 0, 1))
                continue;

            entry = spawnstruct();
			
            entry.origin = node.origin;
			
            entry.expire = timer + 15000;

            self.bot.wander_visited[self.bot.wander_visited.size] = entry;

            return node.origin;
        }
    }

    if(skipped_cooldown)
    {
        self.bot.wander_visited = [];

        self.bot.wander_retry = gettime() + 500;

        return undefined;
    }

    self.bot.wander_retry = gettime() + 1500;

    return undefined;
}

bot_wander_on_cooldown(pos, timer)
{
    foreach(entry in self.bot.wander_visited)
    {
        if(entry.expire > timer && distancesquared(pos, entry.origin) < 60000)
            return true;
    }

    return false;
}


bot_objective_can_run()
{
	if(!isdefined(self) || !isdefined(self.bot))
		return false;

	if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		return false;

	if(self bot_mob_is_afterlife())
		return false;

	// Let the navigation graph carry the bot over stairs, jumps, ladders and mantles.
	// Grounded checks are performed only at the interaction point below.

	if(is_true(self.bot.is_meleeing) || is_true(self.bot.is_throwing_grenade) ||
	   is_true(self.bot.is_getting_shield) || is_true(self.bot.is_buying) ||
	   is_true(self.bot.is_perk_buying) ||
	   is_true(self.bot.is_using_box) || is_true(self.bot.is_reviving) ||
	   is_true(self.bot.is_selfreviving))
		return false;

	if(self isreloading() || self isswitchingweapons() || self isthrowinggrenade())
		return false;

	if(self getgoal("flee") || self hasgoal("flee") ||
	   self getgoal("revive") || self hasgoal("revive") ||
	   self getgoal("selfrevive") || self hasgoal("selfrevive") ||
	   self getgoal("boxbuy") || self hasgoal("boxbuy") ||
	   self getgoal("weaponbuy") || self hasgoal("weaponbuy") ||
	   self getgoal("pap") || self hasgoal("pap") ||
	   self getgoal("powerup") || self hasgoal("powerup"))
		return false;

	return true;
}

bot_auto_buildables_think()
{
	self endon("disconnect");
	self endon("bot_relife");
	self endon("death");
	level endon("end_game");

	for(;;)
	{
		wait 0.5;

		if(!self bot_objective_can_run() || is_true(self.bot.is_crafting) ||
		   is_true(self.bot.is_holding_generator))
		{
			if(self getgoal("bot_buildable") || self hasgoal("bot_buildable"))
				self cancelgoal("bot_buildable");

			self.bot.is_building = undefined;
			continue;
		}

		if(isdefined(self.bot.buildable_scan_after) && gettime() < self.bot.buildable_scan_after)
			continue;

		task = self bot_find_buildable_task();

		if(!isdefined(task))
		{
			self.bot.buildable_scan_after = gettime() + 1000;
			self.bot.is_building = undefined;

			if(self getgoal("bot_buildable") || self hasgoal("bot_buildable"))
				self cancelgoal("bot_buildable");

			continue;
		}

		self.bot.is_building = 1;
		self bot_run_buildable_task(task);
		self.bot.is_building = undefined;
	}
}

bot_find_buildable_task()
{
	if(!isdefined(level.buildable_stubs) || level.buildable_stubs.size == 0)
		return undefined;

	best_task = undefined;
	best_dist_sq = 999999999;
	path_checks = 0;

	// First finish a buildable for which this bot is already carrying the part.
	foreach(stub in level.buildable_stubs)
	{
		if(path_checks >= 48)
			break;

		if(!isdefined(stub) || !isdefined(stub.origin) || !isdefined(stub.buildablezone))
			continue;

		if(isdefined(stub.bot_auto_builder_retry_until) && gettime() < stub.bot_auto_builder_retry_until)
			continue;

		if(isdefined(stub.bot_auto_builder) && stub.bot_auto_builder != self &&
		   isdefined(stub.bot_auto_builder_until) && gettime() < stub.bot_auto_builder_until &&
		   isalive(stub.bot_auto_builder))
			continue;

		if(!self maps\mp\zombies\_zm_buildables::player_can_build(stub.buildablezone, 0))
			continue;

		dist_sq = distancesquared(self.origin, stub.origin);

		if(dist_sq >= best_dist_sq)
			continue;

		path_checks++;

		if(!findpath(self.origin, stub.origin, undefined, 0, 1))
			continue;

		best_task = spawnstruct();
		best_task.kind = "build";
		best_task.origin = stub.origin;
		best_task.stub = stub;
		best_task.buildable = stub.buildablezone;
		best_task.slot = stub.buildablezone.buildable_slot;
		best_dist_sq = dist_sq;
	}

	if(isdefined(best_task))
	{
		best_task.stub.bot_auto_builder = self;
		best_task.stub.bot_auto_builder_until = gettime() + 45000;
		return best_task;
	}

	// Once a buildable is finished, collect its persistent equipment from
	// the same trigger (for example the shield or turbine) when it is available.
	best_equip_stub = undefined;
	best_dist_sq = 999999999;
	path_checks = 0;

	foreach(stub in level.buildable_stubs)
	{
		if(path_checks >= 48)
			break;

		if(!isdefined(stub) || !isdefined(stub.origin) ||
		   !isdefined(stub.built) || !stub.built ||
		   !isdefined(stub.weaponname) || !isdefined(stub.persistent))
			continue;

		if(stub.persistent != 1 && stub.persistent != 2)
			continue;

		if(isdefined(stub.bot_auto_equip_retry_until) && gettime() < stub.bot_auto_equip_retry_until)
			continue;

		if(stub.persistent == 1 && (self has_player_equipment(stub.weaponname) || self hasweapon(stub.weaponname)))
			continue;

		if(stub.persistent == 2 && isdefined(stub.bought) && stub.bought)
			continue;

		if(isdefined(stub.bot_auto_builder) && stub.bot_auto_builder != self &&
		   isdefined(stub.bot_auto_builder_until) && gettime() < stub.bot_auto_builder_until &&
		   isalive(stub.bot_auto_builder))
			continue;

		dist_sq = distancesquared(self.origin, stub.origin);

		if(dist_sq >= best_dist_sq)
			continue;

		path_checks++;

		if(!findpath(self.origin, stub.origin, undefined, 0, 1))
			continue;

		best_equip_stub = stub;
		best_dist_sq = dist_sq;
	}

	if(isdefined(best_equip_stub))
	{
		best_equip_stub.bot_auto_builder = self;
		best_equip_stub.bot_auto_builder_until = gettime() + 45000;

		task = spawnstruct();
		task.kind = "equip";
		task.origin = best_equip_stub.origin;
		task.stub = best_equip_stub;
		task.buildable = best_equip_stub.buildablezone;
		task.slot = isdefined(best_equip_stub.buildablezone) ? best_equip_stub.buildablezone.buildable_slot : 0;
		task.weaponname = best_equip_stub.weaponname;
		return task;
	}

	// Do not collect another non-shared part while a part is already in hand.
	if(isdefined(self.current_buildable_pieces))
	{
		for(slot = 0; slot < self.current_buildable_pieces.size; slot++)
		{
			if(isdefined(self.current_buildable_pieces[slot]))
				return undefined;
		}
	}

	best_piece = undefined;
	best_stub = undefined;
	best_piece_approach = undefined;
	best_dist_sq = 999999999;
	path_checks = 0;

	foreach(stub in level.buildable_stubs)
	{
		if(path_checks >= 48)
			break;

		if(!isdefined(stub) || !isdefined(stub.buildablezone) ||
		   !isdefined(stub.buildablezone.pieces))
			continue;

		foreach(piece in stub.buildablezone.pieces)
		{
			if(path_checks >= 48)
				break;

			if(!isdefined(piece) || !isdefined(piece.model) ||
			   !isdefined(piece.model.origin) || !isdefined(piece.unitrigger))
				continue;

			if(isdefined(piece.built) && piece.built)
				continue;

			if(isdefined(piece.building) && piece.building)
				continue;

			if(isdefined(piece.bot_auto_retry_until) && gettime() < piece.bot_auto_retry_until)
				continue;

			if(isdefined(piece.piece_owner) && isalive(piece.piece_owner))
				continue;

			if(!self maps\mp\zombies\_zm_buildables::player_can_take_piece(piece))
				continue;

			if(isdefined(piece.bot_auto_claim) && piece.bot_auto_claim != self &&
			   isdefined(piece.bot_auto_claim_until) && gettime() < piece.bot_auto_claim_until &&
			   isalive(piece.bot_auto_claim))
				continue;

			slot = piece.buildable_slot;

			if(isdefined(self maps\mp\zombies\_zm_buildables::player_get_buildable_piece(slot)))
				continue;

			dist_sq = distancesquared(self.origin, piece.model.origin);

			if(dist_sq >= best_dist_sq)
				continue;

			path_checks++;

			// Some pickups are suspended over gaps or have a model point that is
			// not reachable by the nav graph. Try the visual point, then just below it.
			approach_origin = piece.model.origin;
			if(!findpath(self.origin, approach_origin, undefined, 0, 1))
			{
				approach_origin = piece.model.origin + (0, 0, -16);
				if(!findpath(self.origin, approach_origin, undefined, 0, 1))
					continue;
			}

			best_piece = piece;
			best_stub = stub;
			best_piece_approach = approach_origin;
			best_dist_sq = dist_sq;
		}
	}

	if(!isdefined(best_piece))
		return undefined;

	best_piece.bot_auto_claim = self;
	best_piece.bot_auto_claim_until = gettime() + 45000;

	task = spawnstruct();
	task.kind = "pickup";
	task.origin = best_piece.model.origin;
	task.approach_origin = best_piece_approach;
	task.piece = best_piece;
	task.stub = best_stub;
	task.slot = best_piece.buildable_slot;
	return task;
}

bot_release_buildable_task(task)
{
	if(!isdefined(task))
		return;

	if(isdefined(task.piece) && isdefined(task.piece.bot_auto_claim) &&
	   task.piece.bot_auto_claim == self)
	{
		task.piece.bot_auto_claim = undefined;
		task.piece.bot_auto_claim_until = undefined;
	}

	if(isdefined(task.stub) && isdefined(task.stub.bot_auto_builder) &&
	   task.stub.bot_auto_builder == self)
	{
		task.stub.bot_auto_builder = undefined;
		task.stub.bot_auto_builder_until = undefined;
	}
}

bot_release_craftable_task(task)
{
	if(!isdefined(task))
		return;

	if(isdefined(task.piece) && isdefined(task.piece.bot_auto_claim) &&
	   task.piece.bot_auto_claim == self)
	{
		task.piece.bot_auto_claim = undefined;
		task.piece.bot_auto_claim_until = undefined;
	}

	if(isdefined(task.stub) && isdefined(task.stub.bot_auto_crafter) &&
	   task.stub.bot_auto_crafter == self)
	{
		task.stub.bot_auto_crafter = undefined;
		task.stub.bot_auto_crafter_until = undefined;
	}
}

bot_drop_stuck_buildable_piece(task, retry_ms)
{
	if(!isdefined(task) || !isdefined(task.slot))
		return;

	held = self maps\mp\zombies\_zm_buildables::player_get_buildable_piece(task.slot);

	if(!isdefined(held))
		return;

	held.bot_auto_retry_until = gettime() + retry_ms;
	self maps\mp\zombies\_zm_buildables::player_drop_piece(undefined, task.slot);
}

// Resolve stock buildables helpers at runtime so this controller remains safe on
// maps that do not initialize a particular buildable subsystem.
bot_buildables_func(name)
{
    if(!isdefined(level.bot_buildables_funcs))
        level.bot_buildables_funcs = [];

    if(!isdefined(level.bot_buildables_funcs[name]))
        level.bot_buildables_funcs[name] = getfunction("maps/mp/zombies/_zm_buildables", name);

    return level.bot_buildables_funcs[name];
}

// Unittriggers are per-player entities. Bots need to explicitly dispatch the
// same event that a human use input sends after the stock trigger is active.
bot_dispatch_buildable_trigger(stub)
{
    if(!isdefined(stub))
        return false;

    unitrigger_trigger_func = getfunction("maps/mp/zombies/_zm_unitrigger", "unitrigger_trigger");
    if(!isdefined(unitrigger_trigger_func))
        return false;

    trigger = stub [[ unitrigger_trigger_func ]](self);

    if(!isdefined(trigger) ||
       !isdefined(trigger.thread_running) || !trigger.thread_running ||
       !isdefined(trigger.parent_player) || trigger.parent_player != self)
        return false;

    trigger notify("trigger", self);
    return true;
}

// Call the stock pickup routine so all map callbacks, inventory state,
// clientfields and piece tracking are updated exactly as for a human player.
bot_take_buildable_piece(piece)
{
    if(!isdefined(piece))
        return false;

    can_take_func = bot_buildables_func("player_can_take_piece");
    take_piece_func = bot_buildables_func("player_take_piece");

    if(!isdefined(can_take_func) || !isdefined(take_piece_func))
        return false;

    if(!self [[ can_take_func ]](piece))
        return false;

    self thread [[ take_piece_func ]](piece);
    return true;
}

// _zm_craftables only ships on maps that use it (Origins, Mob of the Dead). A
// direct file::function reference is resolved at script load and causes
// "Unresolved external" on every other map, so look the functions up at runtime.
// getfunction() returns undefined when the file is not loaded.
bot_craftables_func(name)
{
	if(!isdefined(level.bot_craftables_funcs))
		level.bot_craftables_funcs = [];

	if(!isdefined(level.bot_craftables_funcs[name]))
		level.bot_craftables_funcs[name] = getfunction("maps/mp/zombies/_zm_craftables", name);

	return level.bot_craftables_funcs[name];
}

bot_player_can_craft(craftablespawn)
{
	// Origins staff recipes require all three physical staff pieces before the
	// crystal can be assembled. Enforce the stock staff counter here as well as
	// in the crystal pickup filter, so a missing per-player table trigger cannot
	// make a bot try to craft an incomplete staff.
	if(getdvar("mapname") == "zm_tomb" && isdefined(craftablespawn) &&
	   isdefined(craftablespawn.craftable_name) &&
	   issubstr(craftablespawn.craftable_name, "elemental_staff_"))
	{
		staff_name = craftablespawn.craftable_name;
		if(!isdefined(level.staff_part_count) ||
		   !isdefined(level.staff_part_count[staff_name]) ||
		   level.staff_part_count[staff_name] > 0)
			return false;
	}

	can_craft = bot_craftables_func("player_can_craft");

	if(!isdefined(can_craft))
		return false;

	return self [[ can_craft ]](craftablespawn, 0);
}

bot_player_can_take_piece(piece)
{
	can_take = bot_craftables_func("player_can_take_piece");

	if(!isdefined(can_take))
		return false;

	return self [[ can_take ]](piece);
}

bot_craftable_piece_is_available(piece)
{
    if(!isdefined(piece) || !isdefined(piece.piecestub))
        return false;

    if(getdvar("mapname") != "zm_tomb")
        return true;

    if(!isdefined(piece.craftablename) || !isdefined(piece.piecename))
        return true;

    craftable_name = piece.craftablename;
    piece_name = piece.piecename;

    // A staff crystal is the final ingredient, not a substitute for the three
    // physical pieces. The stock pickup watcher decrements this counter.
    if(issubstr(craftable_name, "elemental_staff_") && piece_name == "gem")
    {
        if(!isdefined(level.staff_part_count) ||
           !isdefined(level.staff_part_count[craftable_name]) ||
           level.staff_part_count[craftable_name] > 0)
            return false;
    }

    // Ice Staff parts become available only after stock digging reveals them.
    if(craftable_name == "elemental_staff_water" && piece_name != "gem")
    {
        if(!isdefined(piece.canmove) || !piece.canmove)
            return false;
    }

    // The Fire Staff lower piece is released by the Panzer-death callback.
    if(craftable_name == "elemental_staff_fire" && piece_name == "lower_staff")
    {
        if(!isdefined(piece.canmove) || !piece.canmove)
            return false;
    }

    // The Fire Staff upper piece is initially only a ghost at the church.
    // Stock assigns its wrapper to the church challenge box only after the
    // correct zone has been captured. Do not let the generic nearby-piece
    // fallback bypass that required Origins step.
    if(craftable_name == "elemental_staff_fire" && piece_name == "upper_staff")
    {
        unlocked = false;

        if(isdefined(level.a_uts_challenge_boxes))
        {
            foreach(challenge_box in level.a_uts_challenge_boxes)
            {
                if(!isdefined(challenge_box) ||
                   !isdefined(challenge_box.str_location) ||
                   challenge_box.str_location != "church_capture" ||
                   !isdefined(challenge_box.s_staff_piece) ||
                   !isdefined(challenge_box.s_staff_piece.piecespawn))
                    continue;

                if(challenge_box.s_staff_piece.piecespawn == piece)
                {
                    unlocked = true;
                    break;
                }
            }
        }

        if(!unlocked)
            return false;
    }

    return true;
}


bot_drop_stuck_craftable_piece(task, retry_ms)
{
	if(!isdefined(task) || !isdefined(self.current_craftable_piece))
		return;

	held = self.current_craftable_piece;
	held.bot_auto_retry_until = gettime() + retry_ms;
	drop_piece = bot_craftables_func("player_drop_piece");

	if(isdefined(drop_piece))
		self [[ drop_piece ]]();
}

bot_run_buildable_task(task)
{
	if(!isdefined(task) || !isdefined(task.origin))
		return;

	goal_name = "bot_buildable";

	// Make the stock per-player unitrigger prompts visible to scripted bots.
	if(task.kind == "pickup" && isdefined(task.piece) && isdefined(task.piece.unitrigger))
		task.piece.unitrigger.ignore_player_valid = 1;
	else if(isdefined(task.stub))
		task.stub.ignore_player_valid = 1;

	nav_origin = task.origin;
	if(task.kind == "pickup" && isdefined(task.approach_origin))
		nav_origin = task.approach_origin;

	if(!findpath(self.origin, nav_origin, undefined, 0, 1))
	{
		if(task.kind == "build")
			self bot_drop_stuck_buildable_piece(task, 12000);
		self bot_release_buildable_task(task);
		return;
	}

	// The stock trigger checks its own bounds. A wide 140-unit bot goal lets
	// navigation stop outside the actual interaction volume.
	self addgoal(nav_origin, 24, 2, goal_name);

	deadline = gettime() + 45000;
	arrived = false;

	while(gettime() < deadline)
	{
		if(!self bot_objective_can_run())
			break;

		if(task.kind == "pickup")
		{
			if(!isdefined(task.piece) || !isdefined(task.piece.model) ||
			   !isdefined(task.piece.model.origin))
				break;

			held = self maps\mp\zombies\_zm_buildables::player_get_buildable_piece(task.slot);

			if(isdefined(held))
				break;

			task.piece.bot_auto_claim_until = gettime() + 45000;
		}
		else if(task.kind == "build")
		{
			if(!isdefined(task.stub) || !isdefined(task.buildable))
				break;

			held = self maps\mp\zombies\_zm_buildables::player_get_buildable_piece(task.slot);

			if(!isdefined(held) || task.buildable buildable_is_piece_built(held))
				break;

			task.stub.bot_auto_builder_until = gettime() + 45000;
		}
		else if(task.kind == "equip")
		{
			if(!isdefined(task.stub) || !isdefined(task.stub.built) || !task.stub.built ||
			   !isdefined(task.weaponname))
				break;

			if(task.stub.persistent == 1 && (self has_player_equipment(task.weaponname) || self hasweapon(task.weaponname)))
				break;

			if(task.stub.persistent == 2 && isdefined(task.stub.bought) && task.stub.bought)
				break;

			task.stub.bot_auto_builder_until = gettime() + 45000;
		}

		arrival_range_sq = task.kind == "pickup" ? 900 : 2500;
		if(distancesquared(self.origin, task.origin) <= arrival_range_sq)
		{
			arrived = true;
			break;
		}

		wait 0.25;
	}

	self cancelgoal(goal_name);
	did_interact = 0;

	if(!arrived && gettime() >= deadline && task.kind == "build")
		self bot_drop_stuck_buildable_piece(task, 12000);

	if(arrived && self bot_objective_can_run())
	{
		did_interact = 1;
		self lookat(task.origin + (0, 0, 32));
		self.bot.is_objective_using = 1;
		use_deadline = gettime() + 7000;

		while(gettime() < use_deadline)
		{
			if(!self bot_objective_can_run())
				break;

			if(task.kind == "pickup")
			{
				if(!isdefined(task.piece.model))
					break;

				held = self maps\mp\zombies\_zm_buildables::player_get_buildable_piece(task.slot);

				if(isdefined(held))
					break;
			}
			else if(task.kind == "build")
			{
				held = self maps\mp\zombies\_zm_buildables::player_get_buildable_piece(task.slot);

				if(!isdefined(held) || task.buildable buildable_is_piece_built(held))
					break;
			}
			else
			{
				if(task.stub.persistent == 1 && (self has_player_equipment(task.weaponname) || self hasweapon(task.weaponname)))
					break;

				if(task.stub.persistent == 2 && isdefined(task.stub.bought) && task.stub.bought)
					break;
			}

			if(!self isonground() || self isonladder() || self ismantling())
			{
				wait 0.1;
				continue;
			}

			if(task.kind == "pickup")
			{
				if(!isdefined(task.piece.bot_auto_take_pending_until) ||
				   gettime() >= task.piece.bot_auto_take_pending_until)
				{
					if(self bot_take_buildable_piece(task.piece))
						task.piece.bot_auto_take_pending_until = gettime() + 2000;
					else if(!self bot_dispatch_buildable_trigger(task.piece.unitrigger))
						self pressusebutton(0.15);
				}
			}
			else if(task.kind == "build")
			{
				// Notify the stock build worker, then hold use through its native timer.
				if(!isdefined(task.trigger_dispatch_after) || gettime() >= task.trigger_dispatch_after)
				{
					self bot_dispatch_buildable_trigger(task.stub);
					task.trigger_dispatch_after = gettime() + 500;
				}
				self pressusebutton(3.2);
			}
			else
			{
				// A completed persistent buildable grants its equipment from this trigger.
				if(!isdefined(task.trigger_dispatch_after) || gettime() >= task.trigger_dispatch_after)
				{
					if(!self bot_dispatch_buildable_trigger(task.stub))
						self pressusebutton(0.15);
					task.trigger_dispatch_after = gettime() + 500;
				}
			}

			wait 0.1;
		}

		self.bot.is_objective_using = undefined;
		self clearlookat();
	}


	if(did_interact && task.kind == "pickup" && isdefined(task.piece) &&
	   isdefined(task.piece.model))
		task.piece.bot_auto_retry_until = gettime() + 5000;

	if(did_interact && task.kind == "build" && isdefined(task.stub) &&
	   isdefined(task.buildable))
	{
		held = self maps\mp\zombies\_zm_buildables::player_get_buildable_piece(task.slot);

		if(isdefined(held) && !task.buildable buildable_is_piece_built(held))
			task.stub.bot_auto_builder_retry_until = gettime() + 5000;
		else
			task.stub.bot_auto_builder_retry_until = undefined;
	}

	if(task.kind == "equip" && isdefined(task.stub))
	{
		if((task.stub.persistent == 1 && !self has_player_equipment(task.weaponname) && !self hasweapon(task.weaponname)) ||
		   (task.stub.persistent == 2 && !(isdefined(task.stub.bought) && task.stub.bought)))
			task.stub.bot_auto_equip_retry_until = gettime() + 15000;
		else
			task.stub.bot_auto_equip_retry_until = undefined;
	}

	self bot_release_buildable_task(task);
}

bot_auto_craftables_think()
{
	self endon("disconnect");
	self endon("bot_relife");
	self endon("death");
	level endon("end_game");

	map_name = getdvar("mapname");

	// Only Mob of the Dead and Origins expose this separate craftables module.
	// Other maps use the shared buildables system above.
	if(map_name != "zm_prison" && map_name != "zm_tomb")
		return;

	for(;;)
	{
		wait 0.5;

		if(!self bot_objective_can_run() || is_true(self.bot.is_building) ||
		   is_true(self.bot.is_holding_generator))
		{
			if(self getgoal("bot_craftable") || self hasgoal("bot_craftable"))
				self cancelgoal("bot_craftable");

			self.bot.is_crafting = undefined;
			continue;
		}

		if(isdefined(self.bot.craftable_scan_after) && gettime() < self.bot.craftable_scan_after)
			continue;

		task = self bot_find_craftable_task();

		if(!isdefined(task))
		{
			self.bot.craftable_scan_after = gettime() + 1000;
			self.bot.is_crafting = undefined;

			if(self getgoal("bot_craftable") || self hasgoal("bot_craftable"))
				self cancelgoal("bot_craftable");

			continue;
		}

		self.bot.is_crafting = 1;
		self bot_run_craftable_task(task);
		self.bot.is_crafting = undefined;
	}
}

bot_find_craftable_task()
{
	if(!isdefined(level.a_uts_craftables) || level.a_uts_craftables.size == 0)
		return undefined;

	best_task = undefined;
	best_dist_sq = 999999999;
	path_checks = 0;

	// Prefer placing a part already being carried (or shared inventory already collected).
	foreach(stub in level.a_uts_craftables)
	{
		if(path_checks >= 48)
			break;

		if(!isdefined(stub) || !isdefined(stub.origin) || !isdefined(stub.craftablespawn))
			continue;

		if(isdefined(stub.bot_auto_craft_retry_until) && gettime() < stub.bot_auto_craft_retry_until)
			continue;

		if(isdefined(stub.bot_auto_crafter) && stub.bot_auto_crafter != self &&
		   isdefined(stub.bot_auto_crafter_until) && gettime() < stub.bot_auto_crafter_until &&
		   isalive(stub.bot_auto_crafter))
			continue;

		if(!self bot_player_can_craft(stub.craftablespawn))
			continue;

		dist_sq = distancesquared(self.origin, stub.origin);

		if(dist_sq >= best_dist_sq)
			continue;

		path_checks++;

		if(!findpath(self.origin, stub.origin, undefined, 0, 1))
			continue;

		best_task = spawnstruct();
		best_task.kind = "craft";
		best_task.origin = stub.origin;
		best_task.stub = stub;
		best_task.craftablespawn = stub.craftablespawn;
		best_dist_sq = dist_sq;
	}

	if(isdefined(best_task))
	{
		best_task.stub.bot_auto_crafter = self;
		best_task.stub.bot_auto_crafter_until = gettime() + 45000;
		return best_task;
	}

	// Pick up completed equipment from persistent craftable tables as the
	// stock trigger permits (e.g. a finished shield or staff).
	best_equip_stub = undefined;
	best_dist_sq = 999999999;
	path_checks = 0;

	foreach(stub in level.a_uts_craftables)
	{
		if(path_checks >= 48)
			break;

		if(!isdefined(stub) || !isdefined(stub.origin) ||
		   !isdefined(stub.crafted) || !stub.crafted ||
		   !isdefined(stub.weaponname) || !isdefined(stub.persistent))
			continue;

		if(stub.persistent != 1 && stub.persistent != 2)
			continue;

		if(isdefined(stub.bot_auto_equip_retry_until) && gettime() < stub.bot_auto_equip_retry_until)
			continue;

		if(stub.persistent == 1 && (self has_player_equipment(stub.weaponname) || self hasweapon(stub.weaponname)))
			continue;

		if(stub.persistent == 2 && isdefined(stub.bought) && stub.bought)
			continue;

		if(isdefined(stub.bot_auto_crafter) && stub.bot_auto_crafter != self &&
		   isdefined(stub.bot_auto_crafter_until) && gettime() < stub.bot_auto_crafter_until &&
		   isalive(stub.bot_auto_crafter))
			continue;

		dist_sq = distancesquared(self.origin, stub.origin);

		if(dist_sq >= best_dist_sq)
			continue;

		path_checks++;

		if(!findpath(self.origin, stub.origin, undefined, 0, 1))
			continue;

		best_equip_stub = stub;
		best_dist_sq = dist_sq;
	}

	if(isdefined(best_equip_stub))
	{
		best_equip_stub.bot_auto_crafter = self;
		best_equip_stub.bot_auto_crafter_until = gettime() + 45000;

		task = spawnstruct();
		task.kind = "equip";
		task.origin = best_equip_stub.origin;
		task.stub = best_equip_stub;
		task.craftablespawn = best_equip_stub.craftablespawn;
		task.weaponname = best_equip_stub.weaponname;
		return task;
	}

	// Personal parts occupy one hand; Origins staff, shield, and drone parts,
	// along with Mob's shared pieces, can be collected into shared inventory.
	best_piece = undefined;
	best_piece_approach = undefined;
	best_dist_sq = 999999999;
	path_checks = 0;

	foreach(stub in level.a_uts_craftables)
	{
		if(path_checks >= 48)
			break;

		if(!isdefined(stub) || !isdefined(stub.craftablespawn) ||
		   !isdefined(stub.craftablespawn.a_piecespawns))
			continue;

		foreach(piece in stub.craftablespawn.a_piecespawns)
		{
			if(path_checks >= 48)
				break;

			if(!isdefined(piece) || !isdefined(piece.model) ||
			   !isdefined(piece.model.origin) || !isdefined(piece.unitrigger) ||
			   !isdefined(piece.piecestub))
				continue;

			if(isdefined(piece.crafted) && piece.crafted)
				continue;

			if(isdefined(piece.bot_auto_retry_until) && gettime() < piece.bot_auto_retry_until)
				continue;

			if(!self bot_player_can_take_piece(piece))
				continue;

			if(!self bot_craftable_piece_is_available(piece))
				continue;

			if(isdefined(piece.in_shared_inventory) && piece.in_shared_inventory)
				continue;

			if(isdefined(self.current_craftable_piece) &&
			   !(isdefined(piece.piecestub.is_shared) && piece.piecestub.is_shared))
				continue;

			if(isdefined(piece.bot_auto_claim) && piece.bot_auto_claim != self &&
			   isdefined(piece.bot_auto_claim_until) && gettime() < piece.bot_auto_claim_until &&
			   isalive(piece.bot_auto_claim))
				continue;

			dist_sq = distancesquared(self.origin, piece.model.origin);

			if(dist_sq >= best_dist_sq)
				continue;

			path_checks++;

			// Some Origins staff and drone pieces are suspended above the
			// floor. Path to a reachable point just below the visible model.
			approach_origin = piece.model.origin + (0, 0, -16);
			if(!findpath(self.origin, approach_origin, undefined, 0, 1))
				continue;

			best_piece = piece;
			best_piece_approach = approach_origin;
			best_dist_sq = dist_sq;
		}
	}

	if(!isdefined(best_piece))
		return undefined;

	best_piece.bot_auto_claim = self;
	best_piece.bot_auto_claim_until = gettime() + 45000;

	task = spawnstruct();
	task.kind = "pickup";
	task.origin = best_piece.model.origin;
	task.piece = best_piece;
	task.approach_origin = best_piece_approach;
	task.stub = undefined;
	task.slot = undefined;
	return task;
}

bot_count_crafted_parts(craftablespawn)
{
	if(!isdefined(craftablespawn) || !isdefined(craftablespawn.a_piecespawns))
		return 0;

	count = 0;

	foreach(piece in craftablespawn.a_piecespawns)
	{
		if(isdefined(piece.crafted) && piece.crafted)
			count++;
	}

	return count;
}


bot_run_origins_riotshield_craft(task)
{
	if(!isdefined(task) || !isdefined(task.stub) ||
	   !isdefined(task.craftablespawn) ||
	   task.craftablespawn.craftable_name != "tomb_shield_zm")
		return false;

	if(!self bot_player_can_craft(task.craftablespawn))
		return false;

	set_crafting_func = bot_craftables_func("craftable_set_piece_crafting");
	clear_crafting_func = bot_craftables_func("craftable_clear_piece_crafting");
	player_craft_func = bot_craftables_func("player_craft");
	all_crafted_func = bot_craftables_func("craftable_all_crafted");

	if(!isdefined(set_crafting_func) || !isdefined(clear_crafting_func) ||
	   !isdefined(player_craft_func) || !isdefined(all_crafted_func))
		return false;

	current_weapon = self getcurrentweapon();
	self.bot.is_objective_using = 1;

	// Match the stock table craft state, consume the shared pieces through
	// player_craft(), and retain the native model and completion callbacks.
	task.craftablespawn [[ set_crafting_func ]](undefined);

	craft_time = 3000;
	if(isdefined(task.stub.usetime) && task.stub.usetime > 0)
		craft_time = task.stub.usetime;

	craft_deadline = gettime() + craft_time + 150;
	while(gettime() < craft_deadline)
	{
		if(!isalive(self) || !self bot_objective_can_run())
			break;
		wait 0.05;
	}

	if(!isalive(self) || !self bot_objective_can_run())
	{
		task.craftablespawn [[ clear_crafting_func ]](undefined);
		self.bot.is_objective_using = undefined;
		return false;
	}

	self [[ player_craft_func ]](task.craftablespawn);
	crafted = task.craftablespawn [[ all_crafted_func ]]();

	if(crafted)
		self scripts\zm\zm_bo2_bots_map_origins::bot_origins_grant_shield(current_weapon);
	else
		task.craftablespawn [[ clear_crafting_func ]](undefined);

	self.bot.is_objective_using = undefined;
	return crafted;
}

bot_run_craftable_task(task)
{
	if(!isdefined(task) || !isdefined(task.origin))
		return;

	goal_name = "bot_craftable";
	use_deadline = 0;

	// Make Origins and Mob's per-player part/table triggers eligible for bots.
	if(getdvar("mapname") == "zm_tomb" || getdvar("mapname") == "zm_prison")
	{
		if(task.kind == "pickup" && isdefined(task.piece) && isdefined(task.piece.unitrigger))
			task.piece.unitrigger.ignore_player_valid = 1;
		else if(isdefined(task.stub))
			task.stub.ignore_player_valid = 1;
	}

	nav_origin = task.origin;
	if(task.kind == "pickup" && getdvar("mapname") == "zm_tomb" &&
	   isdefined(task.approach_origin))
		nav_origin = task.approach_origin;

	if(!findpath(self.origin, nav_origin, undefined, 0, 1))
	{
		if(task.kind == "craft")
			self bot_drop_stuck_craftable_piece(task, 12000);
		self bot_release_craftable_task(task);
		return;
	}

	// Reach the actual part or table trigger; the old 140-unit goal radius
	// let bots stop too far away to pick up parts or hold the craft interaction.
	if(task.kind == "pickup" && getdvar("mapname") == "zm_tomb")
		self addgoal(nav_origin, 56, 2, goal_name);
	else
		self addgoal(task.origin, 24, 2, goal_name);

	// Origins craftable pickup parts and table actions both expose per-player
	// unitrigger entities. Use the same lookup for both task kinds so pickup
	// approach can test the real trigger volume instead of only model distance.
	unitrigger_trigger_func = getfunction("maps/mp/zombies/_zm_unitrigger", "unitrigger_trigger");

	deadline = gettime() + 45000;
	arrived = false;

	while(gettime() < deadline)
	{
		if(!self bot_objective_can_run())
			break;

		if(task.kind == "pickup")
		{
			if(!isdefined(task.piece) || !isdefined(task.piece.model) ||
			   !isdefined(task.piece.model.origin) || !isdefined(task.piece.piecestub))
				break;

			is_shared = isdefined(task.piece.piecestub.is_shared) && task.piece.piecestub.is_shared;

			if(is_shared && isdefined(task.piece.in_shared_inventory) && task.piece.in_shared_inventory)
				break;

			if(!is_shared && isdefined(self.current_craftable_piece))
				break;

			task.piece.bot_auto_claim_until = gettime() + 45000;
		}
		else if(task.kind == "craft")
		{
			if(!isdefined(task.stub) || !isdefined(task.craftablespawn))
				break;

			if(!self bot_player_can_craft(task.craftablespawn))
				break;

			task.stub.bot_auto_crafter_until = gettime() + 45000;
		}
		else if(task.kind == "equip")
		{
			if(!isdefined(task.stub) || !isdefined(task.stub.crafted) || !task.stub.crafted ||
			   !isdefined(task.weaponname))
				break;

			if(task.stub.persistent == 1 && (self has_player_equipment(task.weaponname) || self hasweapon(task.weaponname)))
				break;

			if(task.stub.persistent == 2 &&
			   (isdefined(task.stub.bought) && task.stub.bought))
				break;

			task.stub.bot_auto_crafter_until = gettime() + 45000;
		}

		if(task.kind == "pickup")
		{
			// Parts can be mounted above the floor (especially staff/drone
			// pieces). Their trigger volume is authoritative; a 3D model-radius
			// test can leave a bot standing underneath while it stares upward.
			piece_trigger = undefined;
			if(isdefined(task.piece.unitrigger) && isdefined(unitrigger_trigger_func))
				piece_trigger = task.piece.unitrigger [[ unitrigger_trigger_func ]](self);

			if(isdefined(piece_trigger) && piece_trigger istouching(self))
			{
				arrived = true;
				break;
			}

			if(distance2d(self.origin, task.origin) <= 88 &&
			   abs(self.origin[2] - task.origin[2]) <= 176)
			{
				arrived = true;
				break;
			}
		}
		else
		{
			// The stock craftables handler accepts a build only from inside the
			// bot's own per-player unitrigger, so navigate until that trigger is
			// actually touching the bot instead of relying on a loose radius.
			if(isdefined(unitrigger_trigger_func) && isdefined(task.stub))
			{
				table_trigger = task.stub [[ unitrigger_trigger_func ]](self);
				if(isdefined(table_trigger) && table_trigger istouching(self))
				{
					arrived = true;
					break;
				}
			}
			else if(distancesquared(self.origin, task.origin) <= 24 * 24)
			{
				arrived = true;
				break;
			}
		}

		wait 0.25;
	}

	self cancelgoal(goal_name);
	did_interact = 0;

	if(!arrived && gettime() >= deadline && task.kind == "craft")
		self bot_drop_stuck_craftable_piece(task, 12000);

	if(arrived && self bot_objective_can_run())
	{
		did_interact = 1;
		self lookat(task.origin + (0, 0, 32));
		use_deadline = gettime() + 7000;

		if(task.kind == "pickup")
		{
			if(!isdefined(task.piece) || !isdefined(task.piece.piecestub))
			{
				self.bot.is_objective_using = undefined;
				self clearlookat();
				self bot_release_craftable_task(task);
				return;
			}

			is_shared = isdefined(task.piece.piecestub.is_shared) && task.piece.piecestub.is_shared;
			self.bot.is_objective_using = 1;

			// Retry the native pickup routine while the model is still present.
			// It updates stock callbacks, staff counters, shared inventory and
			// part state; repeated use-button pulses alone are unreliable for bots.
			take_piece_func = undefined;
			next_take_attempt = 0;
			if(getdvar("mapname") == "zm_prison" || getdvar("mapname") == "zm_tomb")
				take_piece_func = bot_craftables_func("player_take_piece");

			while(gettime() < use_deadline)
			{
				if(!self bot_objective_can_run())
					break;

				if(!isdefined(task.piece.model))
					break;

				if(!self bot_craftable_piece_is_available(task.piece))
					break;

				if(is_shared)
				{
					if(isdefined(task.piece.in_shared_inventory) && task.piece.in_shared_inventory)
						break;
				}
				else if(isdefined(self.current_craftable_piece) &&
				        self.current_craftable_piece.piecename == task.piece.piecename &&
				        self.current_craftable_piece.craftablename == task.piece.craftablename)
					break;

				if(getdvar("mapname") == "zm_prison" || getdvar("mapname") == "zm_tomb")
				{
					already_picked = 0;
					if(is_shared && isdefined(task.piece.in_shared_inventory) && task.piece.in_shared_inventory)
						already_picked = 1;
					else if(!is_shared && isdefined(self.current_craftable_piece) &&
					        self.current_craftable_piece.piecename == task.piece.piecename &&
					        self.current_craftable_piece.craftablename == task.piece.craftablename)
						already_picked = 1;

					if(!already_picked && (is_shared || !isdefined(self.current_craftable_piece)) &&
					   isdefined(take_piece_func) && self bot_player_can_take_piece(task.piece) &&
					   gettime() >= next_take_attempt &&
					   (!isdefined(task.piece.bot_auto_take_pending_until) ||
					    gettime() >= task.piece.bot_auto_take_pending_until) &&
					   self isonground() && !self isonladder() && !self ismantling())
					{
						// Prevent overlapping pickup threads if a map onpickup callback
						// takes a little time to finish its stock state updates.
						next_take_attempt = gettime() + 2000;
						task.piece.bot_auto_take_pending_until = gettime() + 2000;
						self thread [[ take_piece_func ]](task.piece);
					}
				}
				else
				{
					if(!self isonground() || self isonladder() || self ismantling())
					{
						wait 0.1;
						continue;
					}

					self pressusebutton(0.15);
				}

				wait 0.1;
			}

			// If the engine does not dispatch pickup to this scripted client, invoke
			// the exact stock pickup routine. Stock callbacks still update inventory,
			// quest fields, staff counters, and shared-piece state.
			if((getdvar("mapname") == "zm_prison" || getdvar("mapname") == "zm_tomb") && isdefined(task.piece) &&
			   isdefined(task.piece.model) && isdefined(task.piece.model.origin) &&
			   self bot_craftable_piece_is_available(task.piece) &&
			   distance2d(self.origin, task.piece.model.origin) <= 96 &&
			   abs(self.origin[2] - task.piece.model.origin[2]) <= 184)
			{
				is_shared = isdefined(task.piece.piecestub) &&
				            isdefined(task.piece.piecestub.is_shared) &&
				            task.piece.piecestub.is_shared;
				already_picked = 0;

				if(is_shared && isdefined(task.piece.in_shared_inventory) && task.piece.in_shared_inventory)
					already_picked = 1;
				else if(!is_shared && isdefined(self.current_craftable_piece) &&
				        self.current_craftable_piece.piecename == task.piece.piecename &&
				        self.current_craftable_piece.craftablename == task.piece.craftablename)
					already_picked = 1;

				if(!already_picked && (is_shared || !isdefined(self.current_craftable_piece)))
				{
					take_piece_func = bot_craftables_func("player_take_piece");
					if(isdefined(take_piece_func) && self bot_player_can_take_piece(task.piece))
						self thread [[ take_piece_func ]](task.piece);
				}
			}
		}
		else if(task.kind == "craft")
		{
			self.bot.is_objective_using = 1;
			progress_before = self bot_count_crafted_parts(task.craftablespawn);

			// Origins' shield is a shared three-piece craftable. Its stock table
			// trigger rejects scripted bots in is_player_valid(); use stock craft
			// callbacks directly after all three parts enter shared inventory.
			if(getdvar("mapname") == "zm_tomb" &&
			   isdefined(task.craftablespawn.craftable_name) &&
			   task.craftablespawn.craftable_name == "tomb_shield_zm")
			{
				self bot_run_origins_riotshield_craft(task);
			}
			else
			{
				while(gettime() < use_deadline)
				{
					if(!self bot_objective_can_run())
						break;

					if(self bot_count_crafted_parts(task.craftablespawn) > progress_before)
						break;

					if(!self isonground() || self isonladder() || self ismantling())
					{
						wait 0.1;
						continue;
					}

					// Dispatch the stock trigger and refresh held-use while the
					// native build-progress loop is running.
					table_trigger = undefined;
					if(isdefined(unitrigger_trigger_func) && isdefined(task.stub))
						table_trigger = task.stub [[ unitrigger_trigger_func ]](self);

					self pressusebutton(0.3);
					if(isdefined(table_trigger) &&
					   isdefined(table_trigger.thread_running) && table_trigger.thread_running &&
					   isdefined(table_trigger.parent_player) && table_trigger.parent_player == self)
						table_trigger notify("trigger", self);

					wait 0.15;
				}
			}
		}
		else
		{
			self.bot.is_objective_using = 1;

			while(gettime() < use_deadline)
			{
				if(!self bot_objective_can_run())
					break;

				if(task.stub.persistent == 1 && (self has_player_equipment(task.weaponname) || self hasweapon(task.weaponname)))
					break;

				if(task.stub.persistent == 2 &&
				   (isdefined(task.stub.bought) && task.stub.bought))
					break;

				if(!self isonground() || self isonladder() || self ismantling())
				{
					wait 0.1;
					continue;
				}

				table_trigger = undefined;
				if(isdefined(unitrigger_trigger_func) && isdefined(task.stub))
					table_trigger = task.stub [[ unitrigger_trigger_func ]](self);

				if(isdefined(table_trigger) &&
				   isdefined(table_trigger.thread_running) && table_trigger.thread_running &&
				   isdefined(table_trigger.parent_player) && table_trigger.parent_player == self)
				{
					table_trigger notify("trigger", self);
					wait 0.25;
				}
				else
				{
					self pressusebutton(0.15);
					wait 0.15;
				}
			}
		}

		self.bot.is_objective_using = undefined;
		self clearlookat();
	}


	if(did_interact && task.kind == "pickup" && isdefined(task.piece) &&
	   isdefined(task.piece.model))
	{
		is_shared = isdefined(task.piece.piecestub) && isdefined(task.piece.piecestub.is_shared) && task.piece.piecestub.is_shared;
		picked_up = is_shared && isdefined(task.piece.in_shared_inventory) && task.piece.in_shared_inventory;

		if(!is_shared && isdefined(self.current_craftable_piece) &&
		   self.current_craftable_piece.piecename == task.piece.piecename &&
		   self.current_craftable_piece.craftablename == task.piece.craftablename)
			picked_up = 1;

		if(!picked_up)
		{
			task.piece.bot_auto_retry_until = gettime() + 2500;
			// A failed attempt should not reserve the same model for 5 seconds;
			// allow this bot to retry quickly after it re-approaches the trigger.
		}
	}

	if(did_interact && task.kind == "craft" && isdefined(task.stub))
	{
		if(self bot_count_crafted_parts(task.craftablespawn) <= progress_before)
			task.stub.bot_auto_craft_retry_until = gettime() + 5000;
		else
			task.stub.bot_auto_craft_retry_until = undefined;
	}

	if(task.kind == "equip" && isdefined(task.stub))
	{
		if((task.stub.persistent == 1 && !self has_player_equipment(task.weaponname) && !self hasweapon(task.weaponname)) ||
		   (task.stub.persistent == 2 &&
		    !(isdefined(task.stub.bought) && task.stub.bought)))
			task.stub.bot_auto_equip_retry_until = gettime() + 15000;
		else
			task.stub.bot_auto_equip_retry_until = undefined;
	}

	self bot_release_craftable_task(task);
}


// -----------------------------------------------------------------------------
// Autonomous Easter Egg / map objective support.
// These routines only activate stock map triggers and use the stock map state;
// they never set quest-completion flags directly.
// -----------------------------------------------------------------------------
bot_auto_quest_think()
{
    self endon("disconnect");
    self endon("bot_relife");
    self endon("death");
    level endon("end_game");

    wait randomfloatrange(1.0, 3.0);

    for(;;)
    {
        wait 0.5;

        mapname = getdvar("mapname");

        // Afterlife players must still be allowed to activate Mob's final-flight
        // trigger; the ordinary objective guard intentionally excludes ghosts.
        if(self bot_mob_is_afterlife())
        {
            self bot_quest_mob_plane();
            continue;
        }

        // After the final flight, stock code turns Arlington into the Weasel
        // and makes the other three characters the opposing team. The normal
        // zombie combat target selector deliberately ignores player entities,
        // so a dedicated endgame controller is required for bots to finish it.
        if(mapname == "zm_prison" && self bot_mob_final_fight_think())
            continue;

        if(!self bot_objective_can_run())
            continue;

        if(is_true(self.bot.is_building) || is_true(self.bot.is_crafting) ||
           is_true(self.bot.is_objective_using) || is_true(self.bot.is_perk_buying))
            continue;

        if(mapname == "zm_prison")
            self bot_quest_mob_plane();
        else if(mapname == "zm_tomb")
            self bot_quest_origins();
        else if(mapname == "zm_transit")
            self bot_quest_tranzit();
        else if(mapname == "zm_highrise")
            self bot_quest_die_rise();
        else if(mapname == "zm_buried")
            self bot_quest_buried();
        else if(mapname == "zm_nuked")
            self bot_quest_nuketown();
    }
}

bot_quest_use_target(target, goal_name, range, use_pulses, allow_afterlife, aim_offset)
{
    if(!isdefined(target) || !isdefined(target.origin))
        return false;

    if(!isdefined(range) || range < 24)
        range = 48;

    if(!isdefined(use_pulses) || use_pulses < 1)
        use_pulses = 3;

    afterlife_objective = isdefined(allow_afterlife) && allow_afterlife &&
                          self bot_mob_is_afterlife();

    if(isdefined(target.bot_auto_quest_owner) && target.bot_auto_quest_owner != self &&
       isdefined(target.bot_auto_quest_until) && gettime() < target.bot_auto_quest_until &&
       isalive(target.bot_auto_quest_owner))
        return false;

    target.bot_auto_quest_owner = self;
    target.bot_auto_quest_until = gettime() + 12000;

    if(!findpath(self.origin, target.origin, undefined, 0, 1) &&
       getdvar("mapname") == "zm_highrise")
        self scripts\zm\zm_bo2_bots_map_die_rise::bot_quest_die_rise_elevator_to(target.origin, goal_name + "_elevator", range, 35000);

    if(!findpath(self.origin, target.origin, undefined, 0, 1))
    {
        target.bot_auto_quest_owner = undefined;
        target.bot_auto_quest_until = undefined;
        return false;
    }

    self addgoal(target.origin, range, 2, goal_name);
    deadline = gettime() + 10000;
    arrived = false;

    while(gettime() < deadline)
    {
        if(!self bot_objective_can_run() && !afterlife_objective)
            break;

        if(!isdefined(target) || !isdefined(target.origin))
            break;

        if(distancesquared(self.origin, target.origin) <= range * range)
        {
            arrived = true;
            break;
        }

        wait 0.2;
    }

    self cancelgoal(goal_name);

    if(arrived && isdefined(target) && isdefined(target.origin) &&
       (self bot_objective_can_run() || afterlife_objective))
    {
        self.bot.is_objective_using = 1;
        if(!isdefined(aim_offset))
            aim_offset = 24;
        self lookat(target.origin + (0, 0, aim_offset));
        wait 0.25;

        for(i = 0; i < use_pulses; i++)
        {
            if(!isdefined(target) || !isdefined(target.origin) || !isalive(self))
                break;

            if(!afterlife_objective && (!self isonground() || self isonladder() || self ismantling()))
            {
                wait 0.1;
                continue;
            }

            self pressusebutton(0.15);
            wait 0.2;
        }

        self.bot.is_objective_using = undefined;
        self clearlookat();

        // Leave the trigger volume so stock scripts that wait for the player
        // to exit (e.g. elevator and ordered-symbol triggers) can re-arm.
        if(isdefined(target) && isdefined(target.origin))
        {
            leave_origin = target.origin + (72, 36, 0);
            if(findpath(self.origin, leave_origin, undefined, 0, 1))
            {
                self addgoal(leave_origin, 24, 1, goal_name + "_leave");
                wait 0.45;
                self cancelgoal(goal_name + "_leave");
            }
        }
    }

    if(isdefined(target) && isdefined(target.bot_auto_quest_owner) && target.bot_auto_quest_owner == self)
    {
        target.bot_auto_quest_owner = undefined;
        target.bot_auto_quest_until = undefined;
    }

    return arrived;
}

bot_quest_hold_use_target(target, goal_name, range, hold_time)
{
    if(!isdefined(target) || !isdefined(target.origin))
        return false;
    if(!isdefined(range) || range < 24)
        range = 48;
    if(!isdefined(hold_time) || hold_time < 0.25)
        hold_time = 1.6;

    if(isdefined(target.bot_auto_hold_owner) && target.bot_auto_hold_owner != self &&
       isdefined(target.bot_auto_hold_until) && gettime() < target.bot_auto_hold_until &&
       isalive(target.bot_auto_hold_owner))
        return false;

    target.bot_auto_hold_owner = self;
    target.bot_auto_hold_until = gettime() + 8000;

    if(!findpath(self.origin, target.origin, undefined, 0, 1) &&
       getdvar("mapname") == "zm_highrise")
        self scripts\zm\zm_bo2_bots_map_die_rise::bot_quest_die_rise_elevator_to(target.origin, goal_name + "_elevator", range, 35000);

    if(!findpath(self.origin, target.origin, undefined, 0, 1))
    {
        target.bot_auto_hold_owner = undefined;
        target.bot_auto_hold_until = undefined;
        return false;
    }

    self addgoal(target.origin, range, 2, goal_name);
    deadline = gettime() + 9000;
    arrived = false;
    while(gettime() < deadline && isalive(self))
    {
        if(distancesquared(self.origin, target.origin) <= range * range)
        {
            arrived = true;
            break;
        }
        wait 0.2;
    }
    self cancelgoal(goal_name);

    if(arrived && isdefined(target) && isdefined(target.origin) && self bot_objective_can_run())
    {
        self.bot.is_objective_using = 1;
        self lookat(target.origin + (0, 0, 16));
        self pressusebutton(hold_time);
        wait(hold_time + 0.1);
        self clearlookat();
        self.bot.is_objective_using = undefined;
    }

    if(isdefined(target) && isdefined(target.bot_auto_hold_owner) && target.bot_auto_hold_owner == self)
    {
        target.bot_auto_hold_owner = undefined;
        target.bot_auto_hold_until = undefined;
    }
    return arrived;
}

bot_quest_move_to(origin, goal_name, range, max_time)
{
    if(!isdefined(origin))
        return false;

    if(!isdefined(range))
        range = 96;

    if(!isdefined(max_time))
        max_time = 8000;

    if(!findpath(self.origin, origin, undefined, 0, 1))
    {
        if(getdvar("mapname") != "zm_highrise")
            return false;

        if(!self scripts\zm\zm_bo2_bots_map_die_rise::bot_quest_die_rise_elevator_to(origin, goal_name + "_elevator", range, max_time + 25000))
            return false;

        if(distancesquared(self.origin, origin) <= range * range)
            return true;

        if(!findpath(self.origin, origin, undefined, 0, 1))
            return false;
    }

    afterlife_objective = self bot_mob_is_afterlife();
    self addgoal(origin, range, 2, goal_name);
    deadline = gettime() + max_time;
    arrived = false;

    while(gettime() < deadline)
    {
        if(!self bot_objective_can_run() && !afterlife_objective)
            break;

        if(distancesquared(self.origin, origin) <= range * range)
        {
            arrived = true;
            break;
        }

        wait 0.2;
    }

    self cancelgoal(goal_name);
    return arrived;
}

bot_quest_deploy_equipment(equipment, origin, goal_name)
{
    if(!isdefined(equipment) || !isdefined(origin) || !self has_player_equipment(equipment))
        return false;

    if(!self bot_quest_move_to(origin, goal_name, 72, 10000))
        return false;

    self.bot.is_objective_using = 1;
    self switchtoweaponimmediate(equipment);
    wait 0.35;

    // BO2's placeable-equipment watcher waits for the native grenade_fire
    // event after the weapon-change event creates its carried model. Force the
    // actual equipment release rather than firing the primary-attack input.
    self forcegrenadethrow();
    wait 0.65;

    if(!isdefined(self.buildableturbine) && equipment == "equip_turbine_zm")
    {
        wait 0.3;
        self forcegrenadethrow();
        wait 0.5;
    }

    wait 0.25;
    self.bot.is_objective_using = undefined;

    if(equipment == "equip_turbine_zm")
        return isdefined(self.buildableturbine);

    return true;
}



bot_quest_primary_weapon()
{
    weapons = self getweaponslistprimaries();
    foreach(weapon in weapons)
    {
        if(!isdefined(weapon) || weapon == "none")
            continue;
        if(issubstr(weapon, "staff_") || weapon == "jetgun_zm" || weapon == "slipgun_zm")
            continue;
        return weapon;
    }
    return undefined;
}

bot_quest_fire_at(origin, weapon, goal_name, range, shots, pulse_time)
{
    if(!isdefined(origin) || !isdefined(weapon) || !self hasweapon(weapon))
        return false;

    if(!isdefined(range) || range < 64)
        range = 700;
    if(!isdefined(shots) || shots < 1)
        shots = 1;
    if(!isdefined(pulse_time) || pulse_time < 0.05)
        pulse_time = 0.12;

    if(distancesquared(self.origin, origin) > range * range)
    {
        if(!self bot_quest_move_to(origin, goal_name, 180, 9000))
            return false;
    }

    afterlife_objective = self bot_mob_is_afterlife();
    if(!self bot_objective_can_run() && !afterlife_objective)
        return false;

    self.bot.is_objective_using = 1;
    self switchtoweaponimmediate(weapon);
    wait 0.25;
    for(i = 0; i < shots; i++)
    {
        if(!isalive(self))
            break;
        self lookat(origin);
        self pressattackbutton(pulse_time);
        wait 0.18;
    }
    self.bot.is_objective_using = undefined;
    self clearlookat();
    return true;
}

bot_quest_hold_in_volume(origin, goal_name, radius, hold_time)
{
    if(!isdefined(origin))
        return false;
    if(!isdefined(radius) || radius < 64)
        radius = 160;
    if(!isdefined(hold_time) || hold_time < 0.5)
        hold_time = 3.0;

    if(distancesquared(self.origin, origin) > radius * radius)
    {
        if(!self bot_quest_move_to(origin, goal_name, radius, 9000))
            return false;
    }

    // Keep the combat routine enabled while the bot occupies the quest area.
    // Other squad members can continue killing while this bot fulfills the
    // stock proximity condition.
    self addgoal(origin, radius, 1, goal_name + "_hold");
    deadline = gettime() + int(hold_time * 1000);
    while(gettime() < deadline && isalive(self))
    {
        if(distancesquared(self.origin, origin) > (radius + 80) * (radius + 80))
            break;
        wait 0.2;
    }
    self cancelgoal(goal_name + "_hold");
    return true;
}




































bot_shield_sync_think()
{
	self endon("disconnect");
	self endon("bot_relife");
	self endon("death");
	
	level endon("end_game");
	
	wait randomfloatrange(2.0, 4.0);
	
	for(;;)
	{
		wait 1;
		
		has_shield_weapon = self hasweapon("riotshield_zm") || self hasweapon("alcatraz_shield_zm") || self hasweapon("tomb_shield_zm");
		
		shield_is_broken = isdefined(self.shielddamagetaken) && isdefined(level.zombie_vars["riotshield_hit_points"]) && self.shielddamagetaken >= level.zombie_vars["riotshield_hit_points"];
		
		if(has_shield_weapon && !shield_is_broken)
			continue;
		
		if(is_true(self.bot.is_getting_shield))
		{
			if(isdefined(self.bot.shield_grant_started) && (gettime() - self.bot.shield_grant_started) > 5000)
				self.bot.is_getting_shield = undefined;
			
			continue;
		}
		
		if(!bot_has_shield())
			continue;
		
		self thread bot_give_shield();
	}
}

bot_has_shield()
{
	players = get_players();
	
	foreach(player in players)
	{
		if(!isdefined(player) || isdefined(player.pers["isbot"]))
			continue;
		
		if(!isalive(player))
			continue;
		
		if(player hasweapon("riotshield_zm") || player hasweapon("alcatraz_shield_zm") || player hasweapon("tomb_shield_zm"))
			return true;
	}
	
	return false;
}

bot_grant_map_shield(shield_weapon, current_weapon)
{
	if(!isdefined(shield_weapon))
		return;

	if(self hasweapon(shield_weapon))
		self takeweapon(shield_weapon);

	self giveweapon(shield_weapon);
	self.shielddamagetaken = 0;
	self allowattack(0);
	self pressads(0);
	self switchtoweapon(shield_weapon);

	switch_timeout = gettime() + 1000;
	while(self isswitchingweapons() && gettime() < switch_timeout)
		wait 0.05;

	wait 0.75;

	if(isdefined(current_weapon) && current_weapon != "none" && current_weapon != shield_weapon)
	{
		self allowattack(0);
		self pressads(0);
		self switchtoweapon(current_weapon);
		switch_timeout = gettime() + 1000;
		while(self isswitchingweapons() && gettime() < switch_timeout)
			wait 0.05;
	}
}

bot_give_shield()
{
	self endon("disconnect");
	self endon("death");
	
	if(is_true(self.bot.is_getting_shield))
		return;
	
	if((self hasweapon("riotshield_zm") || self hasweapon("alcatraz_shield_zm") || self hasweapon("tomb_shield_zm")) && 
	   (!isdefined(self.shielddamagetaken) || !isdefined(level.zombie_vars["riotshield_hit_points"]) || 
	    self.shielddamagetaken < level.zombie_vars["riotshield_hit_points"]))
	{
		self.bot.is_getting_shield = undefined;
		return;
	}
	
	self.bot.is_getting_shield = true;
	
	self.bot.shield_grant_started = gettime();
	
    while(is_true(self.afterlife))
	{
		wait 0.05;
	}
	
	while(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
	{
		wait 0.05;
	}
	
	while(!self isonground() || self isonladder() || self ismantling())
	{
		wait 0.05;
	}
	
	while(self isreloading() || self isswitchingweapons() || self isthrowinggrenade())
	{
		wait 0.05;
	}
	
	while(is_true(self.bot.is_meleeing) || is_true(self.bot.is_throwing_grenade) || is_true(self.bot.is_buying) || is_true(self.bot.is_using_box) || is_true(self.bot.is_reviving) || is_true(self.bot.is_selfreviving) || is_true(self.bot.is_building) || is_true(self.bot.is_crafting) || is_true(self.bot.is_perk_buying))
	{
		wait 0.05;
	}
	
	if((self hasweapon("riotshield_zm") || self hasweapon("alcatraz_shield_zm") || self hasweapon("tomb_shield_zm")) && 
	   (!isdefined(self.shielddamagetaken) || !isdefined(level.zombie_vars["riotshield_hit_points"]) || 
        self.shielddamagetaken < level.zombie_vars["riotshield_hit_points"]))
	{
		self.bot.is_getting_shield = undefined;
		
		return;
	}
	
	current_weapon = self getcurrentweapon();
	
	if(current_weapon == "none")
	{
		primaries = self getweaponslistprimaries();
		
		if(isdefined(primaries) && primaries.size > 0)
			current_weapon = primaries[0];
	}
	
	mapname = getdvar("mapname");
	if(mapname == "zm_transit")
		self bot_tranzit_grant_shield(current_weapon);
	else if(mapname == "zm_prison")
		self bot_mob_grant_shield(current_weapon);
	else if(mapname == "zm_tomb")
		self bot_origins_grant_shield(current_weapon);

	self.bot.is_getting_shield = undefined;
}

bot_weapon_switch_think()
{
    self endon("disconnect");
	self endon("bot_relife");
	self endon("death");
	
    level endon("end_game");

    wait randomfloatrange(3.0, 4.0);

    for(;;)
    {
        wait randomfloatrange(6.0, 8.0);
		
        if(self bot_mob_is_afterlife())
		{
			wait 0.05;
			
			continue;
		}
		
		if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		{
			wait 0.05;
			
			continue;
		}
		
        if(!self isonground() || self isonladder() || self ismantling())
		{
			wait 0.05;
			
			continue;
		}
		
        if(is_true(self.bot.is_meleeing) || is_true(self.bot.is_throwing_grenade) || is_true(self.bot.is_getting_shield) || is_true(self.bot.is_buying) || is_true(self.bot.is_using_box) || is_true(self.bot.is_reviving) || is_true(self.bot.is_selfreviving) || is_true(self.bot.is_building) || is_true(self.bot.is_crafting) || is_true(self.bot.is_objective_using) || is_true(self.bot.is_perk_buying))
		{
			wait 0.05;
			
			continue;
		}

        if(self isreloading() || self isswitchingweapons() || self isthrowinggrenade())
		{
			wait 0.05;
			
			continue;
		}

        if(isdefined(self.bot.next_weapon_switch) && gettime() < self.bot.next_weapon_switch)
		{
			wait 0.05;
			
			continue;
		}

        primaries = self getweaponslistprimaries();

        if(!isdefined(primaries) || primaries.size < 2)
            continue;

        current = self getcurrentweapon();

        if(current == "none")
            continue;

        weapon = bot_switch_weapon(current, primaries);

        if(isdefined(weapon) && weapon != current)
        {
            self allowattack(0);
            self pressads(0);
			
            self switchtoweapon(weapon);
			
            self.bot.next_weapon_switch = gettime() + randomintrange(30000, 90000);
        }
    }
}

bot_switch_weapon(current_weapon, primaries)
{
    target_distance = undefined;

    if(isdefined(self.bot.threat.entity) && isalive(self.bot.threat.entity))
        target_distance = distance(self.origin, self.bot.threat.entity.origin);

    current_score = self bot_weapon_tactical_score(current_weapon, target_distance);
    best_weapon = undefined;
    best_score = -999999;

    foreach(weapon in primaries)
    {
        if(weapon == current_weapon)
            continue;

        score = self bot_weapon_tactical_score(weapon, target_distance);

        if(score > best_score)
        {
            best_score = score;
            best_weapon = weapon;
        }
    }

    if(!isdefined(best_weapon))
        return undefined;

    // Keep a working weapon unless another option is clearly better.
    // An empty weapon is always abandoned when another weapon has ammunition.
    if(current_score > -50000 && best_score < current_score + 80)
        return undefined;

    return best_weapon;
}

bot_weapon_tactical_score(weapon, target_distance)
{
    if(!isdefined(weapon) || weapon == "none")
        return -999999;

    clip = self getweaponammoclip(weapon);
    stock = self getweaponammostock(weapon);
    total_ammo = clip + stock;

    if(total_ammo <= 0)
        return -99999;

    score = self bot_get_weapon_score(weapon) * 10;
    max_clip = weaponclipsize(weapon);

    if(max_clip > 0 && clip > 0)
        score += (clip * 30) / max_clip;
    else if(clip <= 0)
        score -= 25;

    if(stock > 0)
        score += 10;
    else
        score -= 10;

    if(isdefined(target_distance))
    {
        class = weaponclass(weapon);

        if(target_distance < 300)
        {
            if(class == "spread")
                score += 130;
            else if(class == "smg")
                score += 70;
            else if(class == "pistol")
                score += 25;
            else if(class == "mg" || class == "rifle")
                score -= 25;
        }
        else if(target_distance > 600)
        {
            if(class == "mg" || class == "rifle")
                score += 65;
            else if(class == "spread")
                score -= 75;
            else if(class == "smg")
                score -= 15;
        }
    }

    // Use weapons that actually damage the boss armor efficiently.
    // Panzer's stock damage handler gives elemental staffs a stronger damage floor;
    // Brutus takes 1.5x shotgun damage and needs repeated helmet hits.
    threat = self.bot.threat.entity;
    if(isdefined(threat) && isalive(threat))
    {
        class = weaponclass(weapon);

        if(is_true(threat.is_mechz))
        {
            if(issubstr(weapon, "staff_"))
                score += 220;
            else if(class == "mg")
                score += 170;
            else if(class == "rifle")
                score += 130;
            else if(class == "spread")
                score += 100;
            else if(class == "smg")
                score += 65;

            if(isdefined(target_distance) && target_distance > 700 && class == "spread")
                score -= 80;
        }
        else if(is_true(threat.is_brutus))
        {
            if(class == "spread")
                score += 200;
            else if(class == "mg")
                score += 150;
            else if(class == "rifle")
                score += 110;
            else if(class == "smg")
                score += 70;
        }
    }

    return score;
}

bot_weapon_failsafe_monitor()
{
    self endon("disconnect");
	self endon("bot_relife");
	self endon("death");
	
	level endon("end_game");
    
    for(;;)
    {
        wait 1;
		
        if(self bot_mob_is_afterlife())
		{
			wait 0.05;
			
			continue;
		}
		
		if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		{
			wait 0.05;
			
			continue;
		}
		
        if(!self isonground() || self isonladder() || self ismantling())
		{
			wait 0.05;
			
			continue;
		}
        
        if(is_true(self.bot.is_meleeing) || is_true(self.bot.is_throwing_grenade) || is_true(self.bot.is_getting_shield) || is_true(self.bot.is_buying) || is_true(self.bot.is_using_box) || is_true(self.bot.is_reviving) || is_true(self.bot.is_selfreviving) || is_true(self.bot.is_building) || is_true(self.bot.is_crafting) || is_true(self.bot.is_perk_buying))
		{
			wait 0.05;
			
			continue;
		}
		
        if(self isreloading() || self isswitchingweapons() || self isthrowinggrenade())
		{
			wait 0.05;
			
			continue;
		}

        weapon = self getcurrentweapon();
		
        primaries = self getweaponslistprimaries();
        
        if(weapon == "none" || !isdefined(primaries) || primaries.size == 0)
        {
            wait 5;

            weapon = self getcurrentweapon();
			
            primaries = self getweaponslistprimaries();

            if(weapon != "none" && isdefined(primaries) && primaries.size > 0)
                continue;

            fallback_weapon = "ray_gun_zm";
            
			if(weapon != "none")
				self takeweapon(weapon);
			
			if(isdefined(primaries) && primaries.size > 0)
			{
				for(i = 0; i < primaries.size; i++)
					self takeweapon(primaries[i]);
			}
			
			self giveweapon(fallback_weapon);
			self switchtoweapon(fallback_weapon);
			self setspawnweapon(fallback_weapon);
        }
    }
}

bot_give_ammo()
{
	self endon("disconnect");
	self endon("bot_relife");
	self endon("death");
	
	level endon("end_game");
	
	for(;;)
	{
		primary_weapons = self getweaponslistprimaries();
		
		j = 0;
		
		while(j < primary_weapons.size)
		{
			self givemaxammo(primary_weapons[j]);
			
			j++;
		}
		
		wait 1;
	}
}

bot_stand_fix()
{
	if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		return;
	
	if(self isonground() && (self getstance() == "crouch" || self getstance() == "prone"))
	{
		self botaction(bot_action_stand);
	}
}

array_contains(array, value)
{
	if(!isdefined(array) || !array.size)
		return false;
	
	foreach(item in array)
	{
		if(item == value)
			return true;
		
		if(distancesquared(item, value) < 100)
			return true;
	}
	
	return false;
}

bot_wakeup_think()
{
	self endon("disconnect");
	self endon("bot_relife");
	self endon("death");
	
	level endon("end_game");
	
	for(;;)
	{
		wait self.bot.think_interval;
		
		self notify("wakeup");
	}
}

bot_damage_think()
{
	self notify("bot_damage_think");
	
	self endon("bot_damage_think");
	
	self endon("bot_relife");
	
	self endon("disconnect");
	self endon("death");
	
	level endon("end_game");
	
	for(;;)
	{
		self waittill("damage", damage, attacker, direction, point, mod, unused1, unused2, unused3, weapon, flags, inflictor);
		
		self.bot.attacker = attacker;
		self.bot.attacker_time = gettime();
		
		self notify("wakeup", damage, attacker, direction);
	}
}

bot_reset_flee_goal()
{
	self endon("disconnect");
	self endon("bot_relife");
	self endon("death");
	
	level endon("end_game");
	
	while(1)
	{
		wait 0.25;
		
		if(!self hasgoal("flee"))
			continue;
		
		if(!isdefined(self.bot.flee_goal_time) || gettime() - self.bot.flee_goal_time > 8000)
		{
			self cancelgoal("flee");
			
			continue;
		}
		
		if(self bot_flee_goal_unsafe())
		{
			self cancelgoal("flee");
			
			self.bot.next_flee_scan = 0;
		}
	}
}

bot_get_closest_enemy(origin)
{
	enemies = get_cached_zombies();
	enemies = arraysort(enemies, origin);
	
	if(enemies.size >= 1)
	{
		return enemies[0];
	}
	
	return undefined;
}

bot_update_lookat()
{
	if(is_true(self.bot.is_building) || is_true(self.bot.is_crafting) ||
	   is_true(self.bot.is_perk_buying))
		return;

	path = 0;
	
	if(isdefined(self getlookaheaddir()))
	{
		path = 1;
	}
	
	if(!path && gettime() > self.bot.update_idle_lookat)
	{
		origin = bot_get_look_at();
		
		if(!isdefined(origin))
		{
			return;
		}
		
		self lookat(origin + vectorscale((0, 0, 1), 16));
		
		self.bot.update_idle_lookat = gettime() + randomintrange(1500, 3000);
	}
	else if(path && self.bot.update_idle_lookat > 0)
	{
		self clearlookat();
		
		self.bot.update_idle_lookat = 0;
	}
}

bot_get_look_at()
{
	enemy = bot_get_closest_enemy(self.origin);
	
	if(isdefined(enemy))
	{
		node = getvisiblenode(self.origin, enemy.origin);
		
		if(isdefined(node) && distancesquared(self.origin, node.origin) > 1024)
		{
			return node.origin;
		}
	}
	
	spawn = self getgoal("wander");
	
	if(isdefined(spawn))
	{
		node = getvisiblenode(self.origin, spawn);
	}
	
	if(isdefined(node) && distancesquared(self.origin, node.origin) > 1024)
	{
		return node.origin;
	}
	
	return undefined;
}

bot_nearest_node(origin)
{
	node = getnearestnode(origin);
	
	if(isdefined(node))
	{
		return node;
	}
	
	nodes = getnodesinradiussorted(origin, 256, 0, 32);
	
	if(nodes.size)
	{
		return nodes[0];
	}
	
	return undefined;
}