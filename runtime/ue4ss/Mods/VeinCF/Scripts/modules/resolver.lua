------------------------------------------------------------
-- VeinCF :: resolver
-- Dependency resolution, conflict detection, and topological
-- sort to produce a deterministic load order.
--
-- Pipeline:
--   1. check_requirements()  — ue4ss / veincf / game version gates
--   2. check_conflicts()     — bidirectional conflict detection
--   3. check_dependencies()  — missing / incompatible mod deps
--   4. toposort()            — Kahn's algorithm with soft ordering
--
-- Each step collects errors into the log. If any FATAL-level
-- errors appear, the loader should abort before executing mods.
--
-- Require as: require("modules.resolver")
------------------------------------------------------------
local semver = require("modules.semver")
local log    = require("modules.log")

local M = {}

------------------------------------------------------------
-- 1. Framework & game version gates
------------------------------------------------------------

--- Check requires.ue4ss / requires.veincf / requires.game
--- against the running environment.
--- `env` = { ue4ss = "3.0.1", veincf = "0.1.0", game = "1.0.0" }
function M.check_requirements(manifests, env)
    local blocked = {}

    for id, m in pairs(manifests) do
        local req = m.requires
        if not req then goto next_mod end

        -- ue4ss version
        if req.ue4ss and env.ue4ss then
            local ok, err = semver.satisfies(env.ue4ss, req.ue4ss)
            if not ok then
                log.error(id, "Requires UE4SS %s but running %s", req.ue4ss, env.ue4ss)
                blocked[id] = true
            end
        end

        -- veincf version
        if req.veincf and env.veincf then
            local ok, err = semver.satisfies(env.veincf, req.veincf)
            if not ok then
                log.error(id, "Requires VeinCF %s but running %s", req.veincf, env.veincf)
                blocked[id] = true
            end
        end

        -- game build
        if req.game and env.game then
            local ok, err = semver.satisfies(env.game, req.game)
            if not ok then
                log.error(id, "Requires game %s but running %s", req.game, env.game)
                blocked[id] = true
            end
        end

        ::next_mod::
    end

    -- Remove blocked mods from the working set
    for id in pairs(blocked) do
        manifests[id] = nil
    end

    return blocked
end

------------------------------------------------------------
-- 2. Conflict detection (bidirectional)
------------------------------------------------------------

function M.check_conflicts(manifests)
    local blocked = {}

    for id, m in pairs(manifests) do
        if m.conflicts then
            for _, cid in ipairs(m.conflicts) do
                if manifests[cid] and not blocked[cid] then
                    log.error(id, "Conflicts with '%s' — both are installed. Remove one.", cid)
                    -- block the one that declared the conflict (convention: declarer yields)
                    blocked[id] = true
                end
            end
        end
    end

    for id in pairs(blocked) do
        manifests[id] = nil
    end

    return blocked
end

------------------------------------------------------------
-- 3. Dependency resolution
------------------------------------------------------------

function M.check_dependencies(manifests)
    local blocked = {}

    -- Iterate until stable (a removed mod may cause cascading failures)
    local changed = true
    while changed do
        changed = false
        for id, m in pairs(manifests) do
            if blocked[id] then goto next end
            local deps = m.requires and m.requires.mods
            if not deps then goto next end

            for dep_id, range in pairs(deps) do
                local dep = manifests[dep_id]
                if not dep then
                    log.error(id, "Missing required dependency '%s'", dep_id)
                    blocked[id] = true
                    changed = true
                    break
                end
                local ok, err = semver.satisfies(dep.version, range)
                if not ok then
                    log.error(id, "Requires '%s' %s but found %s",
                              dep_id, range, dep.version)
                    blocked[id] = true
                    changed = true
                    break
                end
            end

            ::next::
        end

        -- Prune blocked
        for bid in pairs(blocked) do
            if manifests[bid] then
                manifests[bid] = nil
            end
        end
    end

    return blocked
end

------------------------------------------------------------
-- 4. Topological sort (Kahn's algorithm)
------------------------------------------------------------
-- Edges come from two sources:
--   HARD: requires.mods — dep must load before dependent
--   SOFT: load_order.after / load_order.before — hints, no error if missing

function M.toposort(manifests)
    -- Build adjacency: edges[a][b] = true means "a must load before b"
    local ids    = {}
    local in_deg = {}
    local edges  = {}

    for id in pairs(manifests) do
        ids[#ids+1] = id
        in_deg[id]  = 0
        edges[id]   = {}
    end

    local function add_edge(from, to)
        if not manifests[from] or not manifests[to] then return end
        if from == to then return end
        if edges[from][to] then return end
        edges[from][to] = true
        in_deg[to] = in_deg[to] + 1
    end

    for id, m in pairs(manifests) do
        -- hard deps: dep loads before us
        local deps = m.requires and m.requires.mods
        if deps then
            for dep_id in pairs(deps) do
                add_edge(dep_id, id)
            end
        end

        -- soft ordering
        local lo = m.load_order
        if lo then
            if lo.after then
                for _, aid in ipairs(lo.after) do add_edge(aid, id) end
            end
            if lo.before then
                for _, bid in ipairs(lo.before) do add_edge(id, bid) end
            end
        end
    end

    -- Kahn's
    local queue  = {}
    local sorted = {}

    -- Seed with zero in-degree, sorted alphabetically for determinism
    table.sort(ids)
    for _, id in ipairs(ids) do
        if in_deg[id] == 0 then queue[#queue+1] = id end
    end

    while #queue > 0 do
        -- Pop first (BFS for stable order among peers)
        local node = table.remove(queue, 1)
        sorted[#sorted+1] = node

        -- Collect and sort neighbors for determinism
        local neighbors = {}
        for to in pairs(edges[node]) do
            neighbors[#neighbors+1] = to
        end
        table.sort(neighbors)

        for _, to in ipairs(neighbors) do
            in_deg[to] = in_deg[to] - 1
            if in_deg[to] == 0 then
                queue[#queue+1] = to
            end
        end
    end

    -- Cycle detection
    if #sorted ~= #ids then
        local in_cycle = {}
        for _, id in ipairs(ids) do in_cycle[id] = true end
        for _, id in ipairs(sorted) do in_cycle[id] = nil end
        local cycle_ids = {}
        for id in pairs(in_cycle) do cycle_ids[#cycle_ids+1] = id end
        table.sort(cycle_ids)
        log.error(nil, "Dependency cycle detected among: %s", table.concat(cycle_ids, ", "))
        -- Remove cycled mods
        for _, id in ipairs(cycle_ids) do
            manifests[id] = nil
        end
        -- Re-run without them
        return M.toposort(manifests)
    end

    return sorted
end

------------------------------------------------------------
-- Full pipeline convenience
------------------------------------------------------------

--- Run all resolution steps. Returns ordered list of mod IDs
--- that survived validation and are safe to load.
function M.resolve(manifests, env)
    M.check_requirements(manifests, env)
    M.check_conflicts(manifests)
    M.check_dependencies(manifests)
    local order = M.toposort(manifests)
    return order
end

return M
