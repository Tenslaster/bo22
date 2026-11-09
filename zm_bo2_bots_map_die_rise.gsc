#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_utility;

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
                                self scripts\zm\zm_bo2_bots::bot_quest_use_target(order[step], "bot_die_rise_dragon", 42, 1);
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
                self scripts\zm\zm_bo2_bots::bot_quest_use_target(ball.t_pickup, "bot_die_rise_lion_ball_pickup", 40, 3);
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
                self scripts\zm\zm_bo2_bots::bot_quest_use_target(place_trigger, "bot_die_rise_lion_ball_place", 40, 2);
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
                self scripts\zm\zm_bo2_bots::bot_quest_deploy_equipment(springpad_name, spot.origin, "bot_die_rise_springpad");
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
                self scripts\zm\zm_bo2_bots::bot_quest_fire_at(ssp_ball.origin, "slipgun_zm", "bot_die_rise_sliquify", 700, 22, 0.1);
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
            self scripts\zm\zm_bo2_bots::bot_quest_hold_in_volume(corpse_room.origin, "bot_die_rise_corpse_room", 190, 4.0);
    }
    else if(isdefined(level._cur_stage_name) && level._cur_stage_name == "ssp_2" &&
            flag("ssp2_corpses_in_place") && !flag("ssp2_resurrection_done") && self hasweapon("knife_ballistic_upgraded_zm"))
    {
        corpse_room = getent("corpse_room_trigger", "targetname");
        if(isdefined(corpse_room) && isdefined(corpse_room.origin))
            self scripts\zm\zm_bo2_bots::bot_quest_fire_at(corpse_room.origin, "knife_ballistic_upgraded_zm", "bot_die_rise_resurrection", 500, 5, 0.1);
    }

    self bot_quest_die_rise_tower();

    // When no quest interaction is active, let the bot use a reachable stock
    // jump pad. The stock jump-pad script handles the actual launch/landing.
    self bot_quest_die_rise_traverse();
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


// Use the live Die Rise elevator system when a quest/follow destination is
// on another floor and the normal nav graph has no direct route. The stock map
// controls elevator timing, moving-platform links and floor path activation.
bot_quest_die_rise_elevator_to(target_origin, goal_name, range, max_time)
{
    if(!isdefined(target_origin) || getdvar("mapname") != "zm_highrise" ||
       !isdefined(level.elevators) || level.elevators.size == 0)
        return false;

    if(!isdefined(range) || range < 24)
        range = 96;
    if(!isdefined(max_time) || max_time < 1000)
        max_time = 12000;

    // Elevators are only a vertical-connection fallback; don't ride them for
    // a same-floor obstacle that the alternate-node recovery should handle.
    if(abs(target_origin[2] - self.origin[2]) < 180)
        return false;

    chosen_elevator = undefined;
    chosen_floor_key = undefined;
    chosen_exit = undefined;
    chosen_score = 999999999;

    // If the bot is already riding a lift, keep using that lift instead of
    // trying to path to a second platform.
    current_parent = undefined;
    if(self maps\mp\zm_highrise_elevators::object_is_on_elevator() &&
       isdefined(self.elevator_parent))
        current_parent = self.elevator_parent;

    foreach(elevator in level.elevators)
    {
        if(!isdefined(elevator) || !isdefined(elevator.body) ||
           !isdefined(elevator.floors) || !isdefined(elevator.body.origin))
            continue;

        body = elevator.body;
        already_boarded = isdefined(current_parent) && current_parent == body;
        if(isdefined(current_parent) && !already_boarded)
            continue;

        if(!already_boarded)
        {
            if(is_true(body.is_moving))
                continue;

            board_ent = body;
            if(isdefined(body.trig) && isdefined(body.trig.origin))
                board_ent = body.trig;

            if(!findpath(self.origin, board_ent.origin, undefined, 0, 1))
                continue;
        }

        floor_keys = getarraykeys(elevator.floors);
        foreach(floor_key in floor_keys)
        {
            floor = elevator.floors[floor_key];
            if(!isdefined(floor) || !isdefined(floor.origin))
                continue;

            if(isdefined(body.current_level) && ("" + body.current_level) == ("" + floor_key))
                continue;

            exit_node = undefined;
            exit_score = 999999999;

            if(isdefined(floor.paths) && floor.paths.size > 0)
            {
                foreach(path_node in floor.paths)
                {
                    if(!isdefined(path_node) || !isdefined(path_node.origin))
                        continue;

                    if(!findpath(path_node.origin, target_origin, undefined, 0, 1))
                        continue;

                    node_score = distancesquared(path_node.origin, target_origin);
                    if(node_score < exit_score)
                    {
                        exit_score = node_score;
                        exit_node = path_node;
                    }
                }
            }

            // Some elevator floors expose their entry point directly, without
            // a separate named floor-path node.
            if(!isdefined(exit_node) &&
               findpath(floor.origin, target_origin, undefined, 0, 1))
            {
                exit_node = floor;
                exit_score = distancesquared(floor.origin, target_origin);
            }

            if(!isdefined(exit_node))
                continue;

            board_distance = 0;
            if(!already_boarded)
            {
                board_point = body.origin;
                if(isdefined(body.trig) && isdefined(body.trig.origin))
                    board_point = body.trig.origin;
                board_distance = distancesquared(self.origin, board_point);
            }

            // Prefer a nearby elevator whose selected floor has a real route
            // toward the destination, not merely the numerically nearest lift.
            score = board_distance + exit_score * 0.18;
            if(score < chosen_score)
            {
                chosen_score = score;
                chosen_elevator = elevator;
                chosen_floor_key = "" + floor_key;
                chosen_exit = exit_node;
            }
        }

        if(already_boarded && isdefined(chosen_elevator))
            break;
    }

    if(!isdefined(chosen_elevator) || !isdefined(chosen_floor_key) ||
       !isdefined(chosen_exit) || !isdefined(chosen_elevator.body))
        return false;

    self.bot.is_objective_using = 1;
    elevator_body = chosen_elevator.body;
    boarded = self maps\mp\zm_highrise_elevators::object_is_on_elevator() &&
              isdefined(self.elevator_parent) && self.elevator_parent == elevator_body;

    if(!boarded)
    {
        board_ent = elevator_body;
        if(isdefined(elevator_body.trig) && isdefined(elevator_body.trig.origin))
            board_ent = elevator_body.trig;

        board_deadline = gettime() + 14000;
        next_refresh = 0;
        while(gettime() < board_deadline && isalive(self) && isdefined(elevator_body))
        {
            if(self maps\mp\zm_highrise_elevators::object_is_on_elevator() &&
               isdefined(self.elevator_parent) && self.elevator_parent == elevator_body)
            {
                boarded = true;
                break;
            }

            if(gettime() >= next_refresh && isdefined(board_ent.origin))
            {
                self cancelgoal(goal_name + "_board");
                self addgoal(board_ent.origin, 32, 2, goal_name + "_board");
                next_refresh = gettime() + 900;
            }
            wait 0.15;
        }
        self cancelgoal(goal_name + "_board");
    }

    reached_floor = false;
    if(boarded)
    {
        ride_deadline = gettime() + 75000;
        while(gettime() < ride_deadline && isalive(self) && isdefined(elevator_body))
        {
            if(!self maps\mp\zm_highrise_elevators::object_is_on_elevator() ||
               !isdefined(self.elevator_parent) || self.elevator_parent != elevator_body)
                break;

            if(isdefined(elevator_body.current_level) &&
               ("" + elevator_body.current_level) == chosen_floor_key &&
               !is_true(elevator_body.is_moving))
            {
                reached_floor = true;
                break;
            }
            wait 0.2;
        }
    }

    exited = false;
    if(reached_floor && isdefined(chosen_exit) && isdefined(chosen_exit.origin))
    {
        self addgoal(chosen_exit.origin, 28, 2, goal_name + "_exit");
        exit_deadline = gettime() + 9000;
        while(gettime() < exit_deadline && isalive(self))
        {
            if(!self maps\mp\zm_highrise_elevators::object_is_on_elevator() ||
               !isdefined(self.elevator_parent) || self.elevator_parent != elevator_body)
            {
                exited = true;
                break;
            }

            if(distancesquared(self.origin, chosen_exit.origin) <= 28 * 28)
                wait 0.1;
            else
                wait 0.15;
        }
        self cancelgoal(goal_name + "_exit");
    }

    arrived = false;
    if(exited && findpath(self.origin, target_origin, undefined, 0, 1))
    {
        self addgoal(target_origin, range, 2, goal_name);
        move_deadline = gettime() + max_time;
        while(gettime() < move_deadline && isalive(self))
        {
            if(distancesquared(self.origin, target_origin) <= range * range)
            {
                arrived = true;
                break;
            }
            wait 0.2;
        }
        self cancelgoal(goal_name);
    }

    self cancelgoal(goal_name + "_board");
    self cancelgoal(goal_name + "_exit");
    self.bot.is_objective_using = undefined;
    return arrived;
}


// -----------------------------------------------------------------------------
// Die Rise traversal: route bots onto native jump-pad triggers.
//
// Do not simulate flight by teleporting or setting velocity. The stock
// _zm_jump_pad script owns the launch, trajectory, landing, and POI cleanup.
// This worker only navigates to a reachable trigger and waits for that system.
// -----------------------------------------------------------------------------
bot_die_rise_movement_target()
{
    if(isdefined(level.bot_command_mode) && level.bot_command_mode == "follow")
    {
        commander = level.bot_commander;
        if(isdefined(commander) && isdefined(commander.origin) && isalive(commander) &&
           !isdefined(commander.bot) &&
           !(isdefined(commander.pers) && isdefined(commander.pers["isbot"])))
            return commander.origin;

        foreach(candidate in get_players())
        {
            if(!isdefined(candidate) || !isdefined(candidate.origin) || !isalive(candidate) ||
               isdefined(candidate.bot) ||
               (isdefined(candidate.pers) && isdefined(candidate.pers["isbot"])))
                continue;
            return candidate.origin;
        }
    }

    if(isdefined(level.bot_command_mode) &&
       (level.bot_command_mode == "wander" || level.bot_command_mode == "wander_further") &&
       self hasgoal("wander"))
        return self getgoal("wander");

    return undefined;
}


bot_quest_die_rise_traverse()
{
    if(!isdefined(self.bot) || is_true(self.bot.is_parkour))
        return false;

    if(is_true(self._padded) || is_true(self.lander))
        return false;

    if(isdefined(self.bot.parkour_retry) && gettime() < self.bot.parkour_retry)
        return false;

    // Never replace an active combat escape, revive, purchase, or map objective.
    if(is_true(self.bot.is_objective_using) || is_true(self.bot.is_building) ||
       is_true(self.bot.is_crafting) || is_true(self.bot.is_buying) ||
       is_true(self.bot.is_using_box) || is_true(self.bot.is_reviving) ||
       is_true(self.bot.is_selfreviving) || self getgoal("flee") || self hasgoal("flee"))
        return false;

    if(!self isonground() || self isonladder() || self ismantling())
        return false;

    target_origin = self bot_die_rise_movement_target();
    if(!isdefined(target_origin) ||
       findpath(self.origin, target_origin, undefined, 0, 1))
        return false;

    pads = getentarray("trig_jump_pad", "targetname");
    if(!isdefined(pads) || pads.size == 0)
        return false;

    current_target_distance = distancesquared(self.origin, target_origin);
    best = undefined;
    best_distance = 999999999;

    foreach(pad in pads)
    {
        if(!isdefined(pad) || !isdefined(pad.origin) ||
           !isdefined(pad.destination) || pad.destination.size == 0)
            continue;

        dist_sq = distancesquared(self.origin, pad.origin);
        if(dist_sq < 96 * 96 || dist_sq > 1800 * 1800)
            continue;
        if(!findpath(self.origin, pad.origin, undefined, 0, 1))
            continue;

        // The stock jump-pad script randomly chooses one destination from
        // this array. Only use this pad when every possible landing is a
        // useful, pathable step toward the bot's actual movement target.
        all_destinations_useful = true;
        destination_score = 0;
        for(dest_index = 0; dest_index < pad.destination.size; dest_index++)
        {
            destination = pad.destination[dest_index];
            if(!isdefined(destination) || !isdefined(destination.origin) ||
               distancesquared(destination.origin, target_origin) >= current_target_distance - 14400 ||
               !findpath(destination.origin, target_origin, undefined, 0, 1))
            {
                all_destinations_useful = false;
                break;
            }
            destination_score += distancesquared(destination.origin, target_origin);
        }

        if(!all_destinations_useful)
            continue;

        score = dist_sq + (destination_score / pad.destination.size) * 0.2;
        if(score < best_distance)
        {
            best = pad;
            best_distance = score;
        }
    }

    if(!isdefined(best))
    {
        self.bot.parkour_retry = gettime() + 5000;
        return false;
    }

    self.bot.is_parkour = 1;
    self.bot.is_objective_using = 1;
    self addgoal(best.origin, 28, 2, "bot_die_rise_parkour");

    // The native trigger launches the bot when it physically reaches the pad.
    // Give navigation enough time to reach the trigger, but never camp forever.
    approach_deadline = gettime() + 8000;
    launched = false;

    while(gettime() < approach_deadline && isalive(self))
    {
        if(is_true(self._padded) || is_true(self.lander))
        {
            launched = true;
            break;
        }

        if(distancesquared(self.origin, best.origin) <= 48 * 48)
        {
            // A trigger touch is normally delivered by the game. Do not fake
            // the event: wait briefly for the stock pad handler to respond.
            wait 0.2;
        }
        else
            wait 0.15;
    }

    self cancelgoal("bot_die_rise_parkour");

    if(launched)
    {
        // Keep the traversal task reserved until the stock launch has landed.
        landing_deadline = gettime() + 16000;
        while(gettime() < landing_deadline && isalive(self) &&
              (is_true(self._padded) || is_true(self.lander) || !self isonground()))
            wait 0.1;
    }

    if(launched && isdefined(target_origin) && isalive(self))
        self scripts\zm\zm_bo2_bots::bot_quest_navigate_to(target_origin, "bot_die_rise_parkour_target", 72, 9000);

    self.bot.is_parkour = undefined;
    self.bot.is_objective_using = undefined;
    self.bot.parkour_retry = gettime() + (launched ? 1800 : 6000);
    return launched;
}
