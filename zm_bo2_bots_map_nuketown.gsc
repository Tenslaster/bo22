#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_utility;

// -----------------------------------------------------------------------------
// Nuketown Zombies map-specific bot logic (zm_nuked).
// Shared bot systems and generic quest helpers remain in zm_bo2_bots.gsc.
// Edit this file for behavior that belongs only to this map.
// -----------------------------------------------------------------------------

bot_nuketown_install_mannequin_hook()
{
    if(isdefined(level.destructible_callbacks) && isdefined(level.destructible_callbacks["headless"]))
    {
        level.bo22_nuketown_headless = level.destructible_callbacks["headless"];
        level.destructible_callbacks["headless"] = ::bot_nuketown_mannequin_headless;
    }
}

bot_nuketown_mannequin_headless(event, attacker)
{
    self.bot_nuketown_headless = 1;
    self [[level.bo22_nuketown_headless]](event, attacker);
}

bot_quest_nuketown_mannequins()
{
    if(!isdefined(level.mannequin_count) || level.mannequin_count <= 0)
        return;

    primary = self scripts\zm\zm_bo2_bots::bot_quest_primary_weapon();
    if(!isdefined(primary))
        return;

    best = undefined;
    best_dist = 999999999;
    destructibles = getentarray("destructible", "targetname");
    foreach(item in destructibles)
    {
        if(!isdefined(item.origin) || !isdefined(item.destructibledef) ||
           !issubstr(item.destructibledef, "male") || is_true(item.bot_nuketown_headless) ||
           (isdefined(item.bot_nuketown_retry) && gettime() < item.bot_nuketown_retry))
            continue;

        dist = distancesquared(self.origin, item.origin);
        if(dist < best_dist)
        {
            best = item;
            best_dist = dist;
        }
    }

    if(isdefined(best))
    {
        best.bot_nuketown_retry = gettime() + 12000;
        self scripts\zm\zm_bo2_bots::bot_quest_fire_at(
            best.origin + (0, 0, 56), primary, "bot_nuketown_mannequin", 450, 5, 0.1);
    }
}

bot_quest_nuketown()
{
    if(!isdefined(level.meteor_counter) || is_true(level.music_override))
        return;

    if(level.meteor_counter >= 3)
    {
        self bot_quest_nuketown_mannequins();
        return;
    }

    if(isdefined(level.bot_quest_nuked_owner) && level.bot_quest_nuked_owner != self &&
       gettime() < level.bot_quest_nuked_owner_until && isalive(level.bot_quest_nuked_owner))
        return;

    if(isdefined(level.population_count) && level.population_count == 15 &&
       isdefined(level.door_powerup) && isdefined(level.door_powerup.origin) &&
       (!isdefined(level.bot_nuked_clock_retry) || gettime() >= level.bot_nuked_clock_retry))
    {
        level.bot_nuked_clock_retry = gettime() + 8000;
        if(self scripts\zm\zm_bo2_bots::bot_quest_move_to(level.door_powerup.origin, "bot_nuketown_clock_powerup", 24, 5000))
            return;
    }

    // The stock counter is the number found, so it cannot identify a bear.
    // Inspect the live stock script origins to handle any pickup order.
    points = array((-1998, 632, -48), (-80, 35, -18), (617, 313, 152));
    if(!isdefined(level.bot_nuked_meteors_done))
        level.bot_nuked_meteors_done = [];

    nearest = undefined;
    nearest_index = undefined;
    nearest_dist = 999999999;
    origins = getentarray("script_origin", "classname");
    foreach(origin_ent in origins)
    {
        for(i = 0; i < points.size; i++)
        {
            if(is_true(level.bot_nuked_meteors_done[i]) || distancesquared(origin_ent.origin, points[i]) > 1 ||
               (isdefined(origin_ent.bot_nuked_retry) && gettime() < origin_ent.bot_nuked_retry))
                continue;
            dist = distancesquared(self.origin, origin_ent.origin);
            if(dist < nearest_dist)
            {
                nearest = origin_ent;
                nearest_index = i;
                nearest_dist = dist;
            }
        }
    }

    if(!isdefined(nearest))
        return;

    level.bot_quest_nuked_owner = self;
    level.bot_quest_nuked_owner_until = gettime() + 43000;
    nearest.bot_nuked_retry = gettime() + 8000;
    self scripts\zm\zm_bo2_bots::bot_quest_use_target(nearest, "bot_nuketown_meteor", 34, 4);

    // The native watcher deletes a used bearer after 1.5 seconds. The third
    // remains as the sound source until playback ends.
    wait 1.6;
    if(!isdefined(nearest) || level.meteor_counter >= 3)
        level.bot_nuked_meteors_done[nearest_index] = 1;
    if(isdefined(level.bot_quest_nuked_owner) && level.bot_quest_nuked_owner == self)
        level.bot_quest_nuked_owner = undefined;
}
