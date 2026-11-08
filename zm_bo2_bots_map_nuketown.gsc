// -----------------------------------------------------------------------------
// Nuketown Zombies map-specific bot logic (zm_nuked).
// Shared bot systems and generic quest helpers remain in zm_bo2_bots.gsc.
// Edit this file for behavior that belongs only to this map.
// -----------------------------------------------------------------------------

bot_quest_nuketown_mannequins()
{
    if(!isdefined(level.mannequin_count) || level.mannequin_count <= 0)
        return false;

    destructibles = getentarray("destructible", "targetname");
    foreach(item in destructibles)
    {
        if(!isdefined(item) || !isdefined(item.origin) || !isdefined(item.destructibledef) ||
           !issubstr(item.destructibledef, "male"))
            continue;
        if(isdefined(item.bot_auto_mannequin_owner) && item.bot_auto_mannequin_owner != self &&
           isdefined(item.bot_auto_mannequin_until) && gettime() < item.bot_auto_mannequin_until &&
           isalive(item.bot_auto_mannequin_owner))
            continue;
        item.bot_auto_mannequin_owner = self;
        item.bot_auto_mannequin_until = gettime() + 6000;
        primary = self bot_quest_primary_weapon();
        if(isdefined(primary))
            self bot_quest_fire_at(item.origin, primary, "bot_nuketown_mannequin", 850, 5, 0.1);
        item.bot_auto_mannequin_owner = undefined;
        item.bot_auto_mannequin_until = 0;
        return true;
    }
    return false;
}

bot_quest_nuketown()
{
    if(!isdefined(level.meteor_counter))
        return;

    if(level.meteor_counter >= 3)
    {
        if(!(isdefined(level.music_override) && level.music_override))
            self bot_quest_nuketown_mannequins();
        return;
    }

    if(isdefined(level.music_override) && level.music_override)
        return;

    if(isdefined(level.population_count) && level.population_count == 15 &&
       isdefined(level.door_powerup) && isdefined(level.door_powerup.origin))
    {
        self bot_quest_move_to(level.door_powerup.origin, "bot_nuketown_clock_powerup", 36, 5000);
        return;
    }

    // The map's fake-use handler checks distance, facing and use-button state.
    // These are the three real meteor/bear locations from zm_nuked.gsc.
    origins = array(( -1998, 632, -48 ), ( -80, 35, -18 ), ( 617, 313, 152 ));
    index = level.meteor_counter;

    if(index < 0 || index >= origins.size)
        return;

    if(isdefined(level.bot_quest_nuked_owner) && level.bot_quest_nuked_owner != self &&
       isdefined(level.bot_quest_nuked_owner_until) && gettime() < level.bot_quest_nuked_owner_until &&
       isalive(level.bot_quest_nuked_owner))
        return;

    level.bot_quest_nuked_owner = self;
    level.bot_quest_nuked_owner_until = gettime() + 10000;
    point = spawnstruct();
    point.origin = origins[index];
    self bot_quest_use_target(point, "bot_nuketown_meteor", 42, 7);
    level.bot_quest_nuked_owner = undefined;
    level.bot_quest_nuked_owner_until = undefined;

    if(level.meteor_counter >= 3)
        self bot_quest_nuketown_mannequins();
}
