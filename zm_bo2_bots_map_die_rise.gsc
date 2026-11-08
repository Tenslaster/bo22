// -----------------------------------------------------------------------------
// Die Rise map-specific bot logic (zm_highrise).
// Shared bot systems and generic quest helpers remain in zm_bo2_bots.gsc.
// Edit this file for behavior that belongs only to this map.
// -----------------------------------------------------------------------------

bot_quest_die_rise_tower()
{
    if(!flag("sq_branch_complete") || flag("sq_tower_active") || !isdefined(level.a_wind_order) || level.a_wind_order.size < 4)
        return false;

    index = 0;
    if(isdefined(level.n_cur_leg))
        index = level.n_cur_leg;
    if(index < 0 || index >= 4)
        return false;

    trigger = getent("sq_tower_" + level.a_wind_order[index], "script_noteworthy");
    if(!isdefined(trigger) || !isdefined(trigger.origin))
        return false;

    // The stock watcher tests the player's melee weapon on a touch trigger;
    // pressing use does not advance it. Equip Tazer Knuckles and stand on the
    // exact next leg until the native quest index increments.
    melee_weapon = self get_player_melee_weapon();
    if(self hasweapon("tazer_knuckles_zm"))
        self set_player_melee_weapon("tazer_knuckles_zm");
    else if(self hasweapon("tazer_knuckles_upgraded_zm"))
        self set_player_melee_weapon("tazer_knuckles_upgraded_zm");
    else if(!isdefined(melee_weapon) || (melee_weapon != "tazer_knuckles_zm" && melee_weapon != "tazer_knuckles_upgraded_zm"))
        return false;

    if(!findpath(self.origin, trigger.origin, undefined, 0, 1))
        return false;

    self addgoal(trigger.origin, 36, 2, "bot_die_rise_tower_leg");
    deadline = gettime() + 9000;
    while(gettime() < deadline && !flag("sq_tower_active") && isalive(self))
    {
        if(isdefined(level.n_cur_leg) && level.n_cur_leg > index)
            break;
        wait 0.15;
    }
    self cancelgoal("bot_die_rise_tower_leg");
    return isdefined(level.n_cur_leg) && level.n_cur_leg > index;
}

bot_quest_die_rise()
{
    // The Above the Dragon step needs all four elevator triggers occupied at
    // once. Each bot owns one trigger; the stock quest script sets the flags.
    if(!flag("sq_atd_elevator_activated"))
    {
        if(!self bot_quest_die_rise_stack_elevators())
        {
            // Fallback to one physical trigger per bot if the compatibility
            // helper cannot relocate the trigger volumes on this build.
            elevator_names = array("elevator_bldg1b_trigger", "elevator_bldg1d_trigger", "elevator_bldg3b_trigger", "elevator_bldg3c_trigger");
            elevator_flags = array("sq_atd_elevator0", "sq_atd_elevator1", "sq_atd_elevator2", "sq_atd_elevator3");
            bot_slot = 0;
            bot_count = 0;
            players_now = get_players();
            foreach(p in players_now)
            {
                if(!isdefined(p) || !isdefined(p.bot))
                    continue;
                if(p == self)
                    bot_slot = bot_count % 4;
                bot_count++;
            }
            trigger = getent(elevator_names[bot_slot], "targetname");
            if(isdefined(trigger) && isdefined(trigger.origin) && !flag(elevator_flags[bot_slot]))
                self bot_quest_hold_elevator(trigger, elevator_flags[bot_slot]);
        }
        return;
    }

    // The dragon-symbol sequence is randomized by the map. Bots brute-force
    // complete permutations and verify every step against the live quest index.
    if(!flag("sq_atd_drg_puzzle_complete") &&
       (!isdefined(level.bot_quest_dragon_owner) || !isalive(level.bot_quest_dragon_owner)))
    {
        level.bot_quest_dragon_owner = self;
        a_trigs = getentarray("trig_atd_drg_puzzle", "targetname");

        if(isdefined(a_trigs) && a_trigs.size == 4)
        {
            // Try all 24 permutations once instead of repeatedly sampling
            // random orders; the stock puzzle resets to index 0 on a wrong
            // symbol, so exhaustive permutations guarantee the hidden order
            // is eventually attempted if each trigger is reachable.
            for(first = 0; first < 4 && !flag("sq_atd_drg_puzzle_complete"); first++)
            {
                for(second = 0; second < 4 && !flag("sq_atd_drg_puzzle_complete"); second++)
                {
                    if(second == first)
                        continue;
                    for(third = 0; third < 4 && !flag("sq_atd_drg_puzzle_complete"); third++)
                    {
                        if(third == first || third == second)
                            continue;
                        for(fourth = 0; fourth < 4 && !flag("sq_atd_drg_puzzle_complete"); fourth++)
                        {
                            if(fourth == first || fourth == second || fourth == third)
                                continue;

                            order = array(a_trigs[first], a_trigs[second], a_trigs[third], a_trigs[fourth]);
                            for(step = 0; step < 4; step++)
                            {
                                if(flag("sq_atd_drg_puzzle_complete"))
                                    break;

                                before = level.sq_atd_cur_drg;
                                self bot_quest_use_target(order[step], "bot_die_rise_dragon", 42, 1);
                                wait 0.25;

                                if(!isdefined(level.sq_atd_cur_drg) || level.sq_atd_cur_drg != before + 1)
                                    break;
                            }
                            wait 0.2;
                        }
                    }
                }
            }
        }

        level.bot_quest_dragon_owner = undefined;
        return;
    }

    // The SLB branch explicitly requires sniper damage on the two dragon-tail
    // balls. Do not fake the hit: fire a real sniper round at each map entity.
    sniper = undefined;
    sniper_names = array("dsr50_zm", "dsr50_upgraded_zm", "dsr50_upgraded_zm+vzoom", "barretm82_zm", "barretm82_upgraded_zm", "barretm82_upgraded_zm+vzoom", "svu_zm", "svu_upgraded_zm", "svu_upgraded_zm+vzoom");
    foreach(name in sniper_names)
    {
        if(self hasweapon(name))
        {
            sniper = name;
            break;
        }
    }

    balls = getentarray("sq_dragon_lion_ball", "targetname");
    if(isdefined(balls) && balls.size > 0 && isdefined(sniper))
    {
        self.bot.is_objective_using = 1;
        self switchtoweaponimmediate(sniper);

        foreach(ball in balls)
        {
            if(!isdefined(ball) || !isdefined(ball.origin))
                continue;

            deadline = gettime() + 4000;
            while(isdefined(ball) && gettime() < deadline)
            {
                self lookat(ball.origin);
                self pressattackbutton(0.1);
                wait 0.15;
            }
        }

        self.bot.is_objective_using = undefined;
        self clearlookat();
        return;
    }

    // Pick up and set down the stock lion balls once the map has exposed their
    // triggers. The spring-pad placement worker below handles available pads.
    if(!isdefined(self.zm_sq_has_ball))
    {
        ball_names = array("sq_sliquify_r", "sq_sliquify_m");
        foreach(ball_name in ball_names)
        {
            ball = getent(ball_name, "script_noteworthy");
            if(isdefined(ball) && isdefined(ball.t_pickup) && isdefined(ball.t_pickup.origin) &&
               isdefined(ball.can_pickup) && ball.can_pickup)
            {
                self bot_quest_use_target(ball.t_pickup, "bot_die_rise_lion_ball_pickup", 40, 3);
                return;
            }
        }
    }
    else if(isdefined(self.a_place_ball_trigs))
    {
        foreach(place_trigger in self.a_place_ball_trigs)
        {
            if(isdefined(place_trigger) && isdefined(place_trigger.origin))
            {
                self bot_quest_use_target(place_trigger, "bot_die_rise_lion_ball_place", 40, 2);
                return;
            }
        }
    }

    // Deploy available spring pads on the map's native lion spots.
    springpad_name = "equip_springpad_zm";
    if(isdefined(level.springpad_name))
        springpad_name = level.springpad_name;

    if(self has_player_equipment(springpad_name))
    {
        spot_type = "pts_lion";
        if(isdefined(level._cur_stage_name) && level._cur_stage_name == "pts_1")
            spot_type = "pts_ghoul";
        springpad_spots = getstructarray(spot_type, "targetname");
        foreach(spot in springpad_spots)
        {
            if(isdefined(spot) && isdefined(spot.origin) &&
               (!isdefined(spot.springpad) || !isdefined(spot.springpad.origin)))
            {
                self bot_quest_deploy_equipment(springpad_name, spot.origin, "bot_die_rise_springpad");
                return;
            }
        }
    }

    // Richtofen's first Dragon stage uses the Sliquifier to dissolve each
    // sphere. The native watcher requires 20 damage callbacks per sphere.
    if(isdefined(level._cur_stage_name) && level._cur_stage_name == "ssp_1" && self hasweapon("slipgun_zm"))
    {
        ssp_balls = getentarray("sq_sliquify_ball", "targetname");
        foreach(ssp_ball in ssp_balls)
        {
            if(isdefined(ssp_ball) && isdefined(ssp_ball.origin))
            {
                self bot_quest_fire_at(ssp_ball.origin, "slipgun_zm", "bot_die_rise_sliquify", 700, 22, 0.1);
                return;
            }
        }
    }

    // Maxis' resurrection stage requires the squad to accumulate 15 corpses
    // in the corpse-room volume. Keep bots in the room while the combat loop
    // creates the real death events.
    if(isdefined(level._cur_stage_name) && level._cur_stage_name == "ssp_2" && !flag("ssp2_corpses_in_place"))
    {
        corpse_room = getent("corpse_room_trigger", "targetname");
        if(isdefined(corpse_room) && isdefined(corpse_room.origin))
            self bot_quest_hold_in_volume(corpse_room.origin, "bot_die_rise_corpse_room", 190, 4.0);
    }
    else if(isdefined(level._cur_stage_name) && level._cur_stage_name == "ssp_2" &&
            flag("ssp2_corpses_in_place") && !flag("ssp2_resurrection_done") && self hasweapon("knife_ballistic_upgraded_zm"))
    {
        corpse_room = getent("corpse_room_trigger", "targetname");
        if(isdefined(corpse_room) && isdefined(corpse_room.origin))
            self bot_quest_fire_at(corpse_room.origin, "knife_ballistic_upgraded_zm", "bot_die_rise_resurrection", 500, 5, 0.1);
    }

    self bot_quest_die_rise_tower();
}

bot_quest_die_rise_stack_elevators()
{
    if(flag("sq_atd_elevator_activated"))
        return true;

    if(isdefined(level.bot_atd_elevator_assist_owner) && level.bot_atd_elevator_assist_owner != self &&
       isalive(level.bot_atd_elevator_assist_owner))
        return true;

    elevator_names = array("elevator_bldg1b_trigger", "elevator_bldg1d_trigger", "elevator_bldg3b_trigger", "elevator_bldg3c_trigger");
    triggers = [];
    original_origins = [];

    for(i = 0; i < elevator_names.size; i++)
    {
        trigger = getent(elevator_names[i], "targetname");
        if(!isdefined(trigger) || !isdefined(trigger.origin))
            return false;
        triggers[i] = trigger;
        original_origins[i] = trigger.origin;
    }

    level.bot_atd_elevator_assist_owner = self;
    self.bot.is_objective_using = 1;
    anchor = self.origin;

    // The stock elevator watcher still receives all four real trigger events
    // and owns all four flags. Temporarily co-locate its volumes so a solo
    // host plus bots does not need a human to occupy a fourth pad.
    for(i = 0; i < triggers.size; i++)
        triggers[i].origin = anchor;

    wait_network_frame();
    for(i = 0; i < triggers.size; i++)
        triggers[i] notify("trigger", self);

    deadline = gettime() + 4000;
    while(!flag("sq_atd_elevator_activated") && gettime() < deadline && isalive(self))
        wait 0.1;

    success = flag("sq_atd_elevator_activated");
    for(i = 0; i < triggers.size; i++)
    {
        if(isdefined(triggers[i]))
            triggers[i].origin = original_origins[i];
    }

    level.bot_atd_elevator_assist_owner = undefined;
    self.bot.is_objective_using = undefined;
    return success;
}

bot_quest_hold_elevator(trigger, flag_name)
{
    if(!isdefined(trigger) || !isdefined(trigger.origin))
        return;

    if(!findpath(self.origin, trigger.origin, undefined, 0, 1))
        return;

    self addgoal(trigger.origin, 48, 2, "bot_die_rise_elevator");
    deadline = gettime() + 15000;

    while(gettime() < deadline && !flag("sq_atd_elevator_activated"))
    {
        if(flag(flag_name))
            break;

        if(distancesquared(self.origin, trigger.origin) <= 2304)
        {
            self.bot.is_objective_using = 1;
            self lookat(trigger.origin + (0, 0, 24));
            self pressusebutton(0.15);
            wait 0.25;
            if(flag(flag_name))
            {
                // Keep this bot inside its elevator until the other three
                // stock flags are also active.
                while(!flag("sq_atd_elevator_activated") && isalive(self))
                    wait 0.25;
                break;
            }
        }
        wait 0.2;
    }

    self.bot.is_objective_using = undefined;
    self clearlookat();
    self cancelgoal("bot_die_rise_elevator");
}
