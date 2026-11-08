// -----------------------------------------------------------------------------
// TranZit map-specific bot logic (zm_transit).
// Shared bot systems and generic quest helpers remain in zm_bo2_bots.gsc.
// Edit this file for behavior that belongs only to this map.
// -----------------------------------------------------------------------------

bot_quest_tranzit_emp()
{
    if(!isdefined(level.sq_progress))
        return false;

    route = getdvar("zm_bot_quest_route");
    if(!isdefined(route) || route == "")
        route = "maxis";

    // Maxis B is NOT an EMP step. The stock quest waits for the Avogadro to
    // be stunned while touching the tower volume by the two powered turbines
    // placed in Maxis A. Stay at the tower to attract it; never waste an EMP.
    if(route == "maxis" && isdefined(level.sq_progress["maxis"]) &&
       isdefined(level.sq_progress["maxis"]["A_complete"]) && level.sq_progress["maxis"]["A_complete"] &&
       (!isdefined(level.sq_progress["maxis"]["B_complete"]) || !level.sq_progress["maxis"]["B_complete"]) &&
       isdefined(level.sq_volume) && isdefined(level.sq_volume.origin))
    {
        a1 = isdefined(level.sq_progress["maxis"]["A_turbine_1"]) && isdefined(level.sq_progress["maxis"]["A_turbine_1"].powered) && level.sq_progress["maxis"]["A_turbine_1"].powered;
        a2 = isdefined(level.sq_progress["maxis"]["A_turbine_2"]) && isdefined(level.sq_progress["maxis"]["A_turbine_2"].powered) && level.sq_progress["maxis"]["A_turbine_2"].powered;
        if(a1 && a2 && isdefined(level.avogadro) && isdefined(level.avogadro.origin) &&
           !level.avogadro istouching(level.sq_volume))
        {
            self bot_quest_move_to(level.sq_volume.origin, "bot_tranzit_maxis_avogadro", 160, 6500);
            return true;
        }
        return false;
    }

    // Richtofen C: the native safety-light handler listens for real EMP
    // detonations in four different screecher-light zones after A and B.
    if(route == "richtofen" && isdefined(level.sq_progress["rich"]) &&
       isdefined(level.sq_progress["rich"]["A_complete"]) && level.sq_progress["rich"]["A_complete"] &&
       isdefined(level.sq_progress["rich"]["B_complete"]) && level.sq_progress["rich"]["B_complete"] &&
       (!isdefined(level.sq_progress["rich"]["C_complete"]) || !level.sq_progress["rich"]["C_complete"]) &&
       self hasweapon("emp_grenade_zm"))
    {
        lights = getstructarray("screecher_escape", "targetname");
        foreach(light in lights)
        {
            if(!isdefined(light) || !isdefined(light.origin))
                continue;
            already_done = 0;
            if(isdefined(level.sq_richtofen_c_screecher_lights))
            {
                foreach(done_light in level.sq_richtofen_c_screecher_lights)
                {
                    if(done_light == light)
                        already_done = 1;
                }
            }
            if(already_done)
                continue;
            if(self bot_quest_move_to(light.origin, "bot_tranzit_emp_light", 150, 8000))
            {
                self.bot.is_objective_using = 1;
                self switchtoweaponimmediate("emp_grenade_zm");
                wait 0.2;
                self lookat(light.origin);
                self forcegrenadethrow();
                wait 1.1;
                self clearlookat();
                self.bot.is_objective_using = undefined;
                return true;
            }
        }
    }
    return false;
}

bot_quest_tranzit()
{
    route = getdvar("zm_bot_quest_route");
    if(!isdefined(route) || route == "")
        route = "maxis";

    if(!isdefined(level.sq_volume) || !isdefined(level.sq_volume.origin))
        return;

    if(self bot_quest_tranzit_emp())
        return;

    if(route == "richtofen")
    {
        // Richtofen's Jet Gun tower stage requires it to overheat while its
        // owner remains inside the scripted tower volume.
        if(self hasweapon("jetgun_zm") && isdefined(level.sq_progress) &&
           isdefined(level.sq_progress["rich"]) &&
           (!isdefined(level.sq_progress["rich"]["A_jetgun_tower"]) || !level.sq_progress["rich"]["A_jetgun_tower"]))
        {
            if(self bot_quest_move_to(level.sq_volume.origin, "bot_tranzit_jetgun_tower", 180, 12000))
            {
                self.bot.is_objective_using = 1;
                self switchtoweaponimmediate("jetgun_zm");
                deadline = gettime() + 12000;
                while(gettime() < deadline && isdefined(self.jetgun_heatval) && self.jetgun_heatval < 1)
                {
                    self lookat(level.sq_volume.origin + (0, 0, 32));
                    self pressattackbutton(0.2);
                    wait 0.15;
                }
                self.bot.is_objective_using = undefined;
                self clearlookat();
            }
            return;
        }

        // When the tower kill counter is active, keep bots inside the volume;
        // their normal combat loop performs the zombie kills there.
        if(isdefined(level.sq_progress) && isdefined(level.sq_progress["rich"]) &&
           isdefined(level.sq_progress["rich"]["A_complete"]) && level.sq_progress["rich"]["A_complete"] &&
           isdefined(level.sq_progress["rich"]["B_zombies_tower"]) && level.sq_progress["rich"]["B_zombies_tower"] > 0)
            self bot_quest_move_to(level.sq_volume.origin, "bot_tranzit_jetgun_kills", 200, 5000);

        return;
    }

    if(!isdefined(level.sq_progress) || !isdefined(level.sq_progress["maxis"]))
        return;

    // Maxis A: place two live turbines inside the tower volume. Existing
    // buildable workers acquire the turbine; this worker deploys it at the
    // actual quest volume so the stock power watchers can see it.
    a1 = isdefined(level.sq_progress["maxis"]["A_turbine_1"]);
    a2 = isdefined(level.sq_progress["maxis"]["A_turbine_2"]);

    if((!a1 || !a2) && self has_player_equipment("equip_turbine_zm") &&
       (!isdefined(self.buildableturbine) || !isdefined(self.buildableturbine.origin)))
    {
        offset = (0, 0, 0);
        if(a1)
            offset = (120, 0, 0);
        self bot_quest_deploy_equipment("equip_turbine_zm", level.sq_volume.origin + offset, "bot_tranzit_maxis_turbine_a");
        return;
    }

    // Maxis C: the two turbines must occupy different Screecher safety-light
    // zones. Only deploy when the stock branch has reached this stage.
    if(isdefined(level.sq_progress["maxis"]["A_complete"]) && level.sq_progress["maxis"]["A_complete"] &&
       isdefined(level.sq_progress["maxis"]["B_complete"]) && level.sq_progress["maxis"]["B_complete"] &&
       (!isdefined(level.sq_progress["maxis"]["C_complete"]) || !level.sq_progress["maxis"]["C_complete"]) &&
       self has_player_equipment("equip_turbine_zm") &&
       (!isdefined(self.buildableturbine) || !isdefined(self.buildableturbine.origin)))
    {
        zones = getstructarray("screecher_escape", "targetname");
        foreach(zone in zones)
        {
            if(!isdefined(zone) || !isdefined(zone.origin))
                continue;

            used_zone = 0;
            if(isdefined(level.sq_progress["maxis"]["C_screecher_1"]) &&
               level.sq_progress["maxis"]["C_screecher_1"] == zone)
                used_zone = 1;
            if(isdefined(level.sq_progress["maxis"]["C_screecher_2"]) &&
               level.sq_progress["maxis"]["C_screecher_2"] == zone)
                used_zone = 1;

            if(!used_zone && findpath(self.origin, zone.origin, undefined, 0, 1))
            {
                self bot_quest_deploy_equipment("equip_turbine_zm", zone.origin, "bot_tranzit_maxis_screecher_turbine");
                return;
            }
        }
    }
}
bot_tranzit_grant_shield(current_weapon)
{
	self bot_grant_map_shield("riotshield_zm", current_weapon);
}

