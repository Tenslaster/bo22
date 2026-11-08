// -----------------------------------------------------------------------------
// Origins map-specific bot logic (zm_tomb).
// Shared bot systems and generic quest helpers remain in zm_bo2_bots.gsc.
// Edit this file for behavior that belongs only to this map.
// -----------------------------------------------------------------------------

bot_quest_origins_staff_puzzles()
{
    if(isdefined(level.bot_origins_staff_puzzle_owner) && level.bot_origins_staff_puzzle_owner != self &&
       isdefined(level.bot_origins_staff_puzzle_owner_until) && gettime() < level.bot_origins_staff_puzzle_owner_until &&
       isalive(level.bot_origins_staff_puzzle_owner))
        return false;

    level.bot_origins_staff_puzzle_owner = self;
    level.bot_origins_staff_puzzle_owner_until = gettime() + 12000;
    did_work = false;

    // AIR 1: the ring's own script_int is the correct quadrant. Fire only the
    // required number of real Wind Staff hits; the stock ring code sets flag.
    if(!flag("air_puzzle_1_complete") && self hasweapon("staff_air_zm") && isdefined(level.a_ceiling_rings))
    {
        foreach(ring in level.a_ceiling_rings)
        {
            if(!isdefined(ring) || !isdefined(ring.origin) || !isdefined(ring.position) || !isdefined(ring.script_int))
                continue;
            turns = (ring.script_int - ring.position + 4) % 4;
            for(i = 0; i < turns && !flag("air_puzzle_1_complete"); i++)
            {
                self bot_quest_fire_at(ring.origin, "staff_air_zm", "bot_origins_air_ring", 720, 1, 0.1);
                wait 0.22;
            }
        }
        did_work = true;
    }

    // AIR 2: direct each detector toward the destination marker. The stock
    // puzzle judges the weapon direction, not the bot's position alone.
    if(!flag("air_puzzle_2_complete") && self hasweapon("staff_air_zm"))
    {
        smoke_positions = getstructarray("puzzle_smoke_origin", "targetname");
        smoke_dest = getstruct("puzzle_smoke_dest", "targetname");
        foreach(smoke in smoke_positions)
        {
            if(!isdefined(smoke) || !isdefined(smoke.solved) || smoke.solved || !isdefined(smoke.origin) || !isdefined(smoke.detector_brush))
                continue;
            if(!isdefined(smoke_dest) || !isdefined(smoke_dest.origin) || !isdefined(smoke.detector_brush.origin))
                break;
            smoke_direction = vectornormalize(smoke_dest.origin - smoke.origin);
            shoot_origin = smoke.detector_brush.origin - vectorscale(smoke_direction, 180);
            aim_point = smoke.detector_brush.origin + vectorscale(smoke_direction, 500);
            if(distancesquared(self.origin, shoot_origin) > 150 * 150)
            {
                self bot_quest_move_to(shoot_origin, "bot_origins_air_smoke", 105, 9000);
                did_work = true;
                break;
            }
            self.bot.is_objective_using = 1;
            self switchtoweaponimmediate("staff_air_zm");
            wait 0.2;
            attempts = 0;
            while(!smoke.solved && attempts < 16 && isalive(self))
            {
                self lookat(aim_point);
                self pressattackbutton(0.12);
                wait 0.18;
                attempts++;
            }
            self.bot.is_objective_using = undefined;
            self clearlookat();
            did_work = true;
            break;
        }
    }

    // ICE 1: expose the current ternary-gem value on the matching ceiling
    // tile. Never shoot a mismatched tile because the stock script resets all.
    if(!flag("ice_puzzle_1_complete") && self hasweapon("staff_water_zm") && isdefined(level.unsolved_tiles))
    {
        ice_gem = getent("ice_chamber_gem", "targetname");
        matching = undefined;
        if(isdefined(ice_gem) && isdefined(ice_gem.value) && ice_gem.value >= 0)
        {
            foreach(tile in level.unsolved_tiles)
            {
                if(isdefined(tile) && isdefined(tile.origin) && isdefined(tile.showing_tile_side) && tile.showing_tile_side &&
                   isdefined(tile.value) && tile.value == ice_gem.value)
                {
                    matching = tile;
                    break;
                }
            }
        }
        if(isdefined(matching))
        {
            before_count = level.unsolved_tiles.size;
            self bot_quest_fire_at(matching.origin, "staff_water_zm", "bot_origins_ice_tile", 720, 1, 0.1);
            wait 0.35;
            if(level.unsolved_tiles.size < before_count)
                did_work = true;
        }
        else if(isdefined(ice_gem) && isdefined(ice_gem.origin))
        {
            self bot_quest_fire_at(ice_gem.origin, "staff_water_zm", "bot_origins_ice_gem", 720, 1, 0.1);
            did_work = true;
        }
    }

    // ICE 2: freeze each stone with the Water Staff, then break it with an
    // ordinary bullet weapon. The native stone script owns the completion flag.
    if(flag("ice_puzzle_1_complete") && !flag("ice_puzzle_2_complete") && self hasweapon("staff_water_zm"))
    {
        stones = getstructarray("puzzle_stone_water", "targetname");
        foreach(stone in stones)
        {
            if(!isdefined(stone) || !isdefined(stone.origin) || !isdefined(stone.e_model) || !isdefined(stone.e_model.origin))
                continue;
            if(distancesquared(self.origin, stone.e_model.origin) > 650 * 650)
            {
                self bot_quest_move_to(stone.e_model.origin, "bot_origins_ice_stone", 170, 9000);
                did_work = true;
                break;
            }
            self bot_quest_fire_at(stone.e_model.origin, "staff_water_zm", "bot_origins_ice_freeze", 720, 1, 0.12);
            wait 0.35;
            primary = self bot_quest_primary_weapon();
            if(isdefined(primary) && isdefined(stone.e_model) && isdefined(stone.e_model.origin))
                self bot_quest_fire_at(stone.e_model.origin, primary, "bot_origins_ice_shatter", 720, 7, 0.1);
            did_work = true;
            break;
        }
    }

    // ELECTRIC 1: play each of the three stock chords in the specified order.
    // Firing the keys with the Lightning Staff produces the piano_key_played events.
    if(!flag("electric_puzzle_1_complete") && self hasweapon("staff_lightning_zm"))
    {
        chord_names = array("a_minor", "e_minor", "d_minor");
        keys = getstructarray("piano_key", "script_noteworthy");
        foreach(chord_name in chord_names)
        {
            chord = getstruct("piano_chord_" + chord_name, "script_noteworthy");
            if(!isdefined(chord) || !isdefined(chord.script_string))
                continue;
            notes = strtok(chord.script_string, " ");
            if(notes.size != 3)
                continue;
            foreach(note in notes)
            {
                chosen_key = undefined;
                foreach(key in keys)
                {
                    if(isdefined(key) && isdefined(key.script_string) && key.script_string == note)
                    {
                        chosen_key = key;
                        break;
                    }
                }
                if(isdefined(chosen_key) && isdefined(chosen_key.origin))
                {
                    self bot_quest_fire_at(chosen_key.origin, "staff_lightning_zm", "bot_origins_piano_key", 720, 1, 0.1);
                    wait 0.16;
                }
            }
            wait 4.4;
            if(flag("electric_puzzle_1_complete"))
                break;
        }
        did_work = true;
    }

    // ELECTRIC 2: route electricity through every relay in the game's actual
    // connection graph. Each use increments the live relay position by one.
    if(flag("electric_puzzle_1_complete") && !flag("electric_puzzle_2_complete"))
    {
        relays = level.electric_relays;
        if(isdefined(relays))
        {
            relay_names = array("elec", "ice", "village", "air", "start", "tank_platform", "ruins");
            desired = array(0, 3, 2, 2, 1, 0, 2);
            for(i = 0; i < relay_names.size && !flag("electric_puzzle_2_complete"); i++)
            {
                relay = relays[relay_names[i]];
                if(!isdefined(relay) || !isdefined(relay.position) || !isdefined(relay.trigger_stub) || !isdefined(relay.trigger_stub.origin))
                    continue;
                attempts = 0;
                while(relay.position != desired[i] && attempts < 4 && !flag("electric_puzzle_2_complete"))
                {
                    before_pos = relay.position;
                    self bot_quest_use_target(relay.trigger_stub, "bot_origins_electric_relay", 54, 1);
                    wait 0.25;
                    if(relay.position == before_pos)
                        break;
                    attempts++;
                }
            }
            did_work = true;
        }
    }

    // FIRE 1: occupy every unfinished sacrifice pad. Squad combat kills in
    // the chamber are counted by the map until each stock volume is satisfied.
    if(!flag("fire_puzzle_1_complete") && self hasweapon("staff_fire_zm") && isdefined(level.sacrifice_volumes))
    {
        foreach(volume in level.sacrifice_volumes)
        {
            if(isdefined(volume) && isdefined(volume.origin) &&
               (!isdefined(volume.b_gods_pleased) || !volume.b_gods_pleased))
            {
                self bot_quest_hold_in_volume(volume.origin, "bot_origins_fire_sacrifice", 170, 3.5);
                did_work = true;
                break;
            }
        }
    }

    // FIRE 2: ignite only correct, still-unlit church torches with the Fire
    // Staff. The stock explosion callback verifies every torch and completes it.
    if(flag("fire_puzzle_1_complete") && !flag("fire_puzzle_2_complete") && self hasweapon("staff_fire_zm"))
    {
        torches = getstructarray("church_torch_target", "script_noteworthy");
        foreach(torch in torches)
        {
            if(isdefined(torch) && isdefined(torch.origin) && isdefined(torch.b_correct_torch) && torch.b_correct_torch &&
               !isdefined(torch.e_fx))
            {
                self bot_quest_fire_at(torch.origin, "staff_fire_zm", "bot_origins_fire_torch", 720, 1, 0.12);
                did_work = true;
                break;
            }
        }
    }

    level.bot_origins_staff_puzzle_owner = undefined;
    level.bot_origins_staff_puzzle_owner_until = 0;
    return did_work;
}

bot_quest_origins_crypt_gems()
{
    if(!isdefined(level.gem_start_pos) || !isdefined(level.a_elemental_staffs) || !flag("chamber_entrance_opened"))
        return false;

    weapon = undefined;
    gem_name = undefined;
    start_name = undefined;
    final_name = undefined;

    if(self hasweapon("staff_fire_zm"))
    {
        weapon = "staff_fire_zm";
        gem_name = "crypt_gem_fire";
        start_name = "fire_orb_exit_path";
        final_name = "fire_orb_plinth_final";
    }
    else if(self hasweapon("staff_air_zm"))
    {
        weapon = "staff_air_zm";
        gem_name = "crypt_gem_air";
        start_name = "air_orb_exit_path";
        final_name = "air_orb_plinth_final";
    }
    else if(self hasweapon("staff_water_zm"))
    {
        weapon = "staff_water_zm";
        gem_name = "crypt_gem_ice";
        start_name = "ice_orb_exit_path";
        final_name = "ice_orb_plinth_final";
    }
    else if(self hasweapon("staff_lightning_zm"))
    {
        weapon = "staff_lightning_zm";
        gem_name = "crypt_gem_elec";
        start_name = "lightning_orb_exit_path";
        final_name = "lightning_orb_plinth_final";
    }

    if(!isdefined(weapon))
        return false;

    complete_flag = "staff_";
    if(gem_name == "crypt_gem_fire")
        complete_flag = "staff_fire_zm_upgrade_unlocked";
    else if(gem_name == "crypt_gem_air")
        complete_flag = "staff_air_zm_upgrade_unlocked";
    else if(gem_name == "crypt_gem_ice")
        complete_flag = "staff_water_zm_upgrade_unlocked";
    else
        complete_flag = "staff_lightning_zm_upgrade_unlocked";

    if(flag(complete_flag))
        return false;

    if(!isdefined(level.bot_origins_crypt_owner) || !isalive(level.bot_origins_crypt_owner) ||
       !isdefined(level.bot_origins_crypt_owner_until) || gettime() > level.bot_origins_crypt_owner_until)
    {
        level.bot_origins_crypt_owner = self;
        level.bot_origins_crypt_owner_until = gettime() + 12000;
    }
    else if(level.bot_origins_crypt_owner != self)
        return false;

    main_disc = getent("crypt_puzzle_disc_main", "targetname");
    start = getstruct(start_name, "targetname");
    final_pos = getstruct(final_name, "targetname");
    if(!isdefined(main_disc) || !isdefined(main_disc.position) || !isdefined(start) || !isdefined(start.origin) ||
       !isdefined(final_pos) || !isdefined(final_pos.origin))
    {
        level.bot_origins_crypt_owner = undefined;
        level.bot_origins_crypt_owner_until = 0;
        return false;
    }

    // The stock worker does not create the orb until the original crystal is
    // hit by its matching elemental staff. Store its exact spawn point and
    // element index before the native script deletes that entity.
    if(!isdefined(level.bot_origins_crypt_gem_pos))
        level.bot_origins_crypt_gem_pos = [];
    if(!isdefined(level.bot_origins_crypt_gem_element))
        level.bot_origins_crypt_gem_element = [];

    gem = getent(gem_name, "targetname");
    if(isdefined(gem) && isdefined(gem.origin) && isdefined(gem.script_int))
    {
        level.bot_origins_crypt_gem_pos[gem_name] = gem.origin;
        level.bot_origins_crypt_gem_element[gem_name] = gem.script_int;
        if(distancesquared(self.origin, gem.origin) > 650 * 650)
        {
            self bot_quest_move_to(gem.origin, "bot_origins_crypt_gem", 150, 9000);
            level.bot_origins_crypt_owner_until = gettime() + 12000;
            return true;
        }

        self bot_quest_fire_at(gem.origin, weapon, "bot_origins_crypt_gem_shot", 720, 1, 0.12);
        level.bot_origins_crypt_owner_until = gettime() + 12000;
        return true;
    }

    // Each gem has a different disc offset. Rotate every outer disc until it
    // matches the live main-disc position plus that element's offset.
    wanted = (main_disc.position + level.gem_start_pos[gem_name]) % 4;
    discs = getentarray("crypt_puzzle_disc", "script_noteworthy");
    foreach(disc in discs)
    {
        if(!isdefined(disc) || !isdefined(disc.position) || !isdefined(disc.target))
            continue;
        if(isdefined(disc.targetname) && disc.targetname == "crypt_puzzle_disc_main")
            continue;
        if(disc.position == wanted)
            continue;

        levers = getentarray(disc.target, "targetname");
        selected_lever = undefined;
        selected_dist = 999999999;
        foreach(lever in levers)
        {
            if(!isdefined(lever) || !isdefined(lever.trigger_stub) || !isdefined(lever.trigger_stub.origin))
                continue;
            d = distancesquared(self.origin, lever.trigger_stub.origin);
            if(d < selected_dist && findpath(self.origin, lever.trigger_stub.origin, undefined, 0, 1))
            {
                selected_lever = lever;
                selected_dist = d;
            }
        }

        if(isdefined(selected_lever))
        {
            attempts = 0;
            while(disc.position != wanted && attempts < 4 && isalive(self))
            {
                before = disc.position;
                self bot_quest_use_target(selected_lever.trigger_stub, "bot_origins_crypt_disc", 72, 1);
                wait 0.3;
                if(disc.position == before)
                    break;
                attempts++;
            }
        }
        if(disc.position != wanted)
        {
            level.bot_origins_crypt_owner = undefined;
            level.bot_origins_crypt_owner_until = 0;
            return false;
        }
    }

    // The stock orb only leaves the Crazy Place while a player looks at its
    // exit-path start for a continuous second. Do that, then fire the matching
    // elemental staff at its actual final crypt plinth.
    if(distancesquared(self.origin, start.origin) > 190 * 190)
    {
        self bot_quest_move_to(start.origin, "bot_origins_crypt_orb_start", 150, 9000);
        level.bot_origins_crypt_owner_until = gettime() + 12000;
        return true;
    }

    self.bot.is_objective_using = 1;
    self lookat(start.origin);
    wait 1.35;
    self clearlookat();
    self.bot.is_objective_using = undefined;

    // The stock orb then traverses the crypt path and waits for the disc
    // alignment. Keep the shared puzzle lock while that state machine runs;
    // another bot rotating the same discs mid-flight would deadlock the orb.
    deadline = gettime() + 30000;
    while(!flag(complete_flag) && gettime() < deadline && isalive(self))
    {
        // Once the aligned orb has descended onto its original chamber plinth,
        // the stock gem worker waits for damage from the matching staff. Find
        // that native orb by the saved position + element index and hit it.
        if(isdefined(level.bot_origins_crypt_gem_pos[gem_name]) &&
           isdefined(level.bot_origins_crypt_gem_element[gem_name]))
        {
            orb_models = getentarray("script_model", "classname");
            foreach(orb in orb_models)
            {
                if(!isdefined(orb) || !isdefined(orb.origin) || !isdefined(orb.script_int) ||
                   orb.script_int != level.bot_origins_crypt_gem_element[gem_name])
                    continue;
                if(distancesquared(orb.origin, level.bot_origins_crypt_gem_pos[gem_name]) > 150 * 150)
                    continue;

                self bot_quest_fire_at(orb.origin, weapon, "bot_origins_crypt_orb_charge", 720, 1, 0.12);
                break;
            }
        }
        wait 0.35;
    }

    level.bot_origins_crypt_owner = undefined;
    level.bot_origins_crypt_owner_until = 0;
    return flag(complete_flag);
}

bot_quest_origins_punch_souls()
{
    if(!self hasweapon("one_inch_punch_zm") ||
       (isdefined(self.n_ee_punch_souls) && self.n_ee_punch_souls >= 20))
        return false;

    center = getstruct("chamber_center", "targetname");
    if(!isdefined(center) || !isdefined(center.origin))
        return false;

    if(!maps\mp\zm_tomb_chamber::is_point_in_chamber(self.origin))
    {
        self bot_quest_move_to(center.origin, "bot_origins_punch_souls", 260, 9000);
        return true;
    }

    self set_player_melee_weapon("one_inch_punch_zm");
    zombies = getaispeciesarray(level.zombie_team, "all");
    target = undefined;
    best_distance = 999999999;
    foreach(zombie in zombies)
    {
        if(!isdefined(zombie) || !isalive(zombie) || !isdefined(zombie.origin) ||
           !is_true(zombie.has_soul) || !is_true(zombie.completed_emerging_into_playable_area) ||
           is_true(zombie.is_mechz))
            continue;
        distance_sq = distancesquared(self.origin, zombie.origin);
        if(distance_sq < best_distance && findpath(self.origin, zombie.origin, undefined, 0, 1))
        {
            best_distance = distance_sq;
            target = zombie;
        }
    }

    if(!isdefined(target))
    {
        self bot_quest_hold_in_volume(center.origin, "bot_origins_punch_souls_wait", 300, 1.5);
        return true;
    }

    if(best_distance > 60 * 60)
    {
        self bot_quest_move_to(target.origin, "bot_origins_punch_soul_target", 48, 5000);
        return true;
    }

    self.bot.is_objective_using = 1;
    self lookat(target.origin + (0, 0, 24));
    self pressmelee();
    wait 0.45;
    self clearlookat();
    self.bot.is_objective_using = undefined;
    return true;
}

bot_quest_origins_main_steps()
{
    // Step 3: activate a real fire-link unitrigger during the three-robot
    // round, then hit the damage target with the Beacon during its window.
    if(flag("three_robot_round") && !flag("ee_mech_zombie_hole_opened"))
    {
        if(!isdefined(level.bot_origins_firelink_next_press) ||
           gettime() >= level.bot_origins_firelink_next_press)
        {
            buttons = getentarray("fire_link_button", "targetname");
            foreach(button in buttons)
            {
                if(isdefined(button) && isdefined(button.origin))
                {
                    self bot_quest_use_target(button, "bot_origins_fire_link", 52, 1);
                    level.bot_origins_firelink_next_press = gettime() + 6000;
                    return true;
                }
            }
        }

        if(self hasweapon("beacon_zm"))
        {
            hole = getent("fire_link_damage", "targetname");
            if(isdefined(hole) && isdefined(hole.origin))
            {
                self bot_quest_fire_at(hole.origin, "beacon_zm", "bot_origins_fire_link_shot", 700, 1, 0.1);
                return true;
            }
        }
        return true;
    }

    // Step 5: the biplane accepts damage only from a player while Zombie Blood
    // is active. Do not waste shots before the power-up is actually running.
    if(!flag("ee_maxis_drone_retrieved") && isdefined(self.zombie_vars) &&
       isdefined(self.zombie_vars["zombie_powerup_zombie_blood_on"]) && self.zombie_vars["zombie_powerup_zombie_blood_on"])
    {
        plane = getent("zombie_blood_biplane", "targetname");
        primary = self bot_quest_primary_weapon();
        if(isdefined(plane) && isdefined(plane.origin) && isdefined(primary))
        {
            self bot_quest_fire_at(plane.origin, primary, "bot_origins_blood_plane", 1500, 10, 0.1);
            return true;
        }
    }

    // The Zombie Blood pilot drops the Maxis drone after the plane is destroyed.
    // The stock unitrigger pickup clears ee_quadrotor_disabled and sets the real
    // ee_maxis_drone_retrieved flag; it is a separate prerequisite for the later
    // Samantha portal sequence.
    if(!flag("ee_maxis_drone_retrieved"))
    {
        quadrotor = getent("quadrotor_pickup", "targetname");
        if(isdefined(quadrotor) && isdefined(quadrotor.origin))
        {
            self bot_quest_use_target(quadrotor, "bot_origins_drone_pickup", 64, 4);
            return true;
        }
    }

    // Step 6: initialize the stock One Inch Punch melee system, collect 20
    // Crazy Place souls, and physically touch the player-specific tablet.
    if(!flag("ee_all_players_upgraded_punch"))
    {
        if(!self hasweapon("one_inch_punch_zm") && !self hasweapon("one_inch_punch_upgraded_zm"))
        {
            if(!isdefined(self.one_inch_punch_flag_has_been_init))
                self thread maps\mp\zombies\_zm_weap_one_inch_punch::one_inch_punch_melee_attack();
        }

        if(self hasweapon("one_inch_punch_zm") || self hasweapon("one_inch_punch_upgraded_zm"))
        {
            if(self hasweapon("one_inch_punch_zm"))
                self set_player_melee_weapon("one_inch_punch_zm");
            else if(self hasweapon("one_inch_punch_upgraded_zm"))
                self set_player_melee_weapon("one_inch_punch_upgraded_zm");

            if(!isdefined(self.n_ee_punch_souls) || self.n_ee_punch_souls < 20)
            {
                if(self bot_quest_origins_punch_souls())
                    return true;
            }

            // The stock quest requires a tablet pickup for every player,
            // including the local host. Once this bot earns the real 20-soul
            // tablet, spawn the same stock pickup for any remaining teammates
            // at their current positions; the original callback marks each
            // player upgraded and sets ee_all_players_upgraded_punch itself.
            if(isdefined(self.n_ee_punch_souls) && self.n_ee_punch_souls >= 20 &&
               !is_true(level.bot_origins_punch_tablets_given))
            {
                level.bot_origins_punch_tablets_given = 1;
                all_players = get_players();
                foreach(punch_player in all_players)
                {
                    if(!isdefined(punch_player) || punch_player == self ||
                       (isdefined(punch_player.b_punch_upgraded) && punch_player.b_punch_upgraded))
                        continue;
                    level thread maps\mp\zm_tomb_ee_main_step_6::spawn_punch_upgrade_tablet(punch_player.origin, punch_player);
                }
            }

            tablets = getentarray("script_model", "classname");
            foreach(tablet in tablets)
            {
                if(!isdefined(tablet) || !isdefined(tablet.origin))
                    continue;
                if((!isdefined(tablet.modelname) || tablet.modelname != "p6_zm_tm_tablet") &&
                   (!isdefined(tablet.model) || tablet.model != "p6_zm_tm_tablet"))
                    continue;
                if(isdefined(tablet.owner) && tablet.owner != self)
                    continue;
                if(isdefined(self.n_ee_punch_souls) && self.n_ee_punch_souls >= 20)
                {
                    self bot_quest_move_to(tablet.origin, "bot_origins_punch_tablet", 32, 10000);
                    return true;
                }
            }
        }
    }

    // Step 7: remain in the Crazy Place while squad kills count toward the
    // 100-soul portal requirement. The map callback, not the bot, increments it.
    if(flag("ee_sam_portal_active") && !flag("ee_souls_absorbed"))
    {
        center = getstruct("chamber_center", "targetname");
        if(isdefined(center) && isdefined(center.origin))
            self bot_quest_hold_in_volume(center.origin, "bot_origins_soul_chamber", 340, 4.0);
        return true;
    }

    // Step 8 portal interaction is handled in bot_quest_origins().
    return false;
}

bot_quest_origins()
{
    if(self bot_quest_origins_staff_puzzles())
        return;
    if(self bot_quest_origins_crypt_gems())
        return;

    // Insert carried elemental staffs into their native charge triggers. Stock
    // quest code counts the nearby zombie kills and creates the upgraded pickup.
    if(isdefined(level.a_elemental_staffs))
    {
        foreach(staff in level.a_elemental_staffs)
        {
            if(!isdefined(staff) || !isdefined(staff.weapname) || !self hasweapon(staff.weapname))
                continue;

            if(isdefined(staff.charger) && isdefined(staff.charger.is_inserted) && staff.charger.is_inserted)
                continue;

            if(isdefined(staff.charge_trigger) && isdefined(staff.charge_trigger.origin))
            {
                self bot_quest_use_target(staff.charge_trigger, "bot_origins_staff_charge", 72, 4);
                return;
            }
        }
    }

    // Recover upgraded staffs once their stock pickup trigger is enabled.
    if(isdefined(level.a_elemental_staffs_upgraded))
    {
        foreach(staff_upgraded in level.a_elemental_staffs_upgraded)
        {
            if(!isdefined(staff_upgraded) || !isdefined(staff_upgraded.weapname) ||
               self hasweapon(staff_upgraded.weapname))
                continue;

            if(isdefined(staff_upgraded.trigger) && isdefined(staff_upgraded.trigger.origin))
            {
                self bot_quest_use_target(staff_upgraded.trigger, "bot_origins_staff_pickup", 64, 4);
                return;
            }
        }
    }

    // Step two of Little Lost Girl: put each upgraded staff into its matching
    // robot-head plinth. The stock trigger checks the actual weapon name.
    if(flag("ee_all_staffs_upgraded") && !flag("ee_all_staffs_placed"))
    {
        head_stubs = getstructarray("robot_head_staff", "targetname");
        foreach(head in head_stubs)
        {
            if(!isdefined(head) || !isdefined(head.script_noteworthy) || !isdefined(head.m_plinth))
                continue;

            weapon_name = "staff_" + head.script_noteworthy + "_upgraded_zm";
            if(self hasweapon(weapon_name) &&
               (!isdefined(head.m_plinth.m_staff) || !isdefined(head.m_plinth.m_staff.origin)))
            {
                self bot_quest_use_target(head, "bot_origins_staff_plinth", 64, 5);
                return;
            }
        }
    }

    if(self bot_quest_origins_main_steps())
        return;

    // Last step: use the real portal trigger once the map has activated it.
    if(flag("ee_souls_absorbed") && flag("ee_quadrotor_disabled") && !flag("ee_samantha_released"))
    {
        final_portal = getstruct("player_portal_final", "targetname");
        if(isdefined(final_portal) && isdefined(final_portal.origin))
        {
            point = spawnstruct();
            point.origin = final_portal.origin;
            self bot_quest_use_target(point, "bot_origins_final_portal", 80, 5);
        }
    }
}
bot_origins_grant_shield(current_weapon)
{
	self bot_grant_map_shield("tomb_shield_zm", current_weapon);
}

