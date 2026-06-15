------------------------------------------------------------
-- VeinCF :: recipes
-- Runtime recipe injection API.
-- Allows mods to inject recipe widgets into the crafting UI,
-- modify existing recipes, and remove injected recipes.
--
-- Usage (from a mod script with veincf sandbox):
--   veincf.recipes.add({
--       recipe_name = "CR_HandGrenade",    -- FName of BaseRecipe
--       category    = 0,                   -- category index (0-based)
--   })
--
-- Require as: require("modules.recipes")
------------------------------------------------------------
local log = require("modules.log")

local M = {}

--- Internal registry of injected widgets
--- Key = unique tag, Value = { widget, recipe, category_idx }
local _injected = {}

--- Counter for unique widget names
local _counter = 0

--- Cached references (populated on first use)
local _cache = {
    workbench    = nil,   -- live WorkbenchUserWidget
    categories   = {},    -- [idx] = { widget, recipes_box, icon_class }
    textures     = nil,   -- [fname] = Texture2D (lazy)
    recipes      = nil,   -- [fname] = BaseRecipe (lazy)
}

------------------------------------------------------------
-- Internal helpers
------------------------------------------------------------

--- Find the live workbench widget (must be open)
local function get_workbench()
    if _cache.workbench and _cache.workbench:IsValid() then
        return _cache.workbench
    end
    _cache.workbench = nil
    local ok, all = pcall(FindAllOf, "WorkbenchUserWidget")
    if ok and all then
        for _, w in ipairs(all) do
            if w:GetFullName():find("Transient") then
                _cache.workbench = w
                return w
            end
        end
    end
    return nil
end

--- Get category info at a given index
local function get_category(idx)
    if _cache.categories[idx] then
        local c = _cache.categories[idx]
        if c.widget and c.widget:IsValid() then return c end
    end

    local wb = get_workbench()
    if not wb then return nil end

    local recipesBox = wb.Recipes
    if not recipesBox then return nil end

    local count = recipesBox:GetChildrenCount()
    if idx >= count then return nil end

    local cat = recipesBox:GetChildAt(idx)
    if not cat or not cat:IsValid() then return nil end

    local info = {
        widget      = cat,
        recipes_box = cat.Recipes,
        icon_class  = cat.RecipeIconClass,
    }
    _cache.categories[idx] = info
    return info
end

--- Find a BaseRecipe by FName string
local function find_recipe(name)
    if _cache.recipes then
        return _cache.recipes[name]
    end

    -- Build cache on first call
    _cache.recipes = {}
    local ok, all = pcall(FindAllOf, "BaseRecipe")
    if ok and all then
        for _, r in ipairs(all) do
            pcall(function()
                _cache.recipes[r:GetFName():ToString()] = r
            end)
        end
    end
    return _cache.recipes[name]
end

--- Find a thumbnail texture by recipe result item name
--- Convention: T_Thumb_BP_<ItemName>_0
local function find_thumbnail(recipe)
    if not recipe then return nil end

    -- Try to find by recipe FName pattern
    local rname = recipe:GetFName():ToString()
    -- CR_HandGrenade -> HandGrenade, CR_BandageMakeshift -> BandageMakeshift
    local item_part = rname:match("^CR_(.+)$") or rname:match("^RP_(.+)$") or rname

    -- Build texture cache if needed
    if not _cache.textures then
        _cache.textures = {}
        local ok, all = pcall(FindAllOf, "Texture2D")
        if ok and all then
            for _, t in ipairs(all) do
                pcall(function()
                    local n = t:GetFName():ToString()
                    if n:find("^T_Thumb_") then
                        _cache.textures[n] = t
                    end
                end)
            end
        end
    end

    -- Search for matching thumbnail
    -- Try exact: T_Thumb_BP_<ItemName>_0
    local candidates = {
        "T_Thumb_BP_" .. item_part .. "_0",
        "T_Thumb_" .. item_part .. "_0",
    }
    for _, name in ipairs(candidates) do
        if _cache.textures[name] then
            return _cache.textures[name]
        end
    end

    -- Fuzzy match: any T_Thumb containing the item name
    for tname, tex in pairs(_cache.textures) do
        if tname:find(item_part, 1, true) then
            return tex
        end
    end

    return nil
end

--- Clean up old injected widgets with a given prefix
local function cleanup_tag(tag)
    local entry = _injected[tag]
    if entry and entry.widget then
        pcall(function()
            if entry.widget:IsValid() then
                entry.widget:RemoveFromParent()
            end
        end)
    end
    _injected[tag] = nil
end

------------------------------------------------------------
-- Public API
------------------------------------------------------------

--- Inject a recipe widget into the crafting UI.
---
--- @param opts table with fields:
---   recipe_name  (string)  FName of the BaseRecipe (e.g. "CR_HandGrenade")
---   recipe       (UObject) OR direct BaseRecipe reference (overrides recipe_name)
---   category     (number)  category index, 0-based (default 0)
---   tag          (string)  unique ID for this injection (default: auto-generated)
---   craftable    (bool)    mark as craftable (default true)
---   needs_schematic (bool) requires schematic (default false)
---
--- @return string tag  The unique tag for this injection (use to remove later)
--- @return string|nil error  Error message if failed
--- Injection core. MUST be called on the game thread (no ExecuteInGameThread
--- inside, so it is safe to nest within another game-thread block).
--- @return string|nil tag, string|nil error
local function _add_impl(opts)
    if type(opts) ~= "table" then
        return nil, "recipes.add expects a table"
    end

    -- Resolve recipe
    local recipe = opts.recipe
    if not recipe and opts.recipe_name then
        recipe = find_recipe(opts.recipe_name)
    end
    if not recipe then
        return nil, string.format("Recipe not found: %s", tostring(opts.recipe_name))
    end

    local cat_idx = opts.category or 0
    local tag = opts.tag
    if not tag then
        _counter = _counter + 1
        tag = string.format("veincf_recipe_%d", _counter)
    end

    -- Remove existing widget with same tag
    cleanup_tag(tag)

    local cat = get_category(cat_idx)
    if not cat then
        return nil, string.format("Category %d not found (workbench open?)", cat_idx)
    end

    local fname = FName("VeinCF_" .. tag)
    local widget = StaticConstructObject(cat.icon_class, cat.widget, fname, 0, 0, nil, false, false, nil)
    if not widget or not widget:IsValid() then
        return nil, "StaticConstructObject failed"
    end

    cat.recipes_box:AddChild(widget)
    pcall(function() widget:Construct() end)

    widget.Recipe = recipe
    widget.bCraftable = opts.craftable ~= false
    widget.bNeedsSchematic = opts.needs_schematic or false

    -- Set display name
    pcall(function()
        widget.ItemName:SetText(recipe.RecipeName:ToString())
    end)

    -- Set thumbnail
    local tex = find_thumbnail(recipe)
    if tex then
        pcall(function()
            widget.Thumbnail:SetBrushFromTexture(tex, false)
        end)
    end

    -- Store in registry
    _injected[tag] = {
        widget   = widget,
        recipe   = recipe,
        category = cat_idx,
    }

    return tag
end

function M.add(opts)
    local tag, err
    ExecuteInGameThread(function() tag, err = _add_impl(opts) end)
    return tag, err
end

--- Remove an injected recipe widget by tag.
---
--- @param tag string  The tag returned by add()
--- @return boolean success
function M.remove(tag)
    local entry = _injected[tag]
    if not entry then return false end

    ExecuteInGameThread(function()
        cleanup_tag(tag)
    end)
    return true
end

--- Remove all injected recipe widgets.
function M.remove_all()
    ExecuteInGameThread(function()
        for tag in pairs(_injected) do
            cleanup_tag(tag)
        end
    end)
end

--- Modify properties on an existing recipe (any recipe, not just injected).
---
--- @param recipe_name string  FName of the BaseRecipe
--- @param props table  Properties to set (e.g. { CraftTime = 10.0 })
--- @return boolean success
--- @return string|nil error
function M.modify(recipe_name, props)
    local recipe = find_recipe(recipe_name)
    if not recipe then
        return false, string.format("Recipe not found: %s", recipe_name)
    end

    ExecuteInGameThread(function()
        for k, v in pairs(props) do
            pcall(function()
                recipe[k] = v
            end)
        end
    end)

    return true
end

--- List all injected recipe tags.
---
--- @return table  Array of { tag, recipe_name, category }
function M.list()
    local result = {}
    for tag, entry in pairs(_injected) do
        local rname = "?"
        pcall(function() rname = entry.recipe:GetFName():ToString() end)
        result[#result+1] = {
            tag      = tag,
            recipe   = rname,
            category = entry.category,
        }
    end
    return result
end

--- Get all available recipe names (for discovery).
---
--- @return table  Array of FName strings
function M.get_all_recipes()
    local result = {}
    local ok, all = pcall(FindAllOf, "BaseRecipe")
    if ok and all then
        for _, r in ipairs(all) do
            pcall(function()
                result[#result+1] = r:GetFName():ToString()
            end)
        end
    end
    table.sort(result)
    return result
end

--- Get a recipe UObject by FName.
---
--- @param name string  FName of the BaseRecipe
--- @return UObject|nil
function M.get_recipe(name)
    return find_recipe(name)
end

--- Invalidate internal caches (call after workbench re-opens).
function M.invalidate_cache()
    _cache.workbench  = nil
    _cache.categories = {}
    _cache.textures   = nil
    _cache.recipes    = nil
end

------------------------------------------------------------
-- New-content pipeline: load a cooked recipe from a mounted
-- pak, repair its TSubclassOf item refs, and register it.
--
-- Background: a cooked recipe pak'd via LogicMods mounts but is
-- never instantiated (BPModLoader only spawns ModActor blueprints).
-- We load it explicitly with AssetRegistryHelpers:GetAsset — the
-- same primitive BPModLoader uses. Its OBJECT refs (RecipeType,
-- WorkbenchType) bind fine, but its CLASS refs (TSubclassOf item
-- blueprints) fail to bind from a mod pak and read as null. We
-- repair those at runtime by loading the real item classes by
-- path and assigning them into the null slots.
------------------------------------------------------------

local _UEHelpers_ok, _UEHelpers = pcall(require, "UEHelpers")

--- Make an FName from a string, tolerant of UE4SS variants.
local function mk_fname(s)
    if _UEHelpers_ok and _UEHelpers and _UEHelpers.FindOrAddFName then
        return _UEHelpers.FindOrAddFName(s)
    end
    return FName(s)
end

--- Load a recipe UObject from a mounted pak by package path.
--- MUST run on the game thread (no ExecuteInGameThread inside — safe to nest).
--- Uses AssetRegistryHelpers:GetAsset (BPModLoader's proven primitive).
--- @return UObject|nil recipe
local function _load_from_pak(package_path, asset_name)
    if not package_path then return nil end
    asset_name = asset_name or package_path:match("[^/]+$")
    local arh = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
    if not (arh and arh:IsValid()) then return nil end
    local data = {
        ["PackageName"] = mk_fname(package_path),
        ["AssetName"]   = mk_fname(asset_name),
    }
    local ok, got = pcall(function() return arh:GetAsset(data) end)
    if ok and got and got:IsValid() then return got end
    return nil
end

--- Public wrapper: single game-thread hop.
--- @param package_path string  e.g. "/Game/Vein/Recipes/Crafting/Fuel/CR_QuickKinling"
--- @param asset_name    string|nil  defaults to the leaf of package_path
--- @return UObject|nil recipe
function M.load_from_pak(package_path, asset_name)
    local result = nil
    ExecuteInGameThread(function() result = _load_from_pak(package_path, asset_name) end)
    return result
end

--- Resolve a (Blueprint-generated) class by content path.
--- "/Game/.../BP_X"          -> object "/Game/.../BP_X.BP_X_C"
--- "/Game/.../BP_X.BP_X_C"   -> used as-is
--- @return UClass|nil
local function load_class_by_path(path)
    if not path then return nil end
    local candidates = {}
    local pkg_only = path
    if path:find("%.") then
        candidates[#candidates+1] = path
        pkg_only = path:match("^(.-)%.")
    else
        local leaf = path:match("[^/]+$")
        candidates[#candidates+1] = string.format("%s.%s_C", path, leaf)  -- BlueprintGeneratedClass
        candidates[#candidates+1] = string.format("%s.%s", path, leaf)    -- native/datasset class
    end
    -- try to resolve without loading first (quiets "found but not loaded" spam)
    for _, p in ipairs(candidates) do
        local obj = StaticFindObject(p)
        if obj and obj:IsValid() then return obj end
    end
    -- not resident yet — load the package, then resolve
    pcall(function() LoadAsset(pkg_only) end)
    for _, p in ipairs(candidates) do
        local obj = StaticFindObject(p)
        if obj and obj:IsValid() then return obj end
    end
    return nil
end

M.load_class_by_path = load_class_by_path

--- Repair null TSubclassOf item refs on a recipe from a spec.
--- spec = {
---   results         = { "/Game/.../BP_Result", ... },       -- aligned to Results[]
---   ingredient_sets = { { "/Game/.../BP_A", "/Game/.../BP_B" }, ... }, -- per set, aligned to Ingredients[]
--- }
--- @return table report { ok=bool, results={...}, ingredients={...} }
--- MUST run on the game thread (no ExecuteInGameThread inside — safe to nest).
local function _repair(recipe, spec)
    local report = { ok = true, results = {}, ingredients = {} }
    if not (recipe and recipe:IsValid()) then report.ok = false; return report end
    spec = spec or {}
    do
        -- Result items
        if spec.results then
            local arr = recipe.Results
            for i, path in ipairs(spec.results) do
                local cls = load_class_by_path(path)
                if cls and arr:GetArrayNum() >= i then
                    pcall(function() arr[i].Item = cls end)
                    local n = "?"; pcall(function() n = cls:GetFName():ToString() end)
                    report.results[i] = n
                else
                    report.results[i] = "FAILED:" .. tostring(path)
                    report.ok = false
                end
            end
        end
        -- Ingredient-set items
        if spec.ingredient_sets then
            local sets = recipe.PossibleIngredients
            for si, set_paths in ipairs(spec.ingredient_sets) do
                if sets:GetArrayNum() >= si then
                    local ing = sets[si].Ingredients
                    for ii, path in ipairs(set_paths) do
                        local cls = load_class_by_path(path)
                        if cls and ing:GetArrayNum() >= ii then
                            pcall(function() ing[ii].Item = cls end)
                            local n = "?"; pcall(function() n = cls:GetFName():ToString() end)
                            report.ingredients[#report.ingredients+1] = n
                        else
                            report.ingredients[#report.ingredients+1] = "FAILED:" .. tostring(path)
                            report.ok = false
                        end
                    end
                end
            end
        end
    end
    return report
end

--- Public wrapper: single game-thread hop.
--- @return table report { ok=bool, results={...}, ingredients={...} }
function M.repair(recipe, spec)
    local report
    ExecuteInGameThread(function() report = _repair(recipe, spec) end)
    return report
end

--- Full new-content pipeline: load a cooked recipe from a pak,
--- repair its item class refs, and inject it as a craftable tile.
---
--- PLAIN function — MUST be called on the game thread (i.e. from inside an
--- ExecuteInGameThread block). It performs NO hop itself, so the caller can
--- read its return values reliably (avoids the async-hop result race).
--- Requires a workbench to be OPEN for the injection step.
--- opts = {
---   package         = "/Game/.../CR_X",   (required)
---   asset           = "CR_X",             (optional; derived from package)
---   results         = { "/Game/.../BP_Result" },
---   ingredient_sets = { { "/Game/.../BP_A", "/Game/.../BP_B" } },
---   category        = 0,
---   craftable       = true,
---   tag             = "...",
--- }
--- @return string|nil tag, string|nil error, UObject|nil recipe, table|nil repair_report
function M.register(opts)
    if type(opts) ~= "table" or not opts.package then
        return nil, "recipes.register requires opts.package"
    end

    local recipe = _load_from_pak(opts.package, opts.asset)
    if not recipe then
        return nil, "could not load recipe from pak: " .. tostring(opts.package)
    end
    local report = _repair(recipe, {
        results         = opts.results,
        ingredient_sets = opts.ingredient_sets,
    })
    local tag, err = _add_impl({
        recipe    = recipe,
        category  = opts.category or 0,
        craftable = opts.craftable ~= false,
        tag       = opts.tag,
    })
    return tag, err, recipe, report
end

-- Plain (game-thread-required) building blocks, for callers that want to
-- compose the pipeline inside their own single ExecuteInGameThread block.
M.raw = {
    load_from_pak = _load_from_pak,
    repair        = _repair,
    add           = _add_impl,
}

------------------------------------------------------------
-- Manifest-driven content pipeline (startup, zero-button)
-- A content mod declares cooked recipes in its manifest.json:
--   "recipes": [
--     { "package": "/Game/.../CR_X", "asset": "CR_X",
--       "results": ["/Game/.../BP_Result"],
--       "ingredient_sets": [["/Game/.../BP_A","/Game/.../BP_B"]],
--       "category": 0, "unlock": true }
--   ]
-- The framework loads each from its mounted pak, repairs item class refs,
-- and hands it to the registration BACKEND to make it discoverable/craftable.
------------------------------------------------------------

--- Load + repair + unlock a declared recipe. Game-thread plain.
--- @return UObject|nil recipe, string|nil error, table|nil repair_report
local function _prepare(spec)
    if type(spec) ~= "table" or not spec.package then
        return nil, "recipe spec missing 'package'"
    end
    local rec = _load_from_pak(spec.package, spec.asset)
    if not rec then return nil, "load failed: " .. tostring(spec.package) end
    local report = _repair(rec, { results = spec.results, ingredient_sets = spec.ingredient_sets })
    if spec.unlock ~= false then pcall(function() rec.bDefaultUnlocked = true end) end
    pcall(function() rec.bEnabled = true end)
    return rec, nil, report
end
M.raw.prepare = _prepare

--- Registration BACKEND — makes a prepared recipe discoverable in VEIN's
--- recipe registry (so GetAllRecipes/workbench/craft see it). The actual
--- mechanism (LuaTMap.Add into the recipe map vs native scan vs AssetRegistry
--- merge) is pending the F9/F10 registry recon. Until then this is a stub;
--- swap this single function once the mechanism is known and the whole
--- manifest pipeline goes live with zero other changes.
--- @return boolean ok, string|nil error
M.register_backend = function(recipe, spec)
    -- DLL route via our native PolyHook detour on GetAllRecipes.
    -- Installed HERE (at startup, before any workbench builds its tile cache),
    -- with a COOKED persistent recipe (the old failed test used a synthetic
    -- GC'd object installed mid-session, after the cache was built). If the
    -- first workbench build calls GetAllRecipes, the detour appends our recipe.
    local name = spec.asset
    if not name then pcall(function() name = recipe:GetFName():ToString() end) end

    -- keep the recipe preloaded + GC-rooted (so the detour never appends a dead obj)
    if type(RegisterPreloadedAsset) == "function" then
        pcall(function() RegisterPreloadedAsset("Recipe", name, recipe) end)
    end

    -- HOOK DISABLED FOR DIAGNOSIS (2026-06-11): launch dump shows GetAllRecipes=-1
    -- everywhere; suspect our own detour corrupts the return. Leaving it off to
    -- confirm GetAllRecipes reads cleanly without it.
    -- if type(HookGetAllRecipes) == "function" then
    --     local am = (FindAllOf("VeinAssetManager") or {})[1]
    --     if am then pcall(function() HookGetAllRecipes(am, recipe) end) end
    -- end
    return true, "preloaded (GetAllRecipes hook DISABLED for diagnosis)"
end

--- Register all recipes declared in a mod manifest. Assumes paks are mounted.
--- Runs the whole batch inside ONE game-thread hop. Safe to call at startup;
--- if the asset registry isn't ready yet, individual loads fail gracefully.
--- @param recipes_list table  the manifest's `recipes` array
--- @param mod_id string|nil   for scoped logging
--- @return table report  { prepared=N, registered=N, failed=N }
------------------------------------------------------------
-- ★ register_content — the modder-facing pipeline (PROVEN 2026-06-15, Banana+Nail->Plunger).
-- A mod's manifest declares friendly recipe specs; at WORLD-LOAD we register the cooked
-- recipe (additive AssetRegistry AppendState merge) + repair it (type/items/bench), then the
-- game surfaces + crafts it NATIVELY (no widget injection). All the hard engine work is hidden.
------------------------------------------------------------
local SEP2 = package.config:sub(1,1)
local function hexn(n) return string.format("0x%X", n) end
local function _num(v) return v and tonumber(v) or nil end
local function _rdu64(a) local ok, v = pcall(ReadU64, hexn(a)); if ok then return v end end
local function _rd32(a) local n = _num(_rdu64(a)); if not n then return nil end return n % 0x100000000 end
local function _vv(o) return o and o:IsValid() end

local function _load_obj(path)
    local o; pcall(function() o = StaticFindObject(path) end)
    if not _vv(o) and type(LoadAsset) == "function" then pcall(function() o = LoadAsset(path) end) end
    return o
end

-- friendly tab/bench names -> asset paths (pass-through if already a /path)
local function tab_to_recipetype(tab)
    if not tab or tab == "" then return nil end
    if tab:find("^/") then return tab end
    return string.format("/Game/Vein/RecipeTypes/RT_%s.RT_%s", tab, tab)
end
local function bench_to_workbenchtype(bench)
    if not bench or bench == "" then return nil end
    if bench:find("^/") then return bench end
    return string.format("/Game/Vein/WorkbenchTypes/WT_%s.WT_%s", bench, bench)
end

-- item by full content path OR short blueprint name ("BP_Banana" / "BP_Banana_C")
local function resolve_item_class(s)
    if not s then return nil end
    if s:find("^/") then return load_class_by_path(s) end
    local leaf = s:gsub("_C$", "")
    local o; pcall(function() o = FindObject("BlueprintGeneratedClass", leaf .. "_C") end)
    return _vv(o) and o or nil
end

-- live Recipe primary-asset AssetMap count (the 249/250) at am+0x470 (see assetmanager doc)
local function _recipe_assetmap_num(amAddr)
    local dataPtr = _num(_rdu64(amAddr + 0x470)); local arrNum = _rd32(amAddr + 0x478)
    if not dataPtr or not arrNum then return nil end
    for i = 0, math.min(arrNum, 4096) - 1 do
        local elem = dataPtr + i * 0x20
        local valPtr = _num(_rdu64(elem + 0x08))
        if valPtr and valPtr > 0x10000 then
            local nm = "?"; pcall(function() nm = ReadFNameAt(hexn(elem)) or "?" end)
            if nm == "Recipe" then return _rd32(valPtr + 0x180) end
        end
    end
end

-- Additively merge a cooked AssetRegistry.bin (no shadow) + scan so the AssetManager indexes
-- our recipe. Resolves AppendState (ar+0x28 vtable +0x3F0) and LoadFromDisk (FindCallersOf the
-- registry loader's Load call -> the file-opener fingerprint). Returns ok, err.
local function merge_registry(bin_path, scan_path, mod_id)
    local arh = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
    local ar; pcall(function() ar = arh:GetAssetRegistry() end)
    if not _vv(ar) then return false, "no AssetRegistry" end
    local am = (FindAllOf("VeinAssetManager") or {})[1]; local amAddr = am and am:GetAddress()
    if not amAddr then return false, "no VeinAssetManager" end
    local iface = ar:GetAddress() + 0x28
    local vtable2 = tonumber(ReadU64(hexn(iface)))
    local appendFn = vtable2 and ReadU64(hexn(vtable2 + 0x3F0))
    if not appendFn then return false, "no appendStateFn" end

    -- resolve Load (registry loader calls it at ~+478; loader found via "AssetRegistry.bin")
    local sp; pcall(function() sp = FindStringRefs("AssetRegistry.bin") end)
    local loadAddr, loaderFn
    if sp and sp.refs then
        for _, e in ipairs(sp.refs) do
            if e.func and e.func ~= "0x0000000000000000" then
                local insns; if pcall(function() insns = DisasmFunction(e.func, 700) end) and insns then
                    local a478, a504
                    for _, ins in ipairs(insns) do
                        local off = tonumber(ins.offset) or -1
                        local c = tostring(ins.text):match("call%s+(0x%x+)")
                        if c and off >= 472 and off <= 484 then a478 = c end
                        if c and off >= 498 and off <= 510 then a504 = c end
                    end
                    if a478 and a504 then loadAddr = a478; loaderFn = e.func; break end
                end
            end
        end
    end
    if not loadAddr then return false, "could not resolve Load" end

    -- FindCallersOf(Load) -> LoadFromDisk = caller that opens a file (indirect call + test rax)
    local loadFromDisk
    local cr; pcall(function() cr = FindCallersOf(loadAddr) end)
    if cr and cr.refs then
        local seen = {}
        for _, e in ipairs(cr.refs) do
            if e.func and e.func ~= "0x0000000000000000" and e.func ~= loaderFn and not seen[e.func] then
                seen[e.func] = true
                local insns; if pcall(function() insns = DisasmFunction(e.func, 20) end) and insns then
                    local indirect, nullchk = false, false
                    for _, ins in ipairs(insns) do
                        local t = tostring(ins.text)
                        if t:match("call%s+%[") then indirect = true end
                        if t:match("test%s+rax,") then nullchk = true end
                    end
                    if indirect and nullchk then loadFromDisk = e.func; break end
                end
            end
        end
    end
    if not loadFromDisk then return false, "could not resolve LoadFromDisk" end

    local before = _recipe_assetmap_num(amAddr)
    local ok = MergeRegistryFromDisk(loadFromDisk, hexn(iface), appendFn, bin_path)
    local sr; pcall(function() sr = FindStringRefs("UAssetManager::ScanPathsForPrimaryAssets") end)
    local cls = StaticFindObject("/Script/Vein.BaseRecipe"); local clsAddr = _vv(cls) and cls:GetAddress() or 0
    if sr and sr.refs and sr.refs[1] then pcall(function() ScanPathsForType(sr.refs[1].func, amAddr, "Recipe", scan_path, clsAddr) end) end
    local after = _recipe_assetmap_num(amAddr)
    log.info(mod_id, "merge_registry: AssetMap %s -> %s (merge ok=%s)", tostring(before), tostring(after), tostring(ok))
    return true
end

-- Normalize a manifest recipe entry (friendly OR explicit) into internal fields.
local function normalize(spec, mod_root)
    local pkg = spec.asset or spec.package
    if not pkg then return nil, "recipe missing 'asset'" end
    local leaf = pkg:match("[^/]+$")
    local scan = pkg:match("^(.+)/[^/]+$")
    local bin = spec.registry_bin
    if bin and not bin:find("^%a:[/\\]") and not bin:find("^/") and mod_root then
        bin = mod_root .. SEP2 .. bin   -- relative to mod folder
    end
    local results = spec.results
    if not results and spec.makes then results = (type(spec.makes) == "table") and spec.makes or { spec.makes } end
    local sets = spec.ingredient_sets
    if not sets and spec.needs then sets = { spec.needs } end          -- needs = 1 set (AND)
    if not sets and spec.needs_any then sets = spec.needs_any end       -- needs_any = OR sets
    return {
        package        = pkg,
        asset          = leaf,
        scan_path      = scan,
        registry_bin   = bin,
        recipe_type    = spec.recipe_type or tab_to_recipetype(spec.tab),
        workbench_type = spec.workbench_type or bench_to_workbenchtype(spec.bench),
        results        = results,
        ingredient_sets = sets,
    }
end

-- Repair the live recipe object from a normalized spec. Defensive: NEVER leaves an ingredient
-- slot None (the native tooltip access-violation crashes on a null item).
local function repair_recipe(rec, n, mod_id)
    if not _vv(rec) then return false end
    if n.recipe_type then local rt = _load_obj(n.recipe_type); if _vv(rt) then pcall(function() rec.RecipeType = rt end) end end
    if n.results then
        for i, s in ipairs(n.results) do local c = resolve_item_class(s); if _vv(c) then pcall(function() rec.Results[i].Item = c end) end end
    end
    -- ingredients: flatten the pool, assign across EVERY slot in EVERY set (no None left)
    local pool = {}
    if n.ingredient_sets then for _, set in ipairs(n.ingredient_sets) do for _, s in ipairs(set) do local c = resolve_item_class(s); if _vv(c) then pool[#pool+1] = c end end end end
    if #pool > 0 then
        local k = 0
        pcall(function()
            for si = 1, (rec.PossibleIngredients:GetArrayNum() or 0) do
                local set = rec.PossibleIngredients[si]
                local nn = 0; pcall(function() nn = set.Ingredients:GetArrayNum() end)
                for ii = 1, (nn or 0) do k = k + 1; set.Ingredients[ii].Item = pool[((k - 1) % #pool) + 1] end
            end
        end)
    end
    if n.results and n.results[1] then local rfb = resolve_item_class(n.results[1])
        if _vv(rfb) then pcall(function() for ri = 1, (rec.Results:GetArrayNum() or 0) do local cur; pcall(function() cur = rec.Results[ri].Item end); if not _vv(cur) then rec.Results[ri].Item = rfb end end end) end
    end
    if n.workbench_type then local wt = _load_obj(n.workbench_type)
        if _vv(wt) then pcall(function() for si = 1, (rec.PossibleIngredients:GetArrayNum() or 0) do rec.PossibleIngredients[si].WorkbenchType = wt end end) end
    end
    pcall(function() for si = 1, (rec.PossibleIngredients:GetArrayNum() or 0) do rec.PossibleIngredients[si].bEnabled = true end end)
    pcall(function() rec.bEnabled = true end)
    pcall(function() rec.bDefaultUnlocked = true end)
    return true
end

-- Registered recipes are held here so GC never frees the live object (native surfacing needs
-- it). The AssetRegistry has the ENTRY, but the loaded UObject must stay rooted separately.
local _registered = {}

-- THE modder-facing call: register + repair one recipe. Game-thread plain.
local function register_content(spec, mod_root, mod_id)
    local n, err = normalize(spec, mod_root)
    if not n then log.error(mod_id, "recipe spec invalid: %s", tostring(err)); return false end
    if n.registry_bin then
        local ok, merr = merge_registry(n.registry_bin, n.scan_path, mod_id)
        if not ok then log.warn(mod_id, "merge_registry failed (%s) — recipe may not register", tostring(merr)) end
    end
    local rec = _load_obj(n.package .. "." .. n.asset)
    if not _vv(rec) then log.error(mod_id, "recipe did not load: %s", n.package); return false end
    repair_recipe(rec, n, mod_id)
    -- ★ GC KEEP-ALIVE: nothing else roots the loaded recipe, so root it (Lua ref + engine-side
    -- PreloadedAssets) — else GC frees it after we return and native surfacing has no object.
    _registered[#_registered + 1] = rec
    if type(RegisterPreloadedAsset) == "function" then pcall(function() RegisterPreloadedAsset("Recipe", n.asset, rec) end) end
    -- diagnostics: prove every field resolved (None => silent bench-filter skip = "doesn't show")
    local function _nm(o) local s = "None"; pcall(function() if o and o:IsValid() then s = o:GetFName():ToString() end end); return s end
    local rn = "?"; pcall(function() rn = rec.RecipeName:ToString() end)
    local rtn = "?"; pcall(function() rtn = _nm(rec.RecipeType) end)
    local wtn = "?"; pcall(function() wtn = _nm(rec.PossibleIngredients[1].WorkbenchType) end)
    local res = "?"; pcall(function() res = _nm(rec.Results[1].Item) end)
    local sets = {}
    pcall(function()
        for si = 1, (rec.PossibleIngredients:GetArrayNum() or 0) do
            local set = rec.PossibleIngredients[si]; local p = {}
            for ii = 1, (set.Ingredients:GetArrayNum() or 0) do p[#p+1] = _nm(set.Ingredients[ii].Item) end
            sets[#sets+1] = "set" .. si .. "[" .. table.concat(p, ",") .. "]"
        end
    end)
    log.info(mod_id, "register_content OK: '%s' RT=%s WT=%s Result=%s ingredients=%s",
             tostring(rn), tostring(rtn), tostring(wtn), tostring(res), table.concat(sets, " "))
    return true
end
M.register_content = register_content

------------------------------------------------------------
-- World-load queue: mods declare recipes at mod-load (startup, no AssetManager yet); we
-- QUEUE them and run register_content at WORLD-LOAD (AssetManager exists, before the craft
-- UI builds its tiles -> the game surfaces them natively). One driver for all mods.
------------------------------------------------------------
local _queue    = {}
local _wl_done  = false
local _wl_hooked = false

local function _process_queue()
    if _wl_done then return end
    local am  = (FindAllOf("VeinAssetManager") or {})[1]
    local arh = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers")
    if not (am and arh and arh:IsValid()) then return end   -- not ready; retry next hook/tick
    _wl_done = true
    for _, q in ipairs(_queue) do pcall(register_content, q.spec, q.mod_root, q.mod_id) end
end

local function _ensure_worldload_hook()
    if _wl_hooked then return end
    _wl_hooked = true
    if RegisterInitGameStatePostHook then pcall(function() RegisterInitGameStatePostHook(function() ExecuteInGameThread(_process_queue) end) end) end
    if RegisterLoadMapPostHook       then pcall(function() RegisterLoadMapPostHook(function() ExecuteInGameThread(_process_queue) end) end) end
    if type(LoopAsync) == "function" then   -- fallback if hooks don't fire
        LoopAsync(1500, function() if not _wl_done then pcall(function() ExecuteInGameThread(_process_queue) end) end; return _wl_done end)
    end
end

--- Called by the loader per mod. Queues the mod's declared recipes for world-load registration.
function M.register_declared(recipes_list, mod_id, mod_root)
    local report = { prepared = 0, registered = 0, failed = 0 }
    if type(recipes_list) ~= "table" then return report end
    for _, spec in ipairs(recipes_list) do
        _queue[#_queue + 1] = { spec = spec, mod_id = mod_id, mod_root = mod_root }
        report.prepared = report.prepared + 1
    end
    report.registered = report.prepared   -- queued; actual registration fires at world-load
    _ensure_worldload_hook()
    return report
end

return M
