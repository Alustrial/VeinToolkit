-- Death Message - the simplest scripting example.
--
-- veincf.world.on(class, "Event", callback) runs YOUR code on a game event.
-- Here: when the player dies, log a line. (Swap the class for "BP_Zombie_C"
-- to fire on zombie deaths instead - the callback gets the thing that died.)
--
-- This whole mod is one folder: this script + manifest.json. No pak, no Unreal.

veincf.world.on("BP_VeinPlayerCharacter_C", "OnDeath", function(who)
    veincf.log.info("You died. noob.")
end)
