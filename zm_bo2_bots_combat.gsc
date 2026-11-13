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

	SMART COMBAT v2 (this revision)
	  - Combat has its own 150ms zombie scan (the shared cache is 1000ms old, which means bots were shooting
	    at positions zombies left a second ago and not noticing new ones).
	  - Kiting: with 1-3 slow zombies close and a decent gun, the bot backs away to a nearby node while it keeps
	    shooting, instead of standing still and trading hits. Not used against sprinters/dogs, shotguns, insta-kill.
	  - Damage-rate awareness: damage taken over the last couple of seconds feeds the danger value, so a bot
	    that is bleeding fast leaves earlier than one that is simply near zombies.
	  - Danger weighting: sprinters/dogs count more, crawlers and zombies chasing someone else count less,
	    nearby teammates reduce the danger, no ammo anywhere makes the bot far more cautious,
	    insta-kill makes it bolder.
	  - Targeting: dogs and sprinters first, zombies hitting a hurt teammate first, small bonus for targets
	    already in front of the crosshair (faster kill).
	  - Weapon swap by range: swaps to a clearly better weapon for the current distance (SMG/shotgun close,
	    rifle far) when nothing is touching the bot.
	  - Phd Flopper / flak jacket: splash weapons are no longer treated as self-damage.

	All original function names are kept so the main script and map scripts keep working.
*/

bot_combat_think(damage, attacker, direction)
{
	// Objective movement remains locked, but quest workers must still react to
	// nearby zombies, update danger, and choose an emergency flee route.
	// bot_combat_lookat() preserves any aim required by the active interaction.
	if(is_true(self.bot.is_objective_using))
		self bot_combat_clear_movement();

	if(!bot_can_do_combat())
	{
		self allowattack(0);
		self pressads(0);
		self bot_combat_clear_movement();
		return;
	}
	
	if(self atgoal("flee"))
		self cancelgoal("flee");
	
	// Combat orbit is a temporary survival override. The wander controller
	// pauses while a "combat" goal exists, then resumes stay/follow afterwards.
	// Do not clear the orbit every 100ms just because a command mode is active.
	
	self bot_track_damage(damage);
	self bot_update_situation();

	// A bot must not die trying to revive someone. Abort only under immediate
	// danger; otherwise it completes the revive normally.
	if(is_true(self.bot.is_reviving) && self bot_should_abort_revive())
		self bot_abort_revive();
	
	if(!self hasgoal("flee") && !self bot_flee_blocked() && self bot_should_flee(damage))
	{
		now = gettime();
		
		if(!isdefined(self.bot.next_flee_scan) || now > self.bot.next_flee_scan)
		{
			// Re-evaluate escape routes quickly when pressure is high. The old
			// multi-second delay could leave a surrounded bot stationary too long.
			if(self.bot.danger >= 8)
				self.bot.next_flee_scan = now + 250;
			else if(self.bot.danger >= 5)
				self.bot.next_flee_scan = now + 450;
			else if(get_players().size > 4)
				self.bot.next_flee_scan = now + 1000;
			else
				self.bot.next_flee_scan = now + 750;
			
			self bot_flee_goal();
		}
	}
	
	// Not in flee territory yet, but a zombie is in my face: back up while shooting.
	if(!self hasgoal("flee") && !self bot_flee_blocked() && self bot_should_kite())
		self bot_flee_goal(true);

	// These actions keep their own input/aim, but emergency threat tracking and
	// fleeing above remain active while the animation or interaction is running.
	if(is_true(self.bot.is_getting_shield) || is_true(self.bot.is_throwing_grenade) ||
	   is_true(self.bot.is_reviving))
	{
		self allowattack(0);
		self pressads(0);
		return;
	}
	
	if(self getcurrentweapon() == "none")
	{
		self allowattack(0);
		self pressads(0);
		return;
	}
	
	sight = self bot_best_enemy();
	
	if(!sight && !self bot_has_enemy())
	{
		self bot_combat_clear_movement();
		self allowattack(0);
		self pressads(0);
		
		return;
	}
	
	if(!isdefined(self.bot.threat.entity))
	{
		self allowattack(0);
		self pressads(0);
		self bot_combat_clear_movement();
		return;
	}
	
	if(self threat_dead())
	{
		self allowattack(0);
		self bot_combat_clear_movement();
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

bot_get_zombies()
{
	// Combat needs fresher data than the 1000ms shared cache. One scan per 150ms is shared by every bot.
	now = gettime();
	
	if(!isdefined(level.bot_combat_zombies) || !isdefined(level.bot_combat_zombies_time) || (now - level.bot_combat_zombies_time) >= 150)
	{
		level.bot_combat_zombies = getaispeciesarray(level.zombie_team, "all");
		level.bot_combat_zombies_time = now;
	}
	
	return level.bot_combat_zombies;
}

bot_is_dog(zombie)
{
	if(isdefined(zombie.animname) && zombie.animname == "zombie_dog")
		return true;
	
	return false;
}

bot_is_sprinter(zombie)
{
	if(isdefined(zombie.zombie_move_speed) && (zombie.zombie_move_speed == "sprint" || zombie.zombie_move_speed == "super_sprint"))
		return true;
	
	return false;
}

bot_insta_kill_active()
{
	if(isdefined(level.zombie_vars) && isdefined(self.team) && isdefined(level.zombie_vars[self.team]) && isdefined(level.zombie_vars[self.team]["zombie_powerup_insta_kill_on"]))
		return is_true(level.zombie_vars[self.team]["zombie_powerup_insta_kill_on"]);
	
	return false;
}

// Splash weapons only hurt the bot when it doesn't have Phd Flopper.
bot_splash_hurts_me(weapon)
{
	if(!self bot_is_splash_weapon(weapon))
		return false;
	
	if(self hasperk("specialty_flakjacket"))
		return false;
	
	return true;
}

// Exponentially decaying "damage taken recently" value (hp). Decays 60hp per second.
bot_track_damage(damage)
{
	now = gettime();
	
	if(!isdefined(self.bot.dmg_recent) || !isdefined(self.bot.dmg_time))
	{
		self.bot.dmg_recent = 0;
		self.bot.dmg_time = now;
	}
	
	dt = (now - self.bot.dmg_time) / 1000;
	
	self.bot.dmg_recent -= dt * 60;
	
	if(self.bot.dmg_recent < 0)
		self.bot.dmg_recent = 0;
	
	self.bot.dmg_time = now;
	
	if(isdefined(damage) && damage > 0)
		self.bot.dmg_recent += damage;
}

bot_total_ammo_empty()
{
	primaries = self getweaponslistprimaries();
	
	if(!isdefined(primaries) || primaries.size == 0)
		return true;
	
	foreach(weapon in primaries)
	{
		if(self getweaponammoclip(weapon) + self getweaponammostock(weapon) > 0)
			return false;
	}
	
	return true;
}

bot_get_hurt_allies()
{
	result = [];
	
	foreach(player in get_players())
	{
		if(!isdefined(player) || player == self || !isalive(player))
			continue;
		
		if(player.sessionstate != "playing")
			continue;
		
		// Downed players are handled by the revive logic in target scoring.
		if(player maps\mp\zombies\_zm_laststand::player_is_in_laststand())
			continue;
		
		maxhp = player.maxhealth;
		
		if(!isdefined(maxhp) || maxhp <= 0)
			maxhp = 100;
		
		if((player.health / maxhp) > 0.5)
			continue;
		
		result[result.size] = player.origin;
	}
	
	return result;
}

bot_update_situation()
{
	now = gettime();
	
	if(isdefined(self.bot.sit_time) && (now - self.bot.sit_time) < 100)
		return;
	
	self.bot.sit_time = now;
	self.bot.close_count = 0;
	self.bot.near_count = 0;
	self.bot.fast_close = 0;
	self.bot.allies_near = 0;
	self.bot.nearest_dist = 99999;
	self.bot.nearest_boss = undefined;
	self.bot.nearest_boss_dist = 99999;
	self.bot.danger = 0;
	self.bot.boss_near = false;
	
	zombies = bot_get_zombies();
	
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

		// Bosses threaten us from farther away than ordinary zombies. In particular,
		// Origins Panzer's claw can reach from roughly 300-1000 units.
		if(is_true(zombie.is_brutus) || is_true(zombie.is_mechz))
		{
			if(d <= 3240000)
			{
				dist = sqrt(d);

				if(dist < self.bot.nearest_boss_dist)
				{
					self.bot.nearest_boss = zombie;
					self.bot.nearest_boss_dist = dist;
				}

				if(is_true(zombie.is_mechz) && dist < 1100)
				{
					self.bot.boss_near = true;
					danger += 10;

					if(dist < 600)
						danger += 3;
				}
				else if(is_true(zombie.is_brutus) && dist < 650)
				{
					self.bot.boss_near = true;
					danger += 10;

					if(dist < 300)
						danger += 2;
				}
			}
		}

		if(d > 202500)
			continue;

		dist = sqrt(d);

		if(dist < self.bot.nearest_dist)
			self.bot.nearest_dist = dist;
		
		if(d > 90000)
			continue;
		
		self.bot.near_count++;
		
		// How scary is this particular zombie?
		weight = 1.0;
		
		if(self bot_is_dog(zombie))
			weight = 1.4;
		else if(self bot_is_sprinter(zombie))
			weight = 1.25;
		
		if(isdefined(zombie.has_legs) && !zombie.has_legs)
			weight *= 0.6;
		
		if(isdefined(zombie.favoriteenemy) && zombie.favoriteenemy != self)
			weight *= 0.7;
		
		if(d < 4900)
			danger += 3 * weight;
		else if(d < 16900)
			danger += 2 * weight;
		else if(d < 40000)
			danger += 1 * weight;
		else
			danger += 0.4 * weight;
		
		if(d < 16900)
		{
			self.bot.close_count++;
			
			if(self bot_is_dog(zombie) || self bot_is_sprinter(zombie))
				self.bot.fast_close++;
		}
	}
	
	// Teammates close by split the pressure and help kill things: up to 30% less danger.
	foreach(player in get_players())
	{
		if(!isdefined(player) || player == self || !isalive(player))
			continue;
		
		if(player.sessionstate != "playing")
			continue;
		
		if(distancesquared(self.origin, player.origin) < 360000)
			self.bot.allies_near++;
	}
	
	ally_factor = self.bot.allies_near * 0.1;
	
	if(ally_factor > 0.3)
		ally_factor = 0.3;
	
	self.bot.danger = danger * (1.0 - ally_factor);
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

	maxhp = self.maxhealth;
	if(!isdefined(maxhp) || maxhp <= 0)
		maxhp = 100;

	// Absolute emergency rules: never try to orbit while a fast attacker is
	// already on top of us, or while a low-health bot is being crowded.
	if(isdefined(self.bot.nearest_dist) && self.bot.nearest_dist <= 165)
		return true;

	if(isdefined(self.bot.fast_close) && self.bot.fast_close > 0 &&
	   isdefined(self.bot.nearest_dist) && self.bot.nearest_dist <= 360)
		return true;

	if(isdefined(self.bot.close_count) && self.bot.close_count >= 4)
		return true;

	if(hp <= 0.42 && isdefined(self.bot.nearest_dist) && self.bot.nearest_dist < 520)
		return true;

	if(hp <= 0.55 && isdefined(self.bot.close_count) && self.bot.close_count >= 2)
		return true;

	// With no usable ammunition, do not circle a horde hoping to reload later.
	if(self bot_total_ammo_empty() && isdefined(self.bot.near_count) && self.bot.near_count > 0)
		return true;

	// A sudden burst of damage is an emergency even if only one zombie is visible.
	if(isdefined(self.bot.dmg_recent) && self.bot.dmg_recent >= maxhp * 0.18 &&
	   isdefined(self.bot.nearest_dist) && self.bot.nearest_dist < 425)
		return true;

	// Survival takes priority over holding ground: react before the bot is
	// already one or two hits from being downed.
	threshold = 4.0 - ((1.0 - hp) * 3.2);

	if(self bot_weapon_is_weak())
		threshold -= 1.0;

	// No usable ammo means avoiding contact is more valuable than fighting.
	if(self bot_total_ammo_empty())
		threshold -= 2.0;

	// Insta-kill makes fighting safer, but does not override point-blank danger.
	if(self bot_insta_kill_active())
		threshold += 1.25;

	if(threshold < 0.9)
		threshold = 0.9;

	danger = self.bot.danger;

	if(isdefined(damage))
		danger += 1.0;

	if(isdefined(self.bot.dmg_recent) && self.bot.dmg_recent > 0)
		danger += (self.bot.dmg_recent / maxhp) * 7.0;

	return danger >= threshold;
}

// Back up a few steps while shooting. Only worth it against slow zombies, with a gun that works at range.
bot_should_kite()
{
	now = gettime();
	
	if(isdefined(self.bot.next_kite) && now < self.bot.next_kite)
		return false;
	
	if(!isdefined(self.bot.close_count) || self.bot.close_count < 1 || self.bot.close_count > 3)
		return false;
	
	if(self.bot.nearest_dist > 190)
		return false;
	
	// Sprinters and dogs outrun us, backing up only wastes shots.
	if(self.bot.fast_close > 0)
		return false;
	
	if(!self isonground() || self ismantling() || self isonladder())
		return false;
	
	if(is_true(self.bot.is_meleeing) || is_true(self.bot.is_throwing_grenade))
		return false;
	
	if(self bot_insta_kill_active())
		return false;
	
	weapon = self getcurrentweapon();
	
	if(weapon == "none" || self bot_weapon_is_weak())
		return false;
	
	// Shotguns want zombies up close.
	if(weaponclass(weapon) == "spread")
		return false;
	
	// Kiting only buys time when there's someone to help or a reason to. Don't do it when alone against one zombie
	// that the gun kills in a second anyway.
	if(self.bot.close_count == 1 && self bot_health_fraction() > 0.8 && self.bot.allies_near == 0)
		return false;
	
	self.bot.next_kite = now + 2500;
	
	return true;
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

bot_should_abort_revive()
{
	hp = self bot_health_fraction();
	maxhp = self.maxhealth;
	if(!isdefined(maxhp) || maxhp <= 0)
		maxhp = 100;

	// Break a revive before it becomes a guaranteed trade: point-blank threats,
	// a fast attacker, a crowd, or serious damage while zombies are close.
	if(isdefined(self.bot.nearest_dist) && self.bot.nearest_dist <= 120)
		return true;

	if(isdefined(self.bot.fast_close) && self.bot.fast_close > 0 &&
	   isdefined(self.bot.nearest_dist) && self.bot.nearest_dist <= 220)
		return true;

	if(isdefined(self.bot.close_count) && self.bot.close_count >= 4)
		return true;

	if(hp <= 0.40 && isdefined(self.bot.nearest_dist) &&
	   self.bot.nearest_dist <= 360)
		return true;

	if(isdefined(self.bot.dmg_recent) && self.bot.dmg_recent >= maxhp * 0.24 &&
	   isdefined(self.bot.nearest_dist) && self.bot.nearest_dist <= 360)
		return true;

	return false;
}

bot_abort_revive()
{
	teammate = self.bot.revive_target;

	if(isdefined(teammate))
	{
		teammate.being_revived = false;
		self.bot.revive_abort_target = teammate;
		self.bot.revive_abort_until = gettime() + 4000;
	}

	self.bot.is_reviving = false;
	self.bot.revive_target = undefined;
	self.bot.revive_last_dist = undefined;
	self.bot.revive_claim_blocked_until = gettime() + 1500;

	self cancelgoal("revive");
	self notify("bot_revive_abort");
	self clearlookat();
}

// ---------------------------------------------------------------------------------------------
// Fleeing
// ---------------------------------------------------------------------------------------------

bot_get_flee_goal(max_dist)
{
    candidate = [];

    zombies = bot_get_zombies();

    if(!isdefined(zombies))
        return candidate;

    max_dist_sq = max_dist * max_dist;

    foreach(zombie in zombies)
    {
        if(!isdefined(zombie) || !isalive(zombie) || is_true(zombie.in_the_ground))
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

bot_flee_goal(kite)
{
    // Escape movement has priority over the optional combat orbit.
    self bot_combat_clear_movement();

    nearest = bot_nearest_node(self.origin);

    if(!isdefined(nearest))
        return;

    if(isdefined(kite))
        nodes = getnodesinradiussorted(self.origin, 650, 220, 256);
    else
        nodes = getnodesinradiussorted(self.origin, 1024, 640, 512);

    if(!isdefined(nodes) || nodes.size == 0)
        return;

    if(isdefined(kite))
        zombies = self bot_get_flee_goal(900);
    else
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

    // If a boss is actively threatening us, choose flee nodes relative to it,
    // even when a regular zombie happens to be a few units closer.
    if(isdefined(self.bot.nearest_boss) && isalive(self.bot.nearest_boss))
    {
        boss = self.bot.nearest_boss;
        boss_dist_sq = distancesquared(self.origin, boss.origin);

        if((is_true(boss.is_mechz) && boss_dist_sq < 1210000) ||
           (is_true(boss.is_brutus) && boss_dist_sq < 422500))
            threat_pos = boss.origin;
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
    start_pass = 0;

    // Kiting doesn't need to break line of sight, it just needs room to back up.
    if(isdefined(kite))
        start_pass = 1;

    for(pass = start_pass; pass < 2 && cand_nodes.size == 0; pass++)
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

            if(visible && !isdefined(kite))
                score += 120;

            cand_nodes[cand_nodes.size] = node;
			
            cand_scores[cand_scores.size] = score;
        }
    }

    max_score = 400;
    max_checks = 5;

    // When surrounded or badly hurt, accept a wider range of safe escape
    // nodes. The node scorer still rejects destinations/paths that cut through
    // a zombie, so this avoids freezing merely because every route is costly.
    if(!isdefined(kite))
    {
        if(self.bot.danger >= 8 || self bot_health_fraction() <= 0.35)
        {
            max_score = 1400;
            max_checks = 8;
        }
        else if(self.bot.danger >= 5 || self bot_health_fraction() <= 0.55)
        {
            max_score = 850;
            max_checks = 6;
        }
    }

    if(isdefined(kite))
    {
        max_score = 300;
        max_checks = 3;
    }

    path_checks = 0;

    while(path_checks < max_checks && cand_nodes.size > 0)
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

            // bot_reset_flee_goal() drops flee goals older than 8s: backdate kite goals so they only live ~1.5s.
            if(isdefined(kite))
                self.bot.flee_goal_time = gettime() - 6500;

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

	objective_lock = is_true(self.bot.is_objective_using);

	// Melee, grenades, and weapon swaps can interrupt a scripted quest action
	// or replace the weapon it needs. Keep those disabled during the interaction.
	if(!objective_lock && self bot_should_melee())
	{
		self bot_combat_clear_movement();

		if(!is_true(self.bot.is_meleeing))
			self thread bot_combat_melee();
		
		return;
	}
	
    if(!objective_lock && self bot_should_throw_grenade())
    {
		self bot_combat_clear_movement();

		if(!is_true(self.bot.is_throwing_grenade))
			self thread bot_combat_throw_grenade();
        
        return;
    }
	
	weapon = self getcurrentweapon();
	
	// Never stand around with an empty / dangerous weapon when a better one is in the holster.
	if(!objective_lock && self bot_combat_try_weapon_swap(weapon))
		return;
	
	if(self isswitchingweapons())
	{
		self allowattack(0);
		self pressads(0);
		return;
	}

	// Move after melee, grenades and weapon swaps have yielded control.
	self bot_combat_update_movement();
	
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
		self allowattack(0);
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
	
	aim_due = false;

	if(!isdefined(self.bot.threat.time_aim_correct) ||
	   self.bot.threat.time_aim_correct <= 0 ||
	   time >= self.bot.threat.time_aim_correct)
		aim_due = true;

	// Re-aim early only after a meaningful target displacement, and never
	// more than once per 250ms. This filters skeletal/velocity micro-jitter.
	if(!aim_due && isdefined(self.bot.threat.position) &&
	   distancesquared(self.bot.threat.entity.origin, self.bot.threat.position) > 900 &&
	   (!isdefined(self.bot.threat.time_last_aim_update) ||
	    time - self.bot.threat.time_last_aim_update >= 250))
		aim_due = true;

	if(aim_due)
	{
		tdist = distance(self.origin, self.bot.threat.entity.origin);
		self.bot.threat.time_aim_interval = 350;

		if(tdist < 250)
			self.bot.threat.time_aim_interval = 275;
		else if(tdist > 800)
			self.bot.threat.time_aim_interval = 450;

		self.bot.threat.time_aim_correct = time + self.bot.threat.time_aim_interval;
		self.bot.threat.time_last_aim_update = time;

		frac = (time - self.bot.threat.time_first_sight) / 50;
		frac = clamp(frac, 0, 1);

		if(!self threat_is_player())
			frac = 1;

		// Predict less aggressively for zombies: their pathing/animation
		// velocity can change every frame and over-leading causes aim snapping.
		frames = 3;

		if(tdist < 300)
			frames = 2;
		else if(tdist > 800)
			frames = 4;

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
	
	fire_safe = self bot_can_fire_safely(weapon);
	on_target = self bot_on_target(aim_point, self bot_get_fire_radius(aim_point));

	if(!on_target && isdefined(self.bot.threat.entity) &&
	   isalive(self.bot.threat.entity))
		on_target = self bot_on_target(self.bot.threat.entity.origin, 80);

	if(fire_safe && on_target)
	{
		self.bot.threat.fire_until = gettime() + 180;
		self allowattack(1);
	}
	else if(fire_safe &&
	        isdefined(self.bot.threat.fire_until) &&
	        gettime() < self.bot.threat.fire_until)
	{
		// Avoid dropping the attack permission for a single noisy aim sample.
		self allowattack(1);
	}
	else
	{
		self.bot.threat.fire_until = 0;
		self allowattack(0);
	}
	
	if(is_true(self.stingerlockstarted))
	{
		self allowattack(self.stingerlockfinalized);
		
		return;
	}
}

// ---------------------------------------------------------------------------------------------
// Combat movement: controlled orbiting and collision-aware repositioning
// ---------------------------------------------------------------------------------------------

bot_combat_clear_movement()
{
	if(self getgoal("combat") || self hasgoal("combat"))
		self cancelgoal("combat");

	self.bot.combat_orbit_target = undefined;
	self.bot.next_combat_move = 0;
}

bot_combat_update_movement()
{
	now = gettime();
	threat = self.bot.threat.entity;

	if(!isdefined(threat) || !isalive(threat))
	{
		self bot_combat_clear_movement();
		return;
	}

	// Map objectives, build/craft interactions, revives, generator defense and
	// scripted traversal own movement. Stay/follow only applies when there is
	// no active combat waypoint; combat orbit temporarily takes priority.
	if(is_true(self.bot.is_objective_using) ||
	   is_true(self.bot.is_holding_generator) ||
	   is_true(self.bot.is_origins_soul_holding) ||
	   is_true(self.bot.is_parkouring) ||
	   is_true(self.bot.is_building) ||
	   is_true(self.bot.is_crafting) ||
	   is_true(self.bot.is_perk_buying) ||
	   is_true(self.bot.is_buying) ||
	   is_true(self.bot.is_using_box) ||
	   is_true(self.bot.is_grabbing_box) ||
	   is_true(self.bot.is_reviving) ||
	   is_true(self.bot.is_selfreviving) ||
	   is_true(self.bot.is_getting_shield) ||
	   is_true(self.bot.is_throwing_grenade) ||
	   self maps\mp\zombies\_zm_laststand::player_is_in_laststand() ||
	   !self isonground() || self ismantling() || self isonladder())
	{
		self bot_combat_clear_movement();
		return;
	}

	// Do not circle when a higher-priority escape route or interaction is active.
	if(self getgoal("flee") || self hasgoal("flee") ||
	   self getgoal("revive") || self hasgoal("revive") ||
	   self getgoal("selfrevive") || self hasgoal("selfrevive") ||
	   self getgoal("boxbuy") || self hasgoal("boxbuy") ||
	   self getgoal("weaponbuy") || self hasgoal("weaponbuy") ||
	   self getgoal("pap") || self hasgoal("pap") ||
	   self getgoal("perkbuy") || self hasgoal("perkbuy") ||
	   self getgoal("powerup") || self hasgoal("powerup") ||
	   self getgoal("bot_origins_robot_enter") || self hasgoal("bot_origins_robot_enter") ||
	   self getgoal("bot_mob_final_fight_chase") || self hasgoal("bot_mob_final_fight_chase") ||
	   self getgoal("bot_die_rise_tower_leg") || self hasgoal("bot_die_rise_tower_leg") ||
	   self getgoal("bot_die_rise_elevator") || self hasgoal("bot_die_rise_elevator") ||
	   self getgoal("bot_die_rise_springpad") || self hasgoal("bot_die_rise_springpad") ||
	   self getgoal("bot_buried_roof_jump_takeoff") || self hasgoal("bot_buried_roof_jump_takeoff") ||
	   self getgoal("bot_buried_roof_jump_landing") || self hasgoal("bot_buried_roof_jump_landing") ||
	   self getgoal("bot_buried_springpad") || self hasgoal("bot_buried_springpad") ||
	   self getgoal("bot_buried_springpad_landing") || self hasgoal("bot_buried_springpad_landing") ||
	   self getgoal("bot_buried_springpad_target") || self hasgoal("bot_buried_springpad_target"))
	{
		self bot_combat_clear_movement();
		return;
	}

	// Boss encounters use the dedicated danger/flee logic instead of trying
	// to orbit a boss whose attacks can punish a close circular route.
	if(is_true(threat.is_mechz) || is_true(threat.is_brutus))
	{
		self bot_combat_clear_movement();
		return;
	}

	target_dist = distance2d(self.origin, threat.origin);

	// Combat orbit is a close-to-midrange behavior, not a replacement for
	// normal wandering or long-range target acquisition.
	if(target_dist > 680 ||
	   (!is_true(self.bot.threat.visible) && target_dist > 260) ||
	   (isdefined(self.bot.near_count) && self.bot.near_count == 0 && target_dist > 420))
	{
		self bot_combat_clear_movement();
		return;
	}

	if(is_true(self.bot.is_meleeing))
	{
		self bot_combat_clear_movement();
		return;
	}

	// Randomize orbit direction once per target so the whole squad does not
	// follow the same circular lane.
	if(!isdefined(self.bot.combat_orbit_target) || self.bot.combat_orbit_target != threat)
	{
		self.bot.combat_orbit_target = threat;
		self.bot.combat_orbit_sign = randomfloatrange(0, 2) < 1 ? -1 : 1;
		self.bot.next_combat_move = 0;
	}

	if(isdefined(self.bot.next_combat_move) && now < self.bot.next_combat_move)
		return;

	self.bot.next_combat_move = now + 850;

	weapon = self getcurrentweapon();
	desired_radius = 410;

	if(weapon != "none" && weaponclass(weapon) == "spread")
		desired_radius = 285;
	else if(weapon != "none" && weaponclass(weapon) == "pistol")
		desired_radius = 360;

	// Give damaged or surrounded bots more room; keep a shotgun inside useful range.
	if(self bot_health_fraction() < 0.55 || self.bot.danger >= 5)
		desired_radius += 75;

	if(self bot_insta_kill_active())
		desired_radius -= 45;

	if(desired_radius < 245)
		desired_radius = 245;
	if(desired_radius > 520)
		desired_radius = 520;

	best_node = self bot_combat_find_orbit_node(threat, desired_radius, self.bot.combat_orbit_sign);

	// If the desired side of the orbit has no reachable nodes, reverse direction
	// rather than standing still or trying to cut directly through the horde.
	if(!isdefined(best_node))
	{
		self.bot.combat_orbit_sign = 0 - self.bot.combat_orbit_sign;
		best_node = self bot_combat_find_orbit_node(threat, desired_radius, self.bot.combat_orbit_sign);
	}

	if(!isdefined(best_node))
	{
		if(self getgoal("combat") || self hasgoal("combat"))
			self cancelgoal("combat");
		return;
	}

	current_goal = self getgoal("combat");
	current_goal_valid = false;

	// Do not cancel and recreate a route just because another nearby node
	// scored a little better on the next scan. Keep the current waypoint until
	// it is reached, becomes unsafe, leaves the engagement band, or is blocked.
	if(isdefined(current_goal))
	{
		current_goal_remaining = distance2d(self.origin, current_goal);
		current_goal_target_gap = distance2d(current_goal, threat.origin);
		current_goal_safe = true;
		zombies = self bot_get_zombies();

		foreach(zombie in zombies)
		{
			if(!isdefined(zombie) || !isalive(zombie) ||
			   is_true(zombie.in_the_ground) || !isdefined(zombie.origin))
				continue;

			if(distance2d(zombie.origin, current_goal) < 145)
			{
				current_goal_safe = false;
				break;
			}
		}

		if(current_goal_remaining > 105 &&
		   current_goal_target_gap >= 190 &&
		   current_goal_target_gap <= desired_radius + 340 &&
		   current_goal_safe &&
		   findpath(self.origin, current_goal, undefined, 0, 1))
			current_goal_valid = true;
	}

	if(!isdefined(current_goal) || !current_goal_valid ||
	   distancesquared(current_goal, best_node.origin) > 3600)
	{
		if(self getgoal("combat") || self hasgoal("combat"))
			self cancelgoal("combat");

		// The combat goal has wander-level priority. Flee, revive and map
		// objective goals remain more important and are never replaced here.
		self addgoal(best_node.origin, 52, 1, "combat");
	}
}

bot_combat_find_orbit_node(threat, desired_radius, orbit_sign)
{
	if(!isdefined(threat) || !isdefined(threat.origin))
		return undefined;

	nearest = bot_nearest_node(self.origin);
	if(!isdefined(nearest))
		return undefined;

	nodes = getnodesinradiussorted(self.origin, 760, 110, 320);
	if(!isdefined(nodes) || nodes.size == 0)
		return undefined;

	radial_vec = (self.origin[0] - threat.origin[0], self.origin[1] - threat.origin[1], 0);
	if(distance2d(self.origin, threat.origin) < 1)
		return undefined;

	radial = vectornormalize(radial_vec);
	tangent = (-radial[1] * orbit_sign, radial[0] * orbit_sign, 0);
	zombies = self bot_get_zombies();

	candidate_nodes = [];
	candidate_scores = [];

	foreach(node in nodes)
	{
		if(!isdefined(node) || !isdefined(node.origin))
			continue;

		move_dist = distance2d(self.origin, node.origin);
		if(move_dist < 95 || move_dist > 740)
			continue;

		target_gap = distance2d(node.origin, threat.origin);
		if(target_gap < 190 || target_gap > desired_radius + 340)
			continue;

		node_radial_vec = (node.origin[0] - threat.origin[0], node.origin[1] - threat.origin[1], 0);
		node_radial = vectornormalize(node_radial_vec);
		side_progress = vectordot(node_radial, tangent);

		// Prefer the next safe point along the tangent, but permit a less ideal
		// point if geometry or pathing blocks the preferred side.
		score = move_dist * 0.18;
		score += abs(target_gap - desired_radius) * 0.85;
		score -= side_progress * 230;

		if(side_progress < -0.2)
			score += 260;

		route_vec = (node.origin[0] - self.origin[0], node.origin[1] - self.origin[1], 0);
		route_dir = vectornormalize(route_vec);
		unsafe = false;

		foreach(zombie in zombies)
		{
			if(!isdefined(zombie) || !isalive(zombie) || !isdefined(zombie.origin) ||
			   is_true(zombie.in_the_ground))
				continue;

			node_gap = distance2d(zombie.origin, node.origin);

			// Never select a node inside the immediate melee radius of any zombie.
			if(node_gap < 145)
			{
				unsafe = true;
				break;
			}

			if(node_gap < 260)
				score += (260 - node_gap) * 1.1;

			// Reject routes that pass directly through another zombie's body.
			zombie_vec = (zombie.origin[0] - self.origin[0], zombie.origin[1] - self.origin[1], 0);
			along = vectordot(route_dir, zombie_vec);

			if(along > 45 && along < move_dist - 35)
			{
				zombie_dist = distance2d(self.origin, zombie.origin);
				lateral_sq = zombie_dist * zombie_dist - along * along;

				if(lateral_sq < 0)
					lateral_sq = 0;

				lateral = sqrt(lateral_sq);

				if(lateral < 92)
				{
					unsafe = true;
					break;
				}

				if(lateral < 210)
					score += (210 - lateral) * 0.45;
			}
		}

		if(unsafe)
			continue;

		candidate_nodes[candidate_nodes.size] = node;
		candidate_scores[candidate_scores.size] = score;
	}

	// Path-check only the five best scored candidates to keep the 10 Hz combat
	// loop inexpensive even on high-round zombie counts.
	path_checks = 0;

	while(path_checks < 5 && candidate_nodes.size > 0)
	{
		best = 0;
		for(i = 1; i < candidate_nodes.size; i++)
		{
			if(candidate_scores[i] < candidate_scores[best])
				best = i;
		}

		if(candidate_scores[best] > 900)
			return undefined;

		best_node = candidate_nodes[best];
		candidate_scores[best] = 99999;
		path_checks++;

		if(findpath(self.origin, best_node.origin, undefined, 0, 1))
			return best_node;
	}

	return undefined;
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
	if(self bot_splash_hurts_me(weapon) && dist < 130)
		return false;
	
	// No line of sight = don't burn ammo into a wall, unless the zombie is basically touching us.
	if(isdefined(self.bot.threat.visible) && !self.bot.threat.visible && dist > 320)
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
	
	self.bot.last_swap_score = best_score;
	
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
	else if(self bot_splash_hurts_me(weapon) && dist < 130)
	{
		new_weapon = self bot_get_swap_weapon(weapon, true, true, dist);
	}
	// 3) Empty / nearly empty magazine while zombies are close: a loaded gun beats a reload animation.
	else if((clip <= 0 || (self isreloading() && max > 0 && clip < (max * 0.25))) && (dist < 260 || self.bot.close_count > 0))
	{
		new_weapon = self bot_get_swap_weapon(weapon, true, self.bot.close_count > 0, dist);
	}
	// 4) Nothing touching me and another weapon is clearly better for this distance (SMG/shotgun close, rifle far).
	else if(self.bot.close_count == 0 && !self isreloading() && clip > 0 && (!isdefined(self.bot.next_range_swap) || now >= self.bot.next_range_swap))
	{
		self.bot.next_range_swap = now + 4000;
		
		candidate = self bot_get_swap_weapon(weapon, true, false, dist);
		
		if(isdefined(candidate) && isdefined(self.bot.last_swap_score))
		{
			current_score = self bot_weapon_tactical_score(weapon, dist);
			
			if(self.bot.last_swap_score >= current_score + 140)
				new_weapon = candidate;
		}
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
	zombies = bot_get_zombies();
	
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

    zombies = bot_get_zombies();

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

	// Player targets need lead prediction. Zombies change path/turn direction
	// abruptly, so predictposition can alternate between stale left/right
	// velocities. Track their live origin instead for a stable firing solution.
	if(self threat_is_player())
		prediction = self predictposition(ent, frames);
	else
		prediction = ent.origin;
	
	if(!self threat_is_player())
	{
		// Brutus' helmet is removed by repeated head hits. Do not aim at his torso.
		if(is_true(ent.is_brutus))
		{
			head = ent gettagorigin("j_head");
			if(isdefined(head))
				return prediction + (head - ent.origin);
		}

		// Panzer: damage the stock tag_powersupply hit location while the
		// power plant is intact; after it is destroyed, attack the faceplate/head.
		if(is_true(ent.is_mechz))
		{
			weakpoint = undefined;
			if(is_true(ent.has_powerplant))
				weakpoint = ent gettagorigin("tag_powersupply");

			if(!isdefined(weakpoint))
				weakpoint = ent gettagorigin("j_head");

			if(isdefined(weakpoint))
				return prediction + (weakpoint - ent.origin);
		}

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

	// Match the original T6 bot's approximately 45-unit hit tolerance,
	// with a little more room at long range and enough allowance up close.
	radius = dist * 0.075;
	return clamp(radius, 55, 80);
}

bot_on_target(aim_target, radius)
{
	angles = self getplayerangles();
	forward = anglestoforward(angles);
	origin = self getplayercamerapos();
	len = distance(aim_target, origin);
	end = origin + (forward * len);

	// The stock T6 bot uses distance2dsquared here. A full 3D distance
	// incorrectly rejects shots when the aim point has a vertical offset.
	if(distance2dsquared(aim_target, end) < (radius * radius))
		return 1;

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
	// Objective tasks own movement and may own aim, but never disable the
	// bot's threat tracking, defensive fire, or emergency escape handling.
	if(self ismantling() || self isonladder())
	{
		return 0;
	}
	
	if(is_true(self.bot.is_grabbing_box) || is_true(self.bot.is_selfreviving))
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
    enemies = bot_get_zombies();

    if(!isdefined(enemies) || enemies.size == 0)
    {
        self bot_expire_stale_threat();
        return 0;
    }

    // Quest mode deliberately leaves one living zombie alive. This gives the
    // autonomous part/build/quest workers time to finish without the squad
    // ending the round. All bots use the same live zombie count.
    if(isdefined(level.bot_command_mode) && level.bot_command_mode == "quest")
    {
        alive_count = 0;
        foreach(zombie in enemies)
        {
            if(isdefined(zombie) && isalive(zombie) && !is_true(zombie.in_the_ground))
                alive_count++;
        }

        if(alive_count <= 1)
        {
            self bot_clear_enemy();
            return 0;
        }
    }

    wallshoot_range = getdvarfloatdefault("bot_wallshoot_dist", 200);
    switch_margin = 450;
    revive_point = undefined;

    if(maps\mp\zombies\_zm_laststand::player_any_player_in_laststand())
        revive_point = self get_active_revive_point();

    hurt_allies = self bot_get_hurt_allies();

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

        candidate_range = max_range;
        if(is_true(zombie.is_mechz) && candidate_range < 1800)
            candidate_range = 1800;
        else if(is_true(zombie.is_brutus) && candidate_range < 1400)
            candidate_range = 1400;

        if(dist > candidate_range)
            continue;

        key = dist;

        if(is_true(zombie.is_mechz))
            key -= 1000;
        else if(is_true(zombie.is_brutus))
            key -= 850;

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

    // Keep the nearest boss in the candidate list even when several ordinary
    // zombies would otherwise push it out of the top eight candidates.
    boss = self.bot.nearest_boss;
    if(isdefined(boss) && isalive(boss) && !self threat_should_ignore(boss) && !is_true(boss.in_the_ground))
    {
        boss_range = max_range;
        if(is_true(boss.is_mechz) && boss_range < 1800)
            boss_range = 1800;
        else if(is_true(boss.is_brutus) && boss_range < 1400)
            boss_range = 1400;

        if(distance(self.origin, boss.origin) <= boss_range)
        {
            boss_in_list = false;
            for(i = 0; i < cand.size; i++)
            {
                if(cand[i] == boss)
                {
                    boss_in_list = true;
                    break;
                }
            }

            if(!boss_in_list)
                cand[cand.size] = boss;
        }
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
            // Match the point the combat aimer actually tracks; a low origin+32
            // trace can report false while the upper body is clearly exposed.
            visible = sighttracepassed(eye, zombie getcentroid(), 0, self);

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

        // Dogs and sprinters close the gap fast, kill them before they arrive.
        if(self bot_is_dog(zombie))
            score += 250;
        else if(self bot_is_sprinter(zombie))
            score += 80;

        // Protect teammates that are low on health.
        for(k = 0; k < hurt_allies.size; k++)
        {
            if(distancesquared(zombie.origin, hurt_allies[k]) < 22500)
            {
                score += 220;
                break;
            }
        }

        // Zombies already near the crosshair die sooner (no turn time).
        if(dist > 150 && self bot_dot_product(zombie.origin) > 0.8)
            score += 60;

        // Legless crawlers are slow, only worry about them when they are close.
        if(isdefined(zombie.has_legs) && !zombie.has_legs && dist > 200)
            score -= 150;

        // Special threats are more dangerous than ordinary zombies.
        if(is_true(zombie.isscreecher))
            score += 450;

        if(is_true(zombie.is_brutus))
        {
            // Brutus takes reduced body damage while his helmet is intact.
            score += 1250;
            if(is_true(zombie.has_helmet))
                score += 150;
        }
        else if(is_true(zombie.is_mechz))
        {
            // Panzer's exposed/covered power supply is a better target than its armor.
            score += 1400;
            if(is_true(zombie.has_powerplant))
                score += 200;
        }

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

    // A short lock absorbs score noise while two zombies cross in front of
    // the bot. A clearly more dangerous target (650+ score advantage) can
    // still pre-empt the lock immediately.
    if(isdefined(current_score) && best != current &&
       isdefined(self.bot.threat.target_lock_until) &&
       now < self.bot.threat.target_lock_until &&
       (best_score - current_score) < 650)
    {
        best = current;
        best_visible = current_visible;
    }

    // Hysteresis prevents the bot from endlessly swapping between similarly
    // close targets even after the short acquisition lock expires.
    if(isdefined(current_score) && best != current && (best_score - current_score) < switch_margin)
    {
        best = current;
        best_visible = current_visible;
    }

    if(!isdefined(current) || best != current)
    {
        self.bot.threat.time_first_sight = now;
        self.bot.threat.time_aim_correct = 0;
        self.bot.threat.time_last_aim_update = 0;
        self.bot.threat.aim_target = undefined;
        self.bot.threat.fire_until = 0;
        self.bot.threat.target_lock_until = now + 500;
    }

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
	self.bot.threat.aim_target = undefined;
	self.bot.threat.time_aim_correct = 0;
	self.bot.threat.time_last_aim_update = 0;
	self.bot.threat.fire_until = 0;
	self.bot.threat.target_lock_until = 0;
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