#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_laststand;

#include scripts\zm\zm_bo2_bots;

/*
	SMART COMBAT UPGRADE

	What changed compared to the stock file:
	  - Situational awareness: one cheap scan per ~100ms gives every combat decision the same
	    picture (how many zombies are touching me, how many are near, is a boss close, how hurt am I).
	  - Flee logic is danger/health based instead of "any zombie within 75 units". Bots stand and
	    kill lone zombies, but bail out early when swarmed, hurt, out of ammo or a boss is close.
	    Flee nodes now also prefer regrouping with teammates and have a fallback when no hidden node exists.
	  - Target selection: only the nearest few zombies get a (costly) line-of-sight trace, weapon based
	    engagement range, finishing off weak zombies, zombies chasing me, splash-weapon cluster targeting,
	    stronger target stickiness for zombies that are already in my face.
	  - Aiming: headshots on normal zombies (not with shotguns / splash weapons), adaptive prediction.
	  - Weapon handling: emergency swap on empty magazine / empty weapon instead of standing there,
	    no self-damage with explosive weapons (they swap away when zombies are close), no more
	    "reload until full" while zombies are chewing on the bot, no ADS when crowded.
	  - Grenades: finds the densest cluster (250 unit radius) instead of any 5 zombies within 600,
	    keeps a safe distance, needs line of sight, threshold drops in high rounds / when in danger.
	  - Melee: never starts a knife fight when swarmed (unless insta-kill).
	  - Dead target no longer freezes the bot for 0.35s, it retargets right away.

	All original function names are kept so the main script and map scripts keep working.
*/

bot_combat_think(damage, attacker, direction)
{
	// Map objectives control aim and attack input while this lock is active.
	// Do not let normal combat AI take over during robot entry or other quests.
	if(is_true(self.bot.is_objective_using))
	{
		self allowattack(0);
		self pressads(0);
		return;
	}

	if(is_true(self.bot.is_getting_shield) || is_true(self.bot.is_throwing_grenade))
	{
		self allowattack(0);
		self pressads(0);
		
		return;
	}
	
	self allowattack(0);
	self pressads(0);
	
	if(!bot_can_do_combat())
		return;
	
	if(self atgoal("flee"))
		self cancelgoal("flee");
	
	follow_mode = isdefined(level.bot_command_mode) && level.bot_command_mode == "follow" && isdefined(level.bot_commander);
	
	if(follow_mode && (self getgoal("flee") || self hasgoal("flee")))
		self cancelgoal("flee");
	
	self bot_update_situation();
	
	if(!follow_mode && !self hasgoal("flee") && !self bot_flee_blocked() && self bot_should_flee(damage))
	{
		now = gettime();
		
		if(!isdefined(self.bot.next_flee_scan) || now > self.bot.next_flee_scan)
		{
			if(self.bot.danger >= 8)
				self.bot.next_flee_scan = now + 600;
			else if(get_players().size > 4)
				self.bot.next_flee_scan = now + 3000;
			else
				self.bot.next_flee_scan = now + 1500;
			
			self bot_flee_goal();
		}
	}
	
	if(self getcurrentweapon() == "none")
		return;
	
	sight = self bot_best_enemy();
	
	if(!sight && !self bot_has_enemy())
	{
		self allowattack(0);
		self pressads(0);
		
		return;
	}
	
	if(!isdefined(self.bot.threat.entity))
		return;
	
	if(self threat_dead())
	{
		self bot_combat_dead();
		
		return;
	}
	
	self bot_combat_main();
}

// ---------------------------------------------------------------------------------------------
// Situation / danger model
// ---------------------------------------------------------------------------------------------

bot_health_fraction()
{
	maxhp = self.maxhealth;
	
	if(!isdefined(maxhp) || maxhp <= 0)
		maxhp = 100;
	
	frac = self.health / maxhp;
	
	return clamp(frac, 0, 1);
}

bot_update_situation()
{
	now = gettime();
	
	if(isdefined(self.bot.sit_time) && (now - self.bot.sit_time) < 100)
		return;
	
	self.bot.sit_time = now;
	self.bot.close_count = 0;
	self.bot.near_count = 0;
	self.bot.nearest_dist = 99999;
	self.bot.danger = 0;
	self.bot.boss_near = false;
	
	zombies = get_cached_zombies();
	
	if(!isdefined(zombies))
		return;
	
	danger = 0;
	
	foreach(zombie in zombies)
	{
		if(!isdefined(zombie) || !isalive(zombie))
			continue;
		
		if(is_true(zombie.in_the_ground))
			continue;
		
		d = distancesquared(self.origin, zombie.origin);
		
		if(d > 202500)
			continue;
		
		dist = sqrt(d);
		
		if(dist < self.bot.nearest_dist)
			self.bot.nearest_dist = dist;
		
		if(is_true(zombie.is_brutus) || is_true(zombie.is_mechz))
		{
			if(dist < 450)
			{
				self.bot.boss_near = true;
				
				danger += 5;
			}
		}
		
		if(d > 90000)
			continue;
		
		self.bot.near_count++;
		
		if(d < 4900)
			danger += 3;
		else if(d < 16900)
			danger += 2;
		else if(d < 40000)
			danger += 1;
		else
			danger += 0.4;
		
		if(d < 16900)
			self.bot.close_count++;
	}
	
	self.bot.danger = danger;
}

bot_weapon_is_weak()
{
	weapon = self getcurrentweapon();
	
	if(weapon == "none")
		return true;
	
	clip = self getweaponammoclip(weapon);
	stock = self getweaponammostock(weapon);
	
	if(clip + stock <= 0)
		return true;
	
	if(clip <= 0)
		return true;
	
	return false;
}

bot_should_flee(damage)
{
	hp = self bot_health_fraction();
	
	// Hurt bots bail out earlier, healthy bots stand their ground against one or two zombies.
	threshold = 5.0 - ((1.0 - hp) * 3.0);
	
	if(self bot_weapon_is_weak())
		threshold -= 1.0;
	
	if(threshold < 2.0)
		threshold = 2.0;
	
	danger = self.bot.danger;
	
	if(isdefined(damage))
		danger += 1.0;
	
	return danger >= threshold;
}

bot_flee_blocked()
{
	if(is_true(self.bot.is_buying) || self hasgoal("boxbuy") || is_true(self.bot.is_using_box))
		return true;
	
	if(self hasgoal("revive") || is_true(self.bot.is_reviving))
		return true;
	
	if(self hasgoal("selfrevive") || is_true(self.bot.is_selfreviving))
		return true;
	
	return false;
}

// ---------------------------------------------------------------------------------------------
// Fleeing
// ---------------------------------------------------------------------------------------------

bot_get_flee_goal(max_dist)
{
    candidate = [];

    zombies = get_cached_zombies();

    if(!isdefined(zombies))
        return candidate;

    max_dist_sq = max_dist * max_dist;

    foreach(zombie in zombies)
    {
        if(!isdefined(zombie) || !isalive(zombie))
            continue;

        if(distancesquared(self.origin, zombie.origin) > max_dist_sq)
            continue;

        candidate[candidate.size] = zombie;
    }

    return candidate;
}

bot_get_team_center()
{
	players = get_players();
	
	sum = (0, 0, 0);
	
	count = 0;
	
	foreach(player in players)
	{
		if(!isdefined(player) || player == self || !isalive(player))
			continue;
		
		if(player.sessionstate != "playing")
			continue;
		
		if(player maps\mp\zombies\_zm_laststand::player_is_in_laststand())
			continue;
		
		sum += player.origin;
		
		count++;
	}
	
	if(count == 0)
		return undefined;
	
	return sum * (1.0 / count);
}

bot_flee_goal()
{
    nearest = bot_nearest_node(self.origin);

    if(!isdefined(nearest))
        return;

    nodes = getnodesinradiussorted(self.origin, 1024, 640, 512);

    if(!isdefined(nodes) || nodes.size == 0)
        return;

    zombies = self bot_get_flee_goal(1400);

    threat_pos = undefined;
	
    closest_sq = 99999999;

    foreach(zombie in zombies)
    {
        d = distancesquared(self.origin, zombie.origin);

        if(d < closest_sq)
        {
            closest_sq = d;
			
            threat_pos = zombie.origin;
        }
    }

    if(!isdefined(threat_pos) && isdefined(self.bot.threat.entity) && isdefined(self.bot.threat.position))
        threat_pos = self.bot.threat.position;

    threat_dir = undefined;

    if(isdefined(threat_pos) && distance2d(self.origin, threat_pos) > 1)
    {
        to_threat = (threat_pos[0] - self.origin[0], threat_pos[1] - self.origin[1], 0);

        threat_dir = vectornormalize(to_threat);
    }

    team_pos = self bot_get_team_center();

    cand_nodes = [];
	
    cand_scores = [];

    // Pass 0 only accepts nodes that break line of sight. If the bot is in the open and nothing
    // like that exists, pass 1 accepts visible nodes as long as they are far away from every zombie.
    for(pass = 0; pass < 2 && cand_nodes.size == 0; pass++)
    {
        checked = 0;

        foreach(node in nodes)
        {
            if(checked >= 48)
                break;

            checked++;

            visible = nodesvisible(nearest, node);

            if(pass == 0 && visible)
                continue;

            score = self bot_score_flee_node(node, zombies, threat_dir, team_pos);

            if(!isdefined(score))
                continue;

            if(visible)
                score += 120;

            cand_nodes[cand_nodes.size] = node;
			
            cand_scores[cand_scores.size] = score;
        }
    }

    max_score = 400;

    path_checks = 0;

    while(path_checks < 5 && cand_nodes.size > 0)
    {
        best = 0;

        for(i = 1; i < cand_nodes.size; i++)
        {
            if(cand_scores[i] < cand_scores[best])
                best = i;
        }

        if(cand_scores[best] > max_score)
            break;

        best_node = cand_nodes[best];

        cand_scores[best] = 99999;

        path_checks++;

        if(findpath(self.origin, best_node.origin, undefined, 0, 1))
        {
            self addgoal(best_node.origin, 50, 4, "flee");

            self.bot.flee_goal_time = gettime();

            return;
        }
    }
}

bot_score_flee_node(node, zombies, threat_dir, team_pos)
{
    node_dist = distance2d(self.origin, node.origin);

    if(node_dist < 1)
        return undefined;

    node_point = (node.origin[0] - self.origin[0], node.origin[1] - self.origin[1], 0);

    dir = vectornormalize(node_point);

    score = node_dist * 0.1;

    if(isdefined(threat_dir))
        score += vectordot(dir, threat_dir) * 200;

    // Run toward teammates: safer, and they help kill what is chasing us.
    if(isdefined(team_pos))
    {
        cur = distance2d(self.origin, team_pos);
        new = distance2d(node.origin, team_pos);

        if(new < cur)
        {
            bonus = (cur - new) * 0.3;

            if(bonus > 120)
                bonus = 120;

            score -= bonus;
        }
        else
        {
            malus = (new - cur) * 0.2;

            if(malus > 80)
                malus = 80;

            score += malus;
        }
    }

    foreach(zombie in zombies)
    {
        node_gap = distance2d(zombie.origin, node.origin);

        if(node_gap < 200)
            return undefined;

        if(node_gap < 350)
            score += (350 - node_gap) * 0.6;

        zombie_pos = (zombie.origin[0] - self.origin[0], zombie.origin[1] - self.origin[1], 0);

        along = vectordot(dir, zombie_pos);

        if(along > 0 && along < node_dist + 100)
        {
            zombie_dist = distance2d(self.origin, zombie.origin);

            lateral_sq = zombie_dist * zombie_dist - along * along;

            if(lateral_sq < 0)
                lateral_sq = 0;

            lateral = sqrt(lateral_sq);

            if(lateral < 110)
                return undefined;

            if(lateral < 250)
                score += (250 - lateral) * 0.7;
        }
    }

    return score;
}

bot_flee_goal_unsafe()
{
    goal = self getgoal("flee");

    if(!isdefined(goal))
        return false;

    goal_dist = distance2d(self.origin, goal);

    if(goal_dist < 1)
        return false;

    goal_point = (goal[0] - self.origin[0], goal[1] - self.origin[1], 0);

    dir = vectornormalize(goal_point);

    zombies = self bot_get_flee_goal(1200);

    foreach(zombie in zombies)
    {
        if(distance2d(zombie.origin, goal) < 150)
            return true;

        zombie_pos = (zombie.origin[0] - self.origin[0], zombie.origin[1] - self.origin[1], 0);

        along = vectordot(dir, zombie_pos);

        if(along > 50 && along < goal_dist)
        {
            zombie_dist = distance2d(self.origin, zombie.origin);

            lateral_sq = zombie_dist * zombie_dist - along * along;

            if(lateral_sq < 0)
                lateral_sq = 0;

            if(sqrt(lateral_sq) < 90)
                return true;
        }
    }

    return false;
}

// ---------------------------------------------------------------------------------------------
// Main combat
// ---------------------------------------------------------------------------------------------

bot_combat_main()
{
	self bot_update_situation();
	
	if(self bot_should_melee())
	{
		if(!is_true(self.bot.is_meleeing))
			self thread bot_combat_melee();
		
		return;
	}
	
    if(self bot_should_throw_grenade())
    {
		if(!is_true(self.bot.is_throwing_grenade))
			self thread bot_combat_throw_grenade();
        
        return;
    }
	
	weapon = self getcurrentweapon();
	
	// Never stand around with an empty / dangerous weapon when a better one is in the holster.
	if(self bot_combat_try_weapon_swap(weapon))
		return;
	
	if(self isswitchingweapons())
		return;
	
	if(self isreloading())
	{
		clip = self getweaponammoclip(weapon);
		
		max = weaponclipsize(weapon);

		if(clip < max && self bot_reload_is_safe())
		{
			self.bot.reload_until_full = true;
		}
	}
	
	currentammo = self getweaponammoclip(weapon) + self getweaponammostock(weapon);
	
	if(!currentammo)
	{
		return;
	}
	
	ads = 0;
	
	time = gettime();
	
	if(!self bot_should_hip_fire() && self.bot.threat.dot > 0.96 && self.bot.near_count <= 1 && self.bot.nearest_dist > 250 && !self hasgoal("flee"))
	{
		ads = 1;
	}
	
	if(ads)
	{
		self pressads(1);
	}
	else
	{
		self pressads(0);
	}
	
	if(time >= self.bot.threat.time_aim_correct)
	{
		self.bot.threat.time_aim_correct += self.bot.threat.time_aim_interval;
		
		frac = (time - self.bot.threat.time_first_sight) / 50;
		frac = clamp(frac, 0, 1);
		
		if(!self threat_is_player())
		{
			frac = 1;
		}
		
		// Short prediction up close, longer prediction at range.
		tdist = distance(self.origin, self.bot.threat.entity.origin);
		
		frames = 4;
		
		if(tdist < 250)
			frames = 2;
		else if(tdist > 700)
			frames = 6;
		
		self.bot.threat.aim_target = self bot_update_aim(frames);
		self.bot.threat.position = self.bot.threat.entity.origin;
		self bot_combat_lookat(self.bot.threat.aim_target, frac);
	}
	
	if(isdefined(self.bot.reload_until_full) && self.bot.reload_until_full)
	{
		clip = self getweaponammoclip(weapon);
		
		max = weaponclipsize(weapon);

		// Zombies in my face: stop babysitting the reload, shoot whatever is loaded.
		if(clip >= max || !self isreloading() || (!self bot_reload_is_safe() && clip > 0))
		{
			self.bot.reload_until_full = undefined;
		}
		else
		{
			self allowattack(0);
			
			return;
		}
	}
	
	aim_point = self.bot.threat.aim_target;
	
	if(!isdefined(aim_point))
	{
		aim_point = self.bot.threat.entity.origin;
	}
	
	if(self bot_on_target(aim_point, self bot_get_fire_radius(aim_point)) && self bot_can_fire_safely(weapon))
	{
		self allowattack(1);
	}
	else
	{
		self allowattack(0);
	}
	
	if(is_true(self.stingerlockstarted))
	{
		self allowattack(self.stingerlockfinalized);
		
		return;
	}
}

bot_reload_is_safe()
{
	if(self.bot.close_count > 0)
		return false;
	
	if(self.bot.nearest_dist < 250)
		return false;
	
	return true;
}

bot_can_fire_safely(weapon)
{
	enemy = self.bot.threat.entity;
	
	if(!isdefined(enemy))
		return false;
	
	dist = distance(self.origin, enemy.origin);
	
	// Splash weapons (Ray Gun, M32, ...) hurt the bot when used point blank.
	if(self bot_is_splash_weapon(weapon) && dist < 130)
		return false;
	
	// No line of sight = don't burn ammo into a wall, unless the zombie is basically touching us.
	if(isdefined(self.bot.threat.visible) && !self.bot.threat.visible && dist > 120)
		return false;
	
	return true;
}

bot_is_splash_weapon(weapon)
{
	if(!isdefined(weapon) || weapon == "none")
		return false;
	
	if(issubstr(weapon, "ray_gun") || issubstr(weapon, "raygun"))
		return true;
	
	if(issubstr(weapon, "m32") || issubstr(weapon, "china_lake") || issubstr(weapon, "rpg"))
		return true;
	
	if(issubstr(weapon, "crossbow_explosive"))
		return true;
	
	return false;
}

bot_get_swap_weapon(current, need_clip, avoid_splash, dist)
{
	primaries = self getweaponslistprimaries();
	
	if(!isdefined(primaries) || primaries.size < 2)
		return undefined;
	
	best = undefined;
	best_score = -999999;
	
	foreach(weapon in primaries)
	{
		if(weapon == current || weapon == "none")
			continue;
		
		clip = self getweaponammoclip(weapon);
		stock = self getweaponammostock(weapon);
		
		if(clip + stock <= 0)
			continue;
		
		if(need_clip && clip <= 0)
			continue;
		
		if(avoid_splash && self bot_is_splash_weapon(weapon))
			continue;
		
		score = self bot_weapon_tactical_score(weapon, dist);
		
		if(score > best_score)
		{
			best_score = score;
			best = weapon;
		}
	}
	
	return best;
}

bot_combat_try_weapon_swap(weapon)
{
	now = gettime();
	
	if(isdefined(self.bot.next_combat_swap) && now < self.bot.next_combat_swap)
		return false;
	
	if(self isthrowinggrenade() || self isswitchingweapons())
		return false;
	
	enemy = self.bot.threat.entity;
	
	if(!isdefined(enemy))
		return false;
	
	dist = distance(self.origin, enemy.origin);
	
	clip = self getweaponammoclip(weapon);
	stock = self getweaponammostock(weapon);
	max = weaponclipsize(weapon);
	
	new_weapon = undefined;
	
	// 1) Weapon is completely empty: use anything that still shoots.
	if(clip + stock <= 0)
	{
		new_weapon = self bot_get_swap_weapon(weapon, true, false, dist);
	}
	// 2) Explosive weapon with zombies on top of us: switch to something that doesn't hurt us.
	else if(self bot_is_splash_weapon(weapon) && dist < 130)
	{
		new_weapon = self bot_get_swap_weapon(weapon, true, true, dist);
	}
	// 3) Empty / nearly empty magazine while zombies are close: a loaded gun beats a reload animation.
	else if((clip <= 0 || (self isreloading() && max > 0 && clip < (max * 0.25))) && (dist < 260 || self.bot.close_count > 0))
	{
		new_weapon = self bot_get_swap_weapon(weapon, true, self.bot.close_count > 0, dist);
	}
	
	if(!isdefined(new_weapon) || new_weapon == weapon)
		return false;
	
	self allowattack(0);
	self pressads(0);
	
	self switchtoweapon(new_weapon);
	
	self.bot.next_combat_swap = now + 1200;
	self.bot.next_weapon_switch = now + randomintrange(15000, 30000);
	self.bot.reload_until_full = undefined;
	
	return true;
}

bot_has_ballistic_knife()
{
    weapon = self getcurrentweapon();

    if(issubstr(weapon, "ballistic"))
        return true;

    return false;
}

bot_should_melee()
{
	if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		return false;
	
    if(!self isonground() || self getstance() == "prone")
        return false;
	
	if(is_true(self.bot.is_buying) || is_true(self.bot.is_using_box) || is_true(self.bot.is_reviving) || is_true(self.bot.is_selfreviving))
		return false;
	
    if(self isreloading() || self isswitchingweapons() || self isthrowinggrenade())
        return false;
	
    threat = self.bot.threat.entity;
	
    if(!isdefined(threat) || !isalive(threat))
        return false;
	
    if(!isdefined(threat.health))
        return false;
	
    knife_damage = getdvarintdefault("bot_knife_kill_threshold", 150);
	
    insta_kill_on = level.zombie_vars[self.team]["zombie_powerup_insta_kill_on"];
	
    has_ballistic_knife = self bot_has_ballistic_knife();
	
	if(!insta_kill_on && !has_ballistic_knife && !is_true(threat.isscreecher) && !is_true(threat.is_avogadro) && threat.health > knife_damage)
        return false;
	
	if(is_true(threat.is_brutus) || is_true(threat.is_mechz))
		return false;
	
	// A knife swing leaves the bot standing still; don't do it while several zombies are hitting us.
	self bot_update_situation();
	
	if(!insta_kill_on && self.bot.close_count >= 3)
		return false;
	
    melee_range = getdvarfloatdefault("bot_meleedist", 70);
	
    if(distance(self.origin, threat.origin) > melee_range)
        return false;
	
    return true;
}

bot_combat_melee()
{
    self endon("disconnect");
    self endon("death");

    if(is_true(self.bot.is_meleeing))
        return;

    self.bot.is_meleeing = true;

    self allowattack(0);
    self pressads(0);

    threat = self.bot.threat.entity;

    if(isdefined(threat))
        self bot_lookat_entity(threat);

    self pressmelee();

    wait 0.5;

    self.bot.is_meleeing = undefined;
}

// ---------------------------------------------------------------------------------------------
// Grenades
// ---------------------------------------------------------------------------------------------

bot_get_grenade_required_cluster()
{
	round_number = 1;
	
	if(isdefined(level.round_number))
		round_number = level.round_number;
	
	required = 5;
	
	if(round_number >= 10)
		required = 4;
	
	if(round_number >= 25)
		required = 3;
	
	// In trouble: a grenade on a smaller group is still worth it.
	if(self bot_health_fraction() < 0.5 && required > 3)
		required--;
	
	return required;
}

// Finds the densest group of zombies (250 unit blast radius) and returns the point to throw at.
bot_find_grenade_cluster()
{
	zombies = get_cached_zombies();
	
	if(!isdefined(zombies) || zombies.size == 0)
		return undefined;
	
	valid = [];
	
	foreach(zombie in zombies)
	{
		if(!isdefined(zombie) || !isalive(zombie))
			continue;
		
		if(self threat_should_ignore(zombie))
			continue;
		
		if(is_true(zombie.in_the_ground))
			continue;
		
		if(distancesquared(self.origin, zombie.origin) > 1000000)
			continue;
		
		valid[valid.size] = zombie;
	}
	
	required = self bot_get_grenade_required_cluster();
	
	if(valid.size < required)
		return undefined;
	
	radius_sq = 250 * 250;
	
	best_count = 0;
	best_index = -1;
	
	for(i = 0; i < valid.size; i++)
	{
		count = 0;
		
		for(j = 0; j < valid.size; j++)
		{
			if(distancesquared(valid[i].origin, valid[j].origin) <= radius_sq)
				count++;
		}
		
		if(count > best_count)
		{
			best_count = count;
			best_index = i;
		}
	}
	
	if(best_index < 0 || best_count < required)
		return undefined;
	
	center = valid[best_index].origin;
	
	sum = (0, 0, 0);
	
	members = 0;
	
	for(j = 0; j < valid.size; j++)
	{
		if(distancesquared(center, valid[j].origin) <= radius_sq)
		{
			sum += valid[j].origin;
			
			members++;
		}
	}
	
	if(members == 0)
		return undefined;
	
	target = sum * (1.0 / members);
	
	// Safe distance: never blow ourselves up.
	if(distancesquared(self.origin, target) < 90000)
		return undefined;
	
	// Needs a clear lob, otherwise the grenade bounces back at us.
	if(!sighttracepassed(self geteyeapprox(), target + (0, 0, 40), 0, self))
		return undefined;
	
	self.bot.grenade_cluster_count = best_count;
	
	return target;
}

bot_should_throw_grenade()
{
    if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
        return false;

    if(isdefined(level.round_number) && level.round_number < 2)
        return false;

    if(is_true(self.bot.is_buying) || is_true(self.bot.is_using_box) || is_true(self.bot.is_reviving) || is_true(self.bot.is_selfreviving))
        return false;

    if(self isreloading() || self isswitchingweapons() || self isthrowinggrenade())
        return false;

    threat = self.bot.threat.entity;

    if(!isdefined(threat) || !isalive(threat))
        return false;

    has_grenade = self getweaponammoclip("frag_grenade_zm") + self getweaponammostock("frag_grenade_zm");
	
    has_sticky_grenade = self getweaponammoclip("sticky_grenade_zm") + self getweaponammostock("sticky_grenade_zm");

    if(!has_grenade && !has_sticky_grenade)
        return false;

    if(isdefined(self.bot.next_grenade_throw) && gettime() < self.bot.next_grenade_throw)
        return false;

	// Don't stop shooting to throw a grenade when zombies are already on us.
	self bot_update_situation();
	
	if(self.bot.close_count >= 2)
		return false;

	target = self bot_find_grenade_cluster();
	
	if(!isdefined(target))
		return false;
	
	self.bot.grenade_target = target;
	
    return true;
}

bot_combat_throw_grenade()
{
    self endon("disconnect");
    self endon("death");

    if(is_true(self.bot.is_throwing_grenade))
        return;

    self.bot.is_throwing_grenade = true;

    round_number = 1;
	
	if(isdefined(level.round_number))
		round_number = level.round_number;
	
    self.bot.next_grenade_throw = gettime() + randomintrange(4000, 15000) + (round_number * 100);

    target = self.bot.threat.entity;
	
    weapon = undefined;

    if(self getweaponammoclip("frag_grenade_zm") + self getweaponammostock("frag_grenade_zm") > 0)
        weapon = "frag_grenade_zm";
    else if(self getweaponammoclip("sticky_grenade_zm") + self getweaponammostock("sticky_grenade_zm") > 0)
        weapon = "sticky_grenade_zm";

    if(isdefined(weapon) && isdefined(target) && isalive(target))
    {
        grenade_target = self.bot.grenade_target;
		
		if(!isdefined(grenade_target))
			grenade_target = self bot_get_grenade_cluster_center(target);

        // Never use a point that is dangerously close to the bot.
        if(distancesquared(self.origin, grenade_target) < 62500)
            grenade_target = target.origin;

        if(self throwgrenade(weapon, grenade_target))
        {
            end_time = gettime() + 2000;

            while(self isthrowinggrenade() && gettime() < end_time)
                wait 0.05;
        }
    }
	
	self.bot.grenade_target = undefined;

    self.bot.is_throwing_grenade = undefined;
}

bot_get_grenade_cluster_center(threat)
{
    if(!isdefined(threat) || !isdefined(threat.origin))
        return self.origin;

    zombies = get_cached_zombies();

    if(!isdefined(zombies) || zombies.size == 0)
        return threat.origin;

    sum_x = 0;
    sum_y = 0;
    sum_z = 0;
    count = 0;
    cluster_radius_sq = 250 * 250;

    foreach(zombie in zombies)
    {
        if(!isdefined(zombie) || !isalive(zombie) || self threat_should_ignore(zombie))
            continue;

        if(distancesquared(threat.origin, zombie.origin) > cluster_radius_sq)
            continue;

        sum_x += zombie.origin[0];
        sum_y += zombie.origin[1];
        sum_z += zombie.origin[2];
        count++;
    }

    if(count < 3)
        return threat.origin;

    return (sum_x / count, sum_y / count, sum_z / count);
}

// ---------------------------------------------------------------------------------------------
// Weapon helpers / aiming
// ---------------------------------------------------------------------------------------------

bot_should_hip_fire()
{
	enemy = self.bot.threat.entity;
	
	weapon = self getcurrentweapon();
	
	if(weapon == "none")
	{
		return 0;
	}
	
	if(weaponisdualwield(weapon))
	{
		return 1;
	}
	
	class = weaponclass(weapon);
	
	if(isplayer(enemy) && class == "spread")
	{
		return 1;
	}
	
	distsq = distancesquared(self.origin, enemy.origin);
	
	distcheck = 0;
	
	switch(class)
	{
		case "rocketlauncher":
			distcheck = 0;
			break;
		
		default:
		case "mg":
		case "rifle":
			distcheck = 200;
			break;
		
		case "spread":
			distcheck = 250;
			break;
		
		case "smg":
			distcheck = 400;
			break;
		
		case "pistol":
			distcheck = 300;
			break;
	}
	
	if(isweaponscopeoverlay(weapon))
	{
		distcheck = 400;
	}
	
	return distsq < (distcheck * distcheck);
}

// Max distance at which a weapon type is worth firing at a zombie.
bot_engagement_range(weapon)
{
	if(!isdefined(weapon) || weapon == "none")
		return 1500;
	
	if(self bot_is_splash_weapon(weapon))
		return 1200;
	
	class = weaponclass(weapon);
	
	if(class == "spread")
		return 650;
	
	if(class == "pistol")
		return 1000;
	
	if(class == "smg")
		return 1200;
	
	return 2200;
}

bot_lookat_entity(entity)
{
	if(isplayer(entity) && entity getstance() != "prone")
	{
		if(distancesquared(self.origin, entity.origin) < 65536)
		{
			origin = entity getcentroid() + vectorscale((0, 0, 1), 10);
			
			self lookat(origin);
			
			return;
		}
	}
	
	offset = target_getoffset(entity);
	
	if(isdefined(offset))
	{
		self lookat(entity.origin + offset);
	}
	else
	{
		self lookat(entity getcentroid());
	}
}

bot_combat_lookat(origin, frac)
{
    if(is_true(self.bot.is_objective_using))
        return;

    if(!isdefined(self.bot.threat.entity))
        return;

    self lookat(origin);
}

// Only normal zombies are known to have a j_head tag; everything else (dogs, bosses, ...) gets a body shot.
bot_can_headshot(ent)
{
	if(!isdefined(ent) || isplayer(ent))
		return false;
	
	if(!isdefined(ent.animname) || ent.animname != "zombie")
		return false;
	
	weapon = self getcurrentweapon();
	
	if(weapon == "none")
		return false;
	
	// Pellets spread and explosions don't care about heads.
	if(weaponclass(weapon) == "spread" || self bot_is_splash_weapon(weapon))
		return false;
	
	return true;
}

bot_update_aim(frames)
{
	ent = self.bot.threat.entity;

	if(!isdefined(ent.origin))
		return self.origin;

	dist = distance(self.origin, ent.origin);

	prediction = self predictposition(ent, frames);
	
	if(!self threat_is_player())
	{
		if(self bot_can_headshot(ent))
		{
			head = ent gettagorigin("j_head");
			
			if(isdefined(head))
			{
				head_height = head[2] - ent.origin[2];
				
				if(head_height < 15)
					head_height = 15;
				
				if(head_height > 80)
					head_height = 80;
				
				return prediction + (0, 0, head_height);
			}
		}
		
		centroid = ent getcentroid();
		
		height = centroid[2] - prediction[2];
		
		aim_offset = 0;
		
		if(dist < 300)
			aim_offset += 25;
		
		return prediction + (0, 0, height + aim_offset);
	}

	height = ent getplayerviewheight();
	
	return prediction + (0, 0, height);
}

bot_get_fire_radius(aim_point)
{
	dist = distance(self getplayercamerapos(), aim_point);

	radius = dist * 0.05;
	
	// Up close a hit anywhere on the body is fine.
	if(dist < 150)
		radius += 10;

	return clamp(radius, 18, 44);
}

bot_on_target(aim_target, radius)
{
	angles = self getplayerangles();
	
	forward = anglestoforward(angles);
	
	origin = self getplayercamerapos();
	
	len = distance(aim_target, origin);
	
	end = origin + (forward * len);
	
	if(distancesquared(aim_target, end) < (radius * radius))
	{
		return 1;
	}
	
	return 0;
}

bot_dot_product(origin)
{
	angles = self getplayerangles();
	
	forward = anglestoforward(angles);
	
	delta = origin - self getplayercamerapos();
	delta = vectornormalize(delta);
	
	dot = vectordot(forward, delta);
	
	return dot;
}

bot_can_do_combat()
{
	if(is_true(self.bot.is_objective_using))
		return 0;

	if(self ismantling() || self isonladder())
	{
		return 0;
	}
	
	if(is_true(self.bot.is_throwing_grenade) || is_true(self.bot.is_getting_shield) || is_true(self.bot.is_grabbing_box) || is_true(self.bot.is_reviving) || is_true(self.bot.is_selfreviving))
	{
		return 0;
	}
	
	return 1;
}

threat_is_player()
{
	ent = self.bot.threat.entity;
	
	if(isdefined(ent) && isplayer(ent))
	{
		return 1;
	}
	
	return 0;
}

bot_has_enemy()
{
	if(isdefined(self.bot.threat.entity))
	{
		return 1;
	}
	
	return 0;
}

// ---------------------------------------------------------------------------------------------
// Target selection
// ---------------------------------------------------------------------------------------------

bot_is_special_zombie(zombie)
{
	if(is_true(zombie.isscreecher) || is_true(zombie.is_brutus) || is_true(zombie.is_mechz) || is_true(zombie.is_avogadro))
		return true;
	
	return false;
}

bot_best_enemy()
{
    enemies = get_cached_zombies();

    if(!isdefined(enemies) || enemies.size == 0)
    {
        self bot_expire_stale_threat();
        return 0;
    }

    wallshoot_range = getdvarfloatdefault("bot_wallshoot_dist", 200);
    switch_margin = 250;
    revive_point = undefined;

    if(maps\mp\zombies\_zm_laststand::player_any_player_in_laststand())
        revive_point = self get_active_revive_point();

    weapon = self getcurrentweapon();
    splash = self bot_is_splash_weapon(weapon);
    max_range = self bot_engagement_range(weapon);

    current = self.bot.threat.entity;
    now = gettime();
    eye = self geteyeapprox();

    // ---- Step 1: keep only the nearest few candidates so we only pay for a few visibility traces.
    // Bosses are sorted as if they were closer so they never fall out of the candidate list.
    max_cand = 8;
    cand = [];
    cand_key = [];

    foreach(zombie in enemies)
    {
        if(!isdefined(zombie) || !isalive(zombie))
            continue;

        if(self threat_should_ignore(zombie))
            continue;

        if(is_true(zombie.in_the_ground))
            continue;

        dist = distance(self.origin, zombie.origin);

        if(dist > max_range)
            continue;

        key = dist;

        if(is_true(zombie.is_brutus) || is_true(zombie.is_mechz))
            key -= 400;

        pos = cand.size;

        for(i = 0; i < cand.size; i++)
        {
            if(key < cand_key[i])
            {
                pos = i;
                break;
            }
        }

        if(pos >= max_cand)
            continue;

        last = cand.size;

        if(last >= max_cand)
            last = max_cand - 1;

        for(j = last; j > pos; j--)
        {
            cand[j] = cand[j - 1];
            cand_key[j] = cand_key[j - 1];
        }

        cand[pos] = zombie;
        cand_key[pos] = key;
    }

    // Keep the current target in the list so hysteresis can work even if it's now slightly out of the top few.
    current_in_list = false;

    if(isdefined(current) && isalive(current))
    {
        for(i = 0; i < cand.size; i++)
        {
            if(cand[i] == current)
            {
                current_in_list = true;
                break;
            }
        }
    }

    if(!current_in_list && isdefined(current) && isalive(current) && !self threat_should_ignore(current) && distance(self.origin, current.origin) <= max_range)
        cand[cand.size] = current;

    // ---- Step 2: score them.
    current_score = undefined;
    current_visible = true;
    best = undefined;
    best_score = -999999999;
    best_visible = true;

    for(i = 0; i < cand.size; i++)
    {
        zombie = cand[i];

        if(!isdefined(zombie) || !isalive(zombie))
            continue;

        dist = distance(self.origin, zombie.origin);
        visible = true;

        // Very close threats are actionable without spending a trace on each one.
        if(dist > 100)
            // MP bot sight helper is unavailable in the Zombies script VM.
            visible = sighttracepassed(eye, zombie.origin + (0, 0, 32), 0, self);

        // Allow a very small wall-shoot buffer, but strongly prefer actual line of sight.
        if(!visible && dist > wallshoot_range)
            continue;

        score = 2500 - dist;

        if(visible)
            score += 250;
        else
            score -= 175;

        if(dist < 100)
            score += 650;
        else if(dist < 250)
            score += 300;

        // React to the zombie that just damaged this bot.
        if(isdefined(self.bot.attacker) && self.bot.attacker == zombie &&
           isdefined(self.bot.attacker_time) && now - self.bot.attacker_time < 2000)
            score += 550;

        // Zombies that are actively chasing this bot go first.
        if(isdefined(zombie.favoriteenemy) && zombie.favoriteenemy == self)
            score += 150;

        // Weak zombies die fast: removing them reduces incoming damage cheaply.
        if(isdefined(zombie.health) && zombie.health <= 150)
            score += 120;

        // Legless crawlers are slow, only worry about them when they are close.
        if(isdefined(zombie.has_legs) && !zombie.has_legs && dist > 200)
            score -= 150;

        // Special threats are more dangerous than ordinary zombies.
        if(is_true(zombie.isscreecher))
            score += 450;

        if(is_true(zombie.is_brutus) || is_true(zombie.is_mechz))
            score += 350;

        if(is_true(zombie.is_avogadro))
            score += 300;

        // Explosive weapons: prefer the zombie in the middle of a crowd.
        if(splash)
        {
            neighbours = 0;

            for(j = 0; j < cand.size; j++)
            {
                if(i != j && isdefined(cand[j]) && distancesquared(zombie.origin, cand[j].origin) < 22500)
                    neighbours++;
            }

            score += neighbours * 60;
        }

        if(isdefined(revive_point))
        {
            dist_to_downed = distance(zombie.origin, revive_point.origin);

            if(dist_to_downed < 400)
                score += 600;
            else if(dist_to_downed < 800)
                score += 250;
        }

        if(isdefined(current) && zombie == current)
        {
            current_score = score;
            current_visible = visible;
        }

        if(score > best_score)
        {
            best_score = score;
            best = zombie;
            best_visible = visible;
        }
    }

    if(!isdefined(best))
    {
        self bot_expire_stale_threat();
        return 0;
    }

    // Stick with a zombie that is already in our face and being shot.
    if(isdefined(current) && isalive(current) && distance(self.origin, current.origin) < 120)
        switch_margin = 400;

    // Hysteresis prevents the bot from endlessly swapping between equally close targets.
    if(isdefined(current_score) && best != current && (best_score - current_score) < switch_margin)
    {
        best = current;
        best_visible = current_visible;
    }

    if(!isdefined(current) || best != current)
        self.bot.threat.time_first_sight = now;

    self.bot.threat.entity = best;
    self.bot.threat.time_recent_sight = now;
    self.bot.threat.dot = self bot_dot_product(best.origin);
    self.bot.threat.position = best.origin;
    self.bot.threat.visible = best_visible;

    return 1;
}

bot_expire_stale_threat()
{
    if(!isdefined(self.bot.threat.entity))
        return;
    
    memory_window = 800;
    
    if(isdefined(self.bot.threat.time_recent_sight) && gettime() - self.bot.threat.time_recent_sight <= memory_window)
        return;
    
    self bot_clear_enemy();
}

threat_should_ignore(entity)
{
	if(is_true(self.bot.is_getting_shield))
	{
		return 1;
	}
	
    if(is_true(entity.is_avogadro) && isdefined(entity.state))
    {
        if(entity.state == "cloud" || entity.state == "exiting" || entity.state == "phasing")
            return 1;
    }

    return 0;
}

bot_combat_dead(damage)
{
	// Retarget immediately instead of freezing for a third of a second.
	self allowattack(0);
	
	self bot_clear_enemy();
}

bot_clear_enemy()
{
	self clearlookat();
	
	self.bot.threat.entity = undefined;
	self.bot.threat.visible = undefined;
}

threat_dead()
{
	if(self bot_has_enemy())
	{
		ent = self.bot.threat.entity;
		
		if(!isalive(ent))
		{
			return 1;
		}
		
		return 0;
	}
	
	return 0;
}