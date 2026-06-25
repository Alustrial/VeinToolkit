------------------------------------------------------------
-- VeinCF :: mechanics
-- Reflected gameplay verbs exposed as the clean modder API (veincf.player.* / veincf.world.*).
-- The game exposes these as UFunctions (CheatManager + components), so NO native resolution
-- or hooks are needed.
--
-- ★ CRASH-SAFETY RULE: a wrapper must NEVER pass nil to a UFunction arg. The only AV we ever
-- hit was nil → object-param → engine deref'd null. Passing a NUMBER where an object is wanted
-- is rejected CLEANLY by UE4SS (caught by pcall) — no crash. So: validate args, pass numbers or
-- RESOLVED objects, never nil, pcall everything. A wrong guess then fails cleanly, never AVs.
-- (SetCondition still excluded until its object arg is safely resolvable. SPAWN is now SAFE +
-- exposed: `M.spawn`/`M.brood` use SpawnActorAtLocation + SpawnDefaultController with a RESOLVED
-- class object — no AV. Proven 2026-06-23, see docs/mechanics-reflection.md.)
--
-- Require as: require("modules.mechanics")  ->  veincf.player.* / veincf.world.*
------------------------------------------------------------
local log = require("modules.log")

local M = {}

local function cm()
    local c
    pcall(function() c = (FindAllOf("BP_VeinCheatManager_C") or {})[1] or (FindAllOf("CheatManager") or {})[1] end)
    return c
end
local function pc() return (FindAllOf("BP_VeinPlayerCharacter_C") or {})[1] end
local function isnum(v) return type(v) == "number" end

-- resolve an item arg to a class OBJECT (so we never pass a raw string/nil to an object param).
-- accepts an already-resolved object, a "BP_X_C" class name, or a full object path.
local function resolve_class(item)
    if type(item) == "userdata" then return item end
    if type(item) == "string" then
        local c
        pcall(function() c = FindObject("BlueprintGeneratedClass", item) end)
        if not c then pcall(function() c = StaticFindObject(item) end) end
        return c
    end
    return nil
end

-- call CheatManager:Verb(...) safely. fn does the actual call; returns ok(boolean).
local function cmcall(fn)
    local c = cm(); if not c then return false, "no CheatManager" end
    return (pcall(fn, c))
end

-- ⚠ Build an FName USERDATA from a string. UE4SS's NameProperty param marshaller
-- (push_nameproperty, LuaUObject.cpp:1668, Operation::Set) does get_userdata<FName>() — it REQUIRES
-- an FName userdata, NOT a raw string. Passing a string AVs (reads null+0x70, pcall can't catch it).
-- So EVERY Name-arg verb must pass fname(s), never the raw string. Mirrors recipes.lua mk_fname.
local _UEH_ok, _UEH = pcall(require, "UEHelpers")
local function fname(s)
    local n
    if _UEH_ok and _UEH and _UEH.FindOrAddFName then pcall(function() n = _UEH.FindOrAddFName(s) end) end
    if not n then pcall(function() n = FName(s) end) end
    return n
end

-- ── reads ──────────────────────────────────────────────
function M.get_health()
    local p = pc(); if not p then return nil end
    local v; if pcall(function() v = p:GetHealth().Health end) and isnum(v) then return v end
    return nil
end

-- ── player verbs (0-arg / numeric — crash-safe) ────────
function M.heal()                       return cmcall(function(c) c:Heal() end) end
function M.heal_everyone()              return cmcall(function(c) c:HealEveryone() end) end
function M.damage(amount)               if not (isnum(amount) and amount >= 0) then return false, "amount must be number>=0" end return cmcall(function(c) c:DamageSelf(amount) end) end
function M.damage_consciousness(amount) if not isnum(amount) then return false, "number required" end return cmcall(function(c) c:DamageConsciousness(amount) end) end
function M.damage_target(amount)        if not isnum(amount) then return false, "number required" end return cmcall(function(c) c:DamageTarget(amount) end) end
function M.set_item_damage(v)           if not isnum(v) then return false, "number required" end return cmcall(function(c) c:SetItemDamage(v) end) end
function M.set_vehicle_damage(v)        if not isnum(v) then return false, "number required" end return cmcall(function(c) c:SetVehicleDamage(v) end) end
function M.give_key()                   return cmcall(function(c) c:GiveKey() end) end
function M.give_ammo(n)                 if not isnum(n) then return false, "number required" end return cmcall(function(c) c:GiveAmmo(n) end) end

-- CONTRACT CRACKED (2026-06-24 sig-dump): GiveItem(ID:Name, Count:Int) — an item NAME (FName, not a
-- class), + count. A Lua string marshals to FName cleanly. `name` = the item id (e.g. "BP_Apple"); a
-- wrong name fails cleanly (no AV). count defaults to 1.
function M.give_item(name, count)
    if type(name) ~= "string" then return false, "give_item(name:string, count:number)" end
    local id = fname(name); if not id then return false, "give_item: FName build failed" end
    local n = isnum(count) and count or 1
    return cmcall(function(c) c:GiveItem(id, n) end)
end

-- ── world verbs ────────────────────────────────────────
function M.spawn_horde(intensity)       local n = isnum(intensity) and intensity or 1 return cmcall(function(c) c:SpawnHorde(n) end) end
function M.spawn_flyby()                return cmcall(function(c) c:SpawnFlyby() end) end

-- ── functional spawn + brood mechanic (menu-free; SpawnActor + SpawnDefaultController) ──
-- Proven 2026-06-23 (docs/mechanics-reflection.md). Crash-safe: class resolved to an object,
-- pcall everything, never pass nil to an object param.
local function isfunc(v) return type(v) == "function" end

-- death check: despawned (IsValid=false) OR the actor's own IsDead() UFunction (authoritative,
-- present on player+zombie) OR LimbHealthComponent.Health <= 0 (fallback).
local function is_dead(z)
    if not (z and z.IsValid and z:IsValid()) then return true end
    local dead; pcall(function() dead = z:IsDead() end)
    if type(dead) == "boolean" then return dead end
    local hp; pcall(function() hp = z.Health.Health end)
    if isnum(hp) and hp <= 0 then return true end
    return false
end
M.is_dead = is_dead

--- Spawn a FUNCTIONAL actor (body + AI). class = class object | "BP_X_C" name | object path.
--- opts = { near=<actor>, x=,y=,z=, scale=<num>, ai=<bool, default true> }
--- @return UObject|nil actor, string|nil err
function M.spawn(class, opts)
    opts = opts or {}
    local cls = resolve_class(class)
    if not cls then return nil, "spawn: could not resolve class '" .. tostring(class) .. "'" end
    if type(SpawnActorAtLocation) ~= "function" then return nil, "spawn: SpawnActorAtLocation missing (DLL)" end
    local ctx = pc() or (FindAllOf("Pawn") or {})[1]
    if not ctx then return nil, "spawn: no world context (enter a world)" end
    local x, y, z = opts.x, opts.y, opts.z
    if not (isnum(x) and isnum(y) and isnum(z)) then
        local anchor = opts.near or ctx
        if not pcall(function() local l = anchor:K2_GetActorLocation(); x, y, z = l.X, l.Y, l.Z + 50 end) then
            return nil, "spawn: could not read anchor location"
        end
    end
    local res; if not (pcall(function() res = SpawnActorAtLocation(ctx, cls, x, y, z) end) and res and res.actor) then
        return nil, "spawn: SpawnActorAtLocation failed"
    end
    local path = tostring(res.actor):match("^%S+%s+(.+)$") or tostring(res.actor)
    local obj; pcall(function() obj = StaticFindObject(path) end)
    if not (obj and obj:IsValid()) then return nil, "spawn: spawned actor not resolvable" end
    if opts.ai ~= false then pcall(function() obj:SpawnDefaultController() end) end   -- body -> body+brain
    if isnum(opts.scale) then pcall(function() obj:SetActorScale3D({ X = opts.scale, Y = opts.scale, Z = opts.scale }) end) end
    return obj
end

--- Give an existing pawn its default AI controller (spawns AIControllerClass + possesses).
function M.give_ai(actor)
    if not (actor and actor.IsValid and actor:IsValid()) then return false, "give_ai: invalid actor" end
    return (pcall(function() actor:SpawnDefaultController() end))
end

--- Read a unit's current health (e.g. LimbHealthComponent.Health). @return number|nil
function M.get_health_of(actor)
    if not (actor and actor.IsValid and actor:IsValid()) then return nil end
    local hp; pcall(function() hp = actor.Health.Health end)
    return isnum(hp) and hp or nil
end

--- Destroy / despawn an actor.
function M.destroy(actor)
    if not (actor and actor.IsValid and actor:IsValid()) then return false end
    return (pcall(function() actor:K2_DestroyActor() end))
end

--- All live instances of a class name. @return table (array of objects, never nil)
function M.find(className)
    local t; pcall(function() t = FindAllOf(className) end)
    return t or {}
end

--- Resolve a class object by "BP_X_C" name or object path. @return UClass|nil
function M.find_class(name) return resolve_class(name) end

-- ── actor transform / state helpers ────────────────────
--- @return {x,y,z}|nil
function M.location(actor)
    if not (actor and actor.IsValid and actor:IsValid()) then return nil end
    local p; if pcall(function() local l = actor:K2_GetActorLocation(); p = { x = l.X, y = l.Y, z = l.Z } end) then return p end
    return nil
end
function M.set_location(actor, x, y, z)
    if not (actor and actor.IsValid and actor:IsValid()) then return false, "invalid actor" end
    if not (isnum(x) and isnum(y) and isnum(z)) then return false, "x,y,z required" end
    return (pcall(function() actor:K2_SetActorLocation({ X = x, Y = y, Z = z }, false, {}, false) end))
end
function M.set_scale(actor, s)
    if not (actor and actor.IsValid and actor:IsValid()) then return false, "invalid actor" end
    if not isnum(s) then return false, "scale must be a number" end
    return (pcall(function() actor:SetActorScale3D({ X = s, Y = s, Z = s }) end))
end
--- Distance between two actors (or actor and {x,y,z}). @return number|nil
function M.distance(a, b)
    local la = M.location(a) or (type(a) == "table" and a) or nil
    local lb = M.location(b) or (type(b) == "table" and b) or nil
    if not (la and lb) then return nil end
    local dx = (la.x or la.X) - (lb.x or lb.X)
    local dy = (la.y or la.Y) - (lb.y or lb.Y)
    local dz = (la.z or la.Z) - (lb.z or lb.Z)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- The local player pawn. @return UObject|nil
function M.player()
    local p; pcall(function() p = pc() end)
    if p and p:IsValid() then return p end
    p = (FindAllOf("Pawn") or {})[1]
    return (p and p:IsValid()) and p or nil
end

-- ── timers (Delayed Action System wrappers; survive Ctrl+R, cancelable) ──
--- Run fn() every `ms` on the game thread until fn returns true (or errors). @return handle|nil
function M.loop(ms, fn)
    if not (isnum(ms) and isfunc(fn)) then return nil, "loop(ms:number, fn:function)" end
    if type(LoopInGameThreadWithDelay) ~= "function" then return nil, "timer missing (DLL)" end
    local h
    pcall(function()
        h = LoopInGameThreadWithDelay(ms, function()
            local ok, stop = pcall(fn)
            return (not ok) or (stop == true)   -- stop on modder error OR explicit true
        end)
    end)
    return h
end
--- Run fn() once after `ms` on the game thread. @return handle|nil
function M.after(ms, fn)
    if not (isnum(ms) and isfunc(fn)) then return nil, "after(ms:number, fn:function)" end
    if type(ExecuteInGameThreadWithDelay) ~= "function" then return nil, "timer missing (DLL)" end
    local h; pcall(function() h = ExecuteInGameThreadWithDelay(ms, function() pcall(fn) end) end)
    return h
end
function M.cancel(handle)
    if handle and type(CancelDelayedAction) == "function" then return (pcall(CancelDelayedAction, handle)) end
    return false
end

-- ── batch-wrapped verbs (signatures verified 2026-06-24 via DumpFunctionParams) ──
-- Crash-safe. ⚠ FName args MUST be built as an FName userdata via fname() — UE4SS's NameProperty
-- marshaller AVs on a raw string (LuaUObject.cpp:1668). Numbers/0-arg are safe. (Struct-arg
-- inventory verbs deferred — need a DLL struct builder.)
-- give / progress (CheatManager)
function M.give_item_list(name)  if type(name) ~= "string" then return false, "name:string" end local id = fname(name); if not id then return false, "FName failed" end return cmcall(function(c) c:GiveItemList(id) end) end
function M.give_every_item()     return cmcall(function(c) c:GiveEveryItem() end) end
function M.add_xp(stat, xp)      if type(stat) ~= "string" or not isnum(xp) then return false, "add_xp(stat:string, xp:number)" end local id = fname(stat); if not id then return false, "FName failed" end return cmcall(function(c) c:AddXP(id, xp) end) end
function M.add_perk(name)        if type(name) ~= "string" then return false, "name:string" end local id = fname(name); if not id then return false, "FName failed" end return cmcall(function(c) c:AddPerk(id) end) end
function M.power_up()            return cmcall(function(c) c:PowerUp() end) end
-- condition / status (CheatManager)
function M.set_condition(name, amount) if type(name) ~= "string" or not isnum(amount) then return false, "set_condition(name:string, amount:number)" end local id = fname(name); if not id then return false, "FName failed" end return cmcall(function(c) c:SetCondition(id, amount) end) end
function M.ignite_target(duration)     if not isnum(duration) then return false, "duration:number" end return cmcall(function(c) c:IgniteTarget(duration) end) end
function M.zombify()                   return cmcall(function(c) c:Zombify() end) end
-- teleport / movement (CheatManager) — TargetId = FName; VectorString = FString (raw string ok)
function M.teleport_to(targetId)     if type(targetId) ~= "string" then return false, "targetId:string" end local id = fname(targetId); if not id then return false, "FName failed" end return cmcall(function(c) c:TeleportTo(id) end) end
function M.teleport_all_to(targetId) if type(targetId) ~= "string" then return false, "targetId:string" end local id = fname(targetId); if not id then return false, "FName failed" end return cmcall(function(c) c:TeleportAllTo(id) end) end
function M.bring_all_to_me()         return cmcall(function(c) c:BringAllToMe() end) end
function M.goto_vec(vstr)            if type(vstr) ~= "string" then return false, "vectorString:string" end return cmcall(function(c) c:Goto(vstr) end) end
-- world / event (CheatManager)
function M.explosion()           return cmcall(function(c) c:CreateExplosion() end) end
function M.set_weather(preset)   if type(preset) ~= "string" then return false, "preset:string" end local id = fname(preset); if not id then return false, "FName failed" end return cmcall(function(c) c:SetWeather(id) end) end
function M.add_time(seconds)     if not isnum(seconds) then return false, "seconds:number" end return cmcall(function(c) c:AddTime(seconds) end) end
function M.remove_ai()           return cmcall(function(c) c:RemoveAI() end) end
-- player reads (return the relevant component/object; nil-safe)
local function pread(getter)
    local p = pc(); if not p then return nil end
    local v; if pcall(function() v = p[getter](p) end) then return v end
    return nil
end
function M.get_conditions()  return pread("GetConditions") end
function M.get_stats()       return pread("GetStats") end
function M.get_inventory()   return pread("GetInventory") end
function M.get_temperature() return pread("GetTemperature") end

-- ── inventory (class-based; sig+live-verified 2026-06-24). The bag = pc():GetInventory().
-- ContainsItemOfClass/RemoveAmountOfItems take a CLASS (no struct) — pure reflection, crash-safe.
-- (Instance/ID-specific ops, e.g. drop a SPECIFIC item, deferred — the item ID is a {Data=int} struct,
-- table-buildable, but enumeration/identity is fiddlier; class-verbs cover the common cases.)
local function pc_inv()
    local p = pc(); if not p then return nil end
    local inv; pcall(function() inv = p:GetInventory() end)
    return (inv and inv:IsValid()) and inv or nil
end
function M.has_item(itemClass)
    local cls = resolve_class(itemClass); if not cls then return nil, "has_item: class unresolved '" .. tostring(itemClass) .. "'" end
    local inv = pc_inv(); if not inv then return nil, "no inventory" end
    local r; if pcall(function() r = inv:ContainsItemOfClass(cls) end) then return r end
    return nil
end
function M.remove_amount(itemClass, count)
    local cls = resolve_class(itemClass); if not cls then return false, "remove_amount: class unresolved" end
    if not isnum(count) then return false, "remove_amount(class, count:number)" end
    local inv = pc_inv(); if not inv then return false, "no inventory" end
    local r; if pcall(function() r = inv:RemoveAmountOfItems(cls, count, false) end) then return r ~= false end
    return false
end

-- ── event hooks (the TRIGGER primitive — RegisterHook over a UFunction) ──
-- on(className, funcName, callback): hook a class's UFunction. callback(self_obj, ...) gets the firing
-- object (already :get()'d) + passthrough RemoteUnrealParam args. Returns a handle for off().
-- ⚠ The UFunction must be IN MEMORY (class loaded) to hook — we resolve the full path from a LIVE
-- instance's leaf class. A function declared on a NATIVE PARENT: pass that parent's class name.
-- Delegates (OnX__DelegateSignature) are NOT hookable (UE4SS limit). BP funcs hook POST only.
_G.__veincf_hooks = _G.__veincf_hooks or {}   -- persists across Ctrl+R so re-register doesn't stack
local _hooks = _G.__veincf_hooks
function M.off(handle)
    if not (handle and handle.path) then return false end
    if type(UnregisterHook) == "function" then pcall(function() UnregisterHook(handle.path, handle.preId, handle.postId) end) end
    _hooks[handle.path] = nil
    return true
end
function M.on(className, funcName, callback)
    if type(funcName) ~= "string" or not isfunc(callback) then return nil, "on(class, funcName:string, callback:function)" end
    if type(RegisterHook) ~= "function" then return nil, "RegisterHook missing (DLL)" end
    local inst = (FindAllOf(className) or {})[1]
    if not (inst and inst:IsValid()) then return nil, "no live " .. tostring(className) .. " (function must be in memory to hook)" end
    local targetCls; pcall(function() targetCls = inst:GetClass() end)
    -- class-filtered wrapper: the function may be declared on a shared PARENT, so only fire the
    -- modder's callback for instances of the REQUESTED class.
    local wrapped = function(ctx, ...)
        local self_obj; pcall(function() self_obj = ctx:get() end)
        if not self_obj then return end
        local match = true
        if targetCls then pcall(function() match = self_obj:IsA(targetCls) end) end
        if match then pcall(callback, self_obj, ...) end
    end
    -- walk the class chain (GetSuperStruct); try <classpath>:funcName at each level until RegisterHook
    -- resolves (the level that actually DECLARES the function). RegisterHook fails cleanly on a miss.
    local cls, tried, guard = targetCls, 0, 0
    while cls and guard < 24 do
        guard = guard + 1
        local full; pcall(function() full = cls:GetFullName() end)
        if full then
            local path = (full:match("^%S+%s+(.+)$") or full) .. ":" .. funcName
            tried = tried + 1
            if _hooks[path] then M.off(_hooks[path]) end   -- replace prior (Ctrl+R-safe)
            local preId, postId
            local ok = pcall(function() preId, postId = RegisterHook(path, wrapped) end)
            if ok and preId then
                local handle = { path = path, preId = preId, postId = postId }
                _hooks[path] = handle
                return handle
            end
        end
        local nxt; pcall(function() nxt = cls:GetSuperStruct() end)
        cls = nxt
    end
    return nil, "no class in the chain declares '" .. funcName .. "' (tried " .. tried .. " levels)"
end

return M
