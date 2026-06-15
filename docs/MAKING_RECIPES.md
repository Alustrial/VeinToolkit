# Making a New Recipe

A recipe mod has two halves: **(A)** make a recipe *shell* in Unreal (cook + pak — the only
part that touches UE), and **(B)** wire it up with a JSON manifest. Half B is trivial; half A
is a copy-paste-and-cook once you've done it once.

> You only ever combine and re-stat **existing** game content. No 3D modeling, no new assets.

---

## A. Make the recipe shell (Unreal)

You need the VEIN UE project with the `BaseRecipe` class (included in `src/`). One-time setup:
open it in Unreal Editor.

### A1. Author the asset
**Right-click → Miscellaneous → Data Asset → BaseRecipe.** Name it (e.g. `CR_MyThing`), put it
in any folder under `Content/Vein/`. Set **only** these — leave everything else default/`None`:

| Field | Value | Why |
|---|---|---|
| **RecipeName** | "My Thing" | The display name. Baked in — not set by the manifest. |
| **Possible Ingredients** | **1** set | Holds the ingredients |
| └ that set's **Ingredients** | **N** entries, each `Item = None` | One per ingredient; the entries must exist, but leave items `None` |
| **Results** | **N** entries, each `Item = None` | Usually 1 |

**AND vs OR:**
- **1 set with N ingredients = AND** (needs all of them) ← the normal case
- **Multiple sets = OR** (craftable with set A *or* set B)

Do **not** pick items/RecipeType/WorkbenchType in the asset — those come from the manifest at
runtime. The asset is a shell: a name + the right number of empty slots.

### A2. Cook it (VERSIONED — never `-unversioned`)
```
UnrealEditor-Cmd.exe "<YourProject>.uproject" -run=Cook -targetplatform=Windows -CookDir="<...>\Content\Vein\<YourFolder>" -unattended -nopause
```
(Close the editor first — it locks the project.) Produces, under `Saved\Cooked\Windows\Vein\`:
- `Content\Vein\<YourFolder>\CR_MyThing.uasset` + `.uexp`
- `AssetRegistry.bin`  ← your registry file

### A3. Pak it
Filelist (`mypak.txt`):
```
"<...>\Saved\Cooked\Windows\Vein\Content\Vein\<YourFolder>\CR_MyThing.uasset" "../../../Vein/Content/Vein/<YourFolder>/CR_MyThing.uasset"
"<...>\Saved\Cooked\Windows\Vein\Content\Vein\<YourFolder>\CR_MyThing.uexp" "../../../Vein/Content/Vein/<YourFolder>/CR_MyThing.uexp"
```
```
UnrealPak.exe "MyRecipes_P.pak" -create="mypak.txt"
```

---

## B. Wire it (the manifest)

Make a folder in `Mods/VeinCF/mods/` with three files:
```
my_mod/
├── manifest.json
├── MyRecipes_P.pak       # from A3
└── AssetRegistry.bin     # from A2
```

`manifest.json`:
```json
{
  "manifest_version": 1,
  "id": "my_mod",
  "name": "My Recipe",
  "version": "1.0.0",
  "author": "YourName",
  "requires": { "veincf": ">=0.1.0" },
  "paks": ["MyRecipes_P.pak"],
  "recipes": [
    {
      "asset": "/Game/Vein/<YourFolder>/CR_MyThing",
      "registry_bin": "AssetRegistry.bin",
      "makes": ["/Game/Vein/Items/.../BP_Result"],
      "needs": ["/Game/Vein/Items/.../BP_IngredientA", "/Game/Vein/Items/.../BP_IngredientB"],
      "tab": "Weapons",
      "bench": "Standard"
    }
  ]
}
```

Field notes:
- **`asset`** — the recipe's content path (matches where you cooked it). `id` must equal the folder name.
- **`makes` / `needs`** — full item content paths (get them from FModel). `needs` array = AND.
- **`tab`** — the category tab → `RT_<Tab>`. Valid: `Fuel, Medical, Gadgets, Weapons, Cooking,
  Brewing, Farming, Slicing, Materials, StandardParts, AdvancedParts, FabricatedParts, Special`.
- **`bench`** — where it crafts → `WT_<Bench>`. Valid: `Personal` (hand-craft), `Standard`,
  `Advanced`, `Fabrication`, `Chemistry`, `Repair`, `Stove`, `Schematic`.

---

## C. Run it
Drop `my_mod/` in `Mods/VeinCF/mods/` → launch → it's in the game, craftable, on launch.

---

## Gotchas (the stuff that's easy to miss)
- **Slot entries must exist** (with `Item = None`) — the runtime fills them but can't create them.
- **1 set = AND, multiple sets = OR.**
- **RecipeName is baked** into the asset; everything else (items/tab/bench) comes from the manifest.
- Cook **VERSIONED**, never `-unversioned` (unversioned mis-binds and reads garbage).
- The pak holds **only the recipe** — never put `AssetRegistry.bin` *inside* the pak; it ships
  *beside* the pak in your mod folder.
- Ingredient/result items must already exist in the game — you reference them, you don't create them.
