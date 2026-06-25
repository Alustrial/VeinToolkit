-- They Multiply - when a zombie dies, two more rise near it.
--
-- This is a whole gameplay MECHANIC built from three verbs:
--   veincf.world.on        - the trigger (run code when a zombie dies)
--   veincf.actor.location  - read where it died
--   veincf.world.spawn     - make new ones there (body + AI, ready to fight)
--
-- The framework gives you the verbs; the mechanic is yours. That's the whole idea.
--
-- NOTE: this multiplies without limit on purpose (it's a demo). A real mod would
-- cap the population - e.g. stop spawning once FindAllOf("BP_Zombie_C") passes N.

veincf.world.on("BP_Zombie_C", "OnDeath", function(dead)
    local loc = veincf.actor.location(dead)
    if not loc then return end
    for i = 1, 2 do
        veincf.world.spawn("BP_Zombie_C", { x = loc.x + i * 150, y = loc.y, z = loc.z + 50 })
    end
end)
