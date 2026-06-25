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

-- resolve a WIDGET class: widget classes are WidgetBlueprintGeneratedClass (NOT BlueprintGeneratedClass);
-- the live instance is the most reliable source. Falls back to the generic resolver.
local function resolve_widget_class(name)
    if type(name) == "userdata" then return name end
    local c; pcall(function() c = FindObject("WidgetBlueprintGeneratedClass", name) end)
    if c and c.IsValid and c:IsValid() then return c end
    for _, ww in ipairs(FindAllOf("UserWidget") or {}) do
        local cn; pcall(function() cn = ww:GetClass():GetFName():ToString() end)
        if cn == name then local cc; pcall(function() cc = ww:GetClass() end); if cc and cc.IsValid and cc:IsValid() then return cc end end
    end
    return resolve_class(name)
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

-- ── health-component verbs (ANY actor) — VEIN's REAL damage path (engine ApplyDamage is a no-op on VEIN) ──
-- Proven 2026-06-25: HealthComponent GetHealth()/SetHealth(HP)/ModifyHealth(Amount)/SetInvincible(bool).
-- A live zombie 30.26 HP -> ModifyHealth(-9999) -> 0 (died). All single Double args, reflection, no DLL.
local function health_comp(actor)
    if not (actor and actor.IsValid and actor:IsValid()) then return nil end
    local hc; pcall(function() hc = actor:GetHealthComponent() end)
    if not (hc and hc.IsValid and hc:IsValid()) then pcall(function() hc = actor.Health end) end
    if hc and hc.IsValid and hc:IsValid() then return hc end
    return nil
end
M.health_component = health_comp

--- Any actor's current health (via the component getter; reads Double). @return number|nil
function M.health_of(actor)
    local hc = health_comp(actor); if not hc then return nil end
    local v; pcall(function() v = hc:GetHealth() end)
    return isnum(v) and v or nil
end
--- Damage any actor by `amount` (graded). veincf.world.damage(target, n).
function M.damage_actor(actor, amount)
    if not (isnum(amount) and amount >= 0) then return false, "damage_actor(actor, amount>=0)" end
    local hc = health_comp(actor); if not hc then return false, "no health component" end
    return (pcall(function() hc:ModifyHealth(-amount) end))
end
--- Heal any actor by `amount`. veincf.world.heal(target, n).
function M.heal_actor(actor, amount)
    if not (isnum(amount) and amount >= 0) then return false, "heal_actor(actor, amount>=0)" end
    local hc = health_comp(actor); if not hc then return false, "no health component" end
    return (pcall(function() hc:ModifyHealth(amount) end))
end
--- Kill any actor. veincf.world.kill(target). Routes through the DAMAGE path (ModifyHealth) so the
--- death cascade (ragdoll/anim/loot) fires — a raw SetHealth(0) zeroes health but skips the death trigger.
function M.kill(actor)
    local hc = health_comp(actor); if not hc then return false, "no health component" end
    return (pcall(function() hc:ModifyHealth(-1000000.0) end))
end
--- Make an actor invincible / mortal. veincf.world.set_invincible(target, bool).
function M.set_invincible(actor, on)
    local hc = health_comp(actor); if not hc then return false, "no health component" end
    return (pcall(function() hc:SetInvincible(on and true or false) end))
end

--- The actor your VIEW is pointed at — eyes + view-forward alignment (dot-product) over instances of a
--- class (default BP_Zombie_C). Reflection only, no DLL trace (NOT wall-aware; precise line-trace is future
--- polish). aim_target("BP_Zombie_C", {cone=0.95, range=6000}). Pairs with world.damage = a gun/ability.
function M.aim_target(className, opts)
    local p = pc(); if not p then return nil end
    local ex, ey, ez; pcall(function() local l = p:K2_GetActorLocation(); ex, ey, ez = l.X, l.Y, l.Z end)
    local fx, fy, fz
    local pctrl; pcall(function() pctrl = p:GetController() end)
    local fwd; if pctrl then pcall(function() fwd = pctrl:GetActorForwardVector() end) end
    if type(fwd) ~= "table" then pcall(function() fwd = p:GetActorForwardVector() end) end
    if type(fwd) == "table" then fx, fy, fz = fwd.X, fwd.Y, fwd.Z end
    if not (isnum(ex) and isnum(fx)) then return nil end
    local cone = (opts and opts.cone) or 0.95
    local range = (opts and opts.range) or 6000
    local best, bestdot = nil, cone
    for _, a in ipairs(FindAllOf(className or "BP_Zombie_C") or {}) do
        local al; pcall(function() al = a:K2_GetActorLocation() end)
        if al then
            local dx, dy, dz = (al.X or 0) - ex, (al.Y or 0) - ey, (al.Z or 0) - ez
            local d = math.sqrt(dx*dx + dy*dy + dz*dz)
            if d > 1 and d < range then
                local dot = (dx/d)*fx + (dy/d)*fy + (dz/d)*fz
                if dot > bestdot then bestdot = dot; best = a end
            end
        end
    end
    return best
end

-- ── attach / detach (cars / storage / placeables that hold things) — reflected K2_AttachToActor ──
-- Proven 2026-06-25 (a zombie snapped to the player). EAttachmentRule: KeepRelative=0/KeepWorld=1/SnapToTarget=2.
function M.attach(child, parent, socket)
    if not (child and child.IsValid and child:IsValid()) then return false, "attach: invalid child" end
    if not (parent and parent.IsValid and parent:IsValid()) then return false, "attach: invalid parent" end
    local sock = fname(socket or "None"); if not sock then return false, "attach: FName failed" end
    return (pcall(function() child:K2_AttachToActor(parent, sock, 2, 2, 2, false) end))   -- SnapToTarget all
end
function M.detach(child)
    if not (child and child.IsValid and child:IsValid()) then return false, "detach: invalid child" end
    return (pcall(function() child:K2_DetachFromActor(0, 0, 0) end))   -- KeepRelative
end

-- ── inventory / interaction (struct-arg) — via the DLL ReadStructValue + CallWithStruct primitives ──
-- The struct param (ItemInstance) can't round-trip through UE4SS Lua reflection (hard-locks); we read its
-- raw bytes + build the param frame in C++. Proven 2026-06-25 (Server_UseItem ran clean). `action_id` is
-- the use-action Name (defaults "None"); a real id may be needed for a visible effect — TBD per item.
function M.use_equipped(action_id)
    local p = pc(); if not p then return false, "no player" end
    if type(ReadStructValue) ~= "function" or type(CallWithStruct) ~= "function" then
        return false, "DLL ReadStructValue/CallWithStruct missing"
    end
    local h; pcall(function() h = ReadStructValue(p, "GetEquippedItemInstance") end)
    if not (h and h.ptr) then return false, "no equipped item (or getter failed)" end
    local r; pcall(function() r = CallWithStruct(p, "Server_UseItem", h.ptr, h.size, action_id or "None") end)
    return (r and r.ok and r.structWrote == 1) or false, r
end

-- ── net / authority (MP server-authority gates) — see library docs/ue56-save-and-replication.md ──
-- ENetMode: NM_Standalone=0, NM_DedicatedServer=1, NM_ListenServer=2, NM_Client=3 (< NM_Client = a server).
-- ENetRole: ROLE_Authority=3. Best-effort reflection reads; SP / unknown => server + authority.
local function _netmode()
    local p = pc(); if not p then return nil end
    local m; pcall(function() m = p:GetNetMode() end)
    return isnum(m) and m or nil
end
M.net_mode = _netmode
function M.is_standalone() local m = _netmode(); return m == nil or m == 0 end
function M.is_server()     local m = _netmode(); return m == nil or m < 3 end
function M.is_client()     return _netmode() == 3 end
function M.has_authority(actor)
    local a = actor or pc(); if not a then return true end
    local r; pcall(function() r = a:GetLocalRole() end)
    if not isnum(r) then pcall(function() r = a.Role end) end
    if isnum(r) then return r == 3 end
    return true   -- SP / unknown => assume authority
end
function M.authority_only(fn)
    if type(fn) ~= "function" then return false, "authority_only(fn)" end
    if M.has_authority() then return fn() end
    return nil
end

-- ── UI — reuse the game's own widgets (UMG). Create an instance of an existing WBP + add to viewport.
-- WidgetBlueprintLibrary:Create(WorldContext, WidgetType:class, OwningPlayer) -> UserWidget (all reflected).
-- ⚠ build/add our OWN instance; NEVER mutate a LIVE game-owned widget mid-paint (crash). See ui-and-attach.md.
-- ★ PROVEN 2026-06-25: UMG Create needs a live WIDGET (the HUD) as WorldContext — a raw controller/pawn
-- returns null. Use the live HUD (any live UserWidget) for context; class must be loaded (resolve_class).
local function _create_widget(cls)
    local hud = (FindAllOf("WBP_HUD_C") or {})[1] or (FindAllOf("UserWidget") or {})[1]
    if not (hud and hud.IsValid and hud:IsValid()) then return nil, "no live widget for context (enter a world)" end
    local owner; pcall(function() owner = hud:GetOwningPlayer() end)
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local w
    if type(CallReturningObject) == "function" and wbl then
        pcall(function() w = CallReturningObject(wbl, "Create", hud, cls, owner) end)   -- live HUD = WorldContext
    end
    if not (w and w.IsValid and w:IsValid()) then                                       -- fallback: construct w/ HUD outer
        pcall(function() w = StaticConstructObject(cls, hud, FName("None"), 0, 0, nil, false, false, nil) end)
    end
    if not (w and w.IsValid and w:IsValid()) then return nil, "creation failed" end
    return w
end

--- Create a widget + show it as a viewport OVERLAY (HUD-style). veincf.ui.spawn_widget("WBP_X_C").
function M.spawn_widget(wbp_class, opts)
    local cls = resolve_widget_class(wbp_class); if not cls then return nil, "spawn_widget: class not found/loaded: " .. tostring(wbp_class) end
    local w, err = _create_widget(cls); if not w then return nil, "spawn_widget: " .. tostring(err) end
    pcall(function() w:AddToViewport((opts and opts.zorder) or 0) end)
    return w
end

--- Open a proper MANAGED window (escapable/layered) — the game uses Epic CommonUI: the window stack is a
--- CommonActivatableWidgetStack and BP_AddWidget(class) creates + pushes it. veincf.ui.open_window("WBP_X_C").
--- The widget class should be a CommonActivatableWidget (the game's window base) to be stack-managed.
function M.open_window(wbp_class, opts)
    local cls = resolve_widget_class(wbp_class); if not cls then return nil, "open_window: class not found/loaded: " .. tostring(wbp_class) end
    local wc = (FindAllOf("WBP_RootWindowContainer_C") or {})[1]
    local stack; if wc and wc.IsValid and wc:IsValid() then pcall(function() stack = wc:GetStack() end) end
    if stack and stack.IsValid and stack:IsValid() then
        local w
        if type(CallReturningObject) == "function" then pcall(function() w = CallReturningObject(stack, "BP_AddWidget", nil, cls, nil) end) end
        if not (w and w.IsValid and w:IsValid()) then pcall(function() stack:BP_AddWidget(cls) end) end       -- side-effect even if the return drops
        if not (w and w.IsValid and w:IsValid()) then pcall(function() w = stack:GetActiveWidget() end) end  -- recover the top-of-stack
        return w or true
    end
    -- fallback: unmanaged overlay if there's no window stack
    local w2 = _create_widget(cls); if w2 then pcall(function() w2:AddToViewport((opts and opts.zorder) or 50) end) end
    return w2
end
function M.find_widget(name) return (FindAllOf(name) or {})[1] end
function M.set_widget_visible(w, vis)
    if not (w and w.IsValid and w:IsValid()) then return false end
    return (pcall(function() w:SetVisibility(vis and 0 or 1) end))   -- ESlateVisibility: Visible=0 / Collapsed=1
end
function M.remove_widget(w)
    if not (w and w.IsValid and w:IsValid()) then return false end
    return (pcall(function() w:RemoveFromParent() end))
end

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
