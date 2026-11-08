// ============================================================================
//  ULTIMATE ZM MOD MENU - MAP-WIDE PARTS ESP
//  Included by zm_modmenu.gsc. Supports the stock Zombies craftable and
//  buildable registries used by Origins, Mob, TranZit, Die Rise and Buried.
// ============================================================================

MM_TogglePartsESP()
{
    self MM_Toggle("partesp", "Parts ESP", ::MM_PartsESPLoop);
}

// Return currently spawned part models from the stock game registries.
// This deliberately uses the game's own piece objects instead of guessing
// model names or drawing markers at hard-coded coordinates.
MM_CollectMapPartModels()
{
    models = [];

    if(isDefined(level.zombie_include_craftables))
    {
        foreach(craftable in level.zombie_include_craftables)
        {
            if(!isDefined(craftable) || !isDefined(craftable.a_piecestubs))
                continue;

            foreach(piecestub in craftable.a_piecestubs)
            {
                if(!isDefined(piecestub) || !isDefined(piecestub.piecespawn))
                    continue;
                if(!isDefined(piecestub.piecespawn.model))
                    continue;

                model = piecestub.piecespawn.model;
                if(!isDefined(model.origin))
                    continue;

                duplicate = false;
                foreach(existing in models)
                {
                    if(existing == model)
                    {
                        duplicate = true;
                        break;
                    }
                }
                if(!duplicate)
                    models[models.size] = model;
            }
        }
    }

    if(isDefined(level.zombie_buildables))
    {
        foreach(buildable in level.zombie_buildables)
        {
            if(!isDefined(buildable) || !isDefined(buildable.buildablepieces))
                continue;

            foreach(piece in buildable.buildablepieces)
            {
                if(!isDefined(piece) || !isDefined(piece.model))
                    continue;
                if(!isDefined(piece.model.origin))
                    continue;

                duplicate = false;
                foreach(existing in models)
                {
                    if(existing == piece.model)
                    {
                        duplicate = true;
                        break;
                    }
                }
                if(!duplicate)
                    models[models.size] = piece.model;
            }
        }
    }

    return models;
}

MM_CreatePartESPDot()
{
    hud = newClientHudElem(self);
    hud.archived = 1;
    hud.foreground = false;
    hud.hideWhenInMenu = true;
    hud.sort = 1;
    hud.alpha = 0;
    hud.color = (0.0, 1.0, 1.0);
    hud setShader("white", 5, 5);
    hud setWaypoint(true, "white");
    return hud;
}

MM_PartsESPLoop()
{
    self endon("disconnect");

    // If the user switches the toggle off and on before cleanup runs, the
    // existing loop remains responsible for its HUD pool instead of spawning
    // a second one.
    if(isDefined(self.mmPartsESPActive) && self.mmPartsESPActive)
        return;

    self.mmPartsESPActive = true;
    maxDots = 24;
    huds = [];
    for(i = 0; i < maxDots; i++)
        huds[i] = self MM_CreatePartESPDot();

    self.mmPartsESPHuds = huds;

    for(;;)
    {
        if(!self MM_IsOn("partesp"))
            break;

        parts = self MM_CollectMapPartModels();
        used = [];

        // Display the nearest 24 registered pieces, updating live as pieces
        // spawn, are picked up, are built, or are moved by map logic.
        for(slot = 0; slot < maxDots; slot++)
        {
            bestIdx = -1;
            bestDistance = 999999999;

            foreach(idx, model in parts)
            {
                if(isDefined(used[idx]))
                    continue;
                if(!isDefined(model) || !isDefined(model.origin))
                    continue;

                distanceNow = distancesquared(self.origin, model.origin);
                if(distanceNow < bestDistance)
                {
                    bestDistance = distanceNow;
                    bestIdx = idx;
                }
            }

            if(bestIdx < 0)
            {
                huds[slot].alpha = 0;
                continue;
            }

            used[bestIdx] = true;
            part = parts[bestIdx];
            if(!isDefined(part) || !isDefined(part.origin))
            {
                huds[slot].alpha = 0;
                continue;
            }

            markerPos = part.origin + (0, 0, 18);
            huds[slot].x = markerPos[0];
            huds[slot].y = markerPos[1];
            huds[slot].z = markerPos[2];
            huds[slot].alpha = 1;
        }

        wait 0.15;
    }

    foreach(hud in huds)
    {
        if(isDefined(hud))
            hud destroy();
    }

    self.mmPartsESPHuds = [];
    self.mmPartsESPActive = false;
}
