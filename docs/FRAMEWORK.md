# Vein Toolkit — Framework & Internals

This is the doc for **extending** the toolkit — adding recipes in bulk, hacking on the framework
itself, or branching into new content types. If you just want to make a recipe, read
[MAKING_RECIPES.md](MAKING_RECIPES.md) instead.

---

## The core idea: attack the engine, not the game

VEIN is built on Unreal Engine. UE's core (the AssetManager, the asset registry, UObject
reflection) is *Epic's* code — the same in every UE5 game. So instead of hacking VEIN's specific
systems, the toolkit works at the **engine layer**: it registers new content the way the engine
itself does, and lets the game surface it natively. That's why it's additive, crash-light, and
why the same approach ports to other UE games.

## How a recipe actually gets into the game (the pipeline)

```
cook ─► mount ─► register ─► repair ─► root ─► (game displays + crafts it natively)
```

1. **Cook** — you make a `BaseRecipe` Data Asset shell in Unreal and cook it (versioned). It's a
   real, registry-discoverable primary asset of type `Recipe`. (This is the only UE step.)
2. **Mount** — the cooked `.uasset` ships in a `.pak`; UE4SS's pak loader mounts it.
3. **Register** — at **world-load** the framework additively merges your cooked `AssetRegistry.bin`
   into the live AssetManager (`FAssetRegistryState::AppendState`) and scans the path, so the
   `Recipe` asset map goes from N → N+1. The recipe is now known to the game's own systems.
4. **Repair** — a cooked asset loaded from a mod pak comes back with **null** references (mod-pak
   class imports don't bind to base-game classes). So the framework sets them at runtime via
   reflection: RecipeType, ingredient/result item classes, WorkbenchType, flags.
5. **Root** — the loaded recipe UObject is held alive (Lua ref + `RegisterPreloadedAsset`) so GC
   doesn't free it right after registration.
6. **Native surfacing** — because all of that happens *before* the craft UI builds its tile list,
   the game includes the recipe itself: real icon, tooltip, ingredients, crafting. **No widget
   injection.**

Why world-load timing matters: the workbench/craft menu sources its recipe list once, at build
time. Register + repair *before* that and the game does the display for free.

## Repo layout

| Path | What |
|------|------|
| `runtime/ue4ss/Mods/VeinCF/Scripts/` | the framework (Lua) |
| `runtime/ue4ss/Mods/VeinCF/Scripts/modules/recipes.lua` | **the heart** — register_content, merge_registry, repair |
| `runtime/ue4ss/Mods/VeinCF/Scripts/modules/loader.lua` | discovers mods, mounts paks, queues recipes for world-load |
| `runtime/ue4ss/Mods/VeinCF/Scripts/modules/manifest.lua` | parses + validates `manifest.json` |
| `src/veincf_natives/LuaMod.cpp` | the custom DLL functions (the engine toolkit) |
| `src/ue_recipe_stub/` | the C++ stub classes for cooking shells |

## Manifest reference (`manifest.json`)

```jsonc
{
  "manifest_version": 1,
  "id": "my_mod",                 // must equal the folder name
  "name": "My Mod",
  "version": "1.0.0",             // semver
  "author": "You",
  "requires": { "veincf": ">=0.1.0" },
  "paks": ["MyRecipes_P.pak"],    // cooked paks to mount (relative to mod folder)
  "recipes": [
    {
      "asset": "/Game/Vein/.../CR_X",     // the cooked recipe's content path (required)
      "registry_bin": "AssetRegistry.bin", // cooked registry, relative to mod folder
      "makes":  ["/Game/.../BP_Result"],   // result item path(s)
      "needs":  ["/Game/.../BP_A", "/Game/.../BP_B"],  // ingredients — ARRAY = AND (all required)
      "needs_any": [["/Game/.../BP_A"], ["/Game/.../BP_B"]], // optional: sets = OR (alternatives)
      "tab":   "Weapons",          // friendly -> RT_Weapons (or pass a full /Game/.../RT_X path)
      "bench": "Standard"          // friendly -> WT_Standard (or a full /Game/.../WT_X path)
    }
  ]
}
```
Friendly `tab`/`bench` names map to `RT_<name>` / `WT_<name>`. Items resolve by full path, or by
short blueprint name (`BP_Banana`) if already loaded. The explicit form
(`results` / `ingredient_sets` / `recipe_type` / `workbench_type`) is also accepted.

## The `veincf.*` Lua API (for mods that want code)

A mod can also ship a Lua entrypoint (declare it in `entrypoints.main`) and call:

| API | What |
|-----|------|
| `veincf.recipes.register_content(spec, mod_root, mod_id)` | the whole pipeline for one recipe spec |
| `veincf.recipes.add{recipe_name, category, ...}` | inject a tile widget (legacy display path) |
| `veincf.recipes.modify(name, {field=value})` | reflection-edit an existing recipe |
| `veincf.recipes.get_recipe(name)` / `get_all_recipes()` | look up live recipes |
| `veincf.recipes.raw.{merge_registry, repair, ...}` | the building blocks, if you compose your own |
| `veincf.log.{info,warn,error}` | scoped logging to `UE4SS.log` |
| `veincf.config.get(key)` | per-mod config |

Most recipe mods need **none** of this — the manifest drives it all. The API is for advanced
content or new tooling.

## The engine toolkit (custom DLL natives)

`LuaMod.cpp` exposes universal, SEH-guarded primitives — the reusable part that makes new content
types possible. Highlights:

- `ReadU64`, `DisasmFunction` (Zydis), `CallNative`, `CallVirtual` — read/follow/call any native fn
- `FindStringRefs`, `FindCallersOf`, `ScanThunkCalls` — locate functions with no symbols
- `ReadFNameAt`, `ResolveFName` — walk FName-keyed memory (TMap keys)
- `MergeRegistryFromDisk`, `ScanPathsForType`, `RegisterPreloadedAsset` — content registration
- `DumpClassProperties`, `CopyAllProperties`, `GetObjectAt` — reflection helpers

These are how `merge_registry` resolves `LoadFromDisk`/`AppendState` at runtime without hardcoded
offsets — so it survives game updates better than a fixed-address approach.

## Extending it — adding a new content type

Recipes are a `Data Asset` (the easy case). Other content (items, gear, guns) are **Blueprint
classes** with data on the CDO — same registration *pattern*, different shell. To add a type:

1. **Stub the class** — write a C++ stub for the type's parent (e.g. `FoodItem`, `FirearmItem`)
   from the `.usmap` / FModel, like `src/ue_recipe_stub/BaseRecipe.h`.
2. **Author a shell** — a Blueprint child of that stub (vs a Data Asset), cook it.
3. **Register** — the merge is type-agnostic; scan for that primary-asset type instead of `Recipe`.
4. **Repair** — generalize the repair to set the type's CDO fields (make it declarative so the
   manifest describes the field→value/ref repairs — that's the lever that makes type #3, #4 free).
5. **Gate to watch:** does the new primary-asset type register the same way `Recipe` does, and does
   the loaded object stay rooted. Those are the two things that bit recipes; expect the same.

## The dev loop

- **Lua change** (Scripts): reload with UE4SS's hot-reload, or relaunch.
- **DLL change** (`LuaMod.cpp`): rebuild + redeploy `UE4SS.dll`, relaunch (game closed to deploy).
- **New cooked content**: cook + pak in UE, then relaunch.
- Read `UE4SS.log` for framework logs (`[your_mod] register_content OK: ...`).
