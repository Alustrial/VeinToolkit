# Vein Toolkit

A modding framework for **VEIN** that lets you add **new craftable recipes** to the game —
on launch, no buttons, no editing game files. You write a small JSON manifest; the toolkit
registers your recipe into the game's own crafting system so it shows up and crafts natively.

> **v1 — Recipes.** Future versions add more (items, gear, and beyond). v1 does recipes, and
> does them properly: net-new recipes, native display, real crafting.

## What it can do (v1)
- Add **new recipes** that craft *any existing item* from *any existing ingredients*
- Pick the **category tab** (Weapons, Fuel, Medical, Gadgets, …) and the **bench** it crafts at
- Zero art, zero Lua — a recipe is a small cooked shell + a few lines of JSON
- Recipes are **additive** — nothing existing is overwritten

## Install (drop-in)
Copy the **contents of `runtime/`** into `Vein/Vein/Binaries/Win64/`:
- `runtime/dwmapi.dll`  → `Binaries/Win64/dwmapi.dll`
- `runtime/ue4ss/`      → `Binaries/Win64/ue4ss/`

That's the complete runtime (UE4SS + the VEIN signatures + the pak loader + VeinCF). Launch the
game once and check `Binaries/Win64/ue4ss/UE4SS.log` for the `VeinCF` startup banner.

> Already running UE4SS? Just replace your `ue4ss/UE4SS.dll` with this one and copy
> `ue4ss/Mods/VeinCF/` in.

## Make a recipe
See **[docs/MAKING_RECIPES.md](docs/MAKING_RECIPES.md)** for the full walkthrough.

The short version — a recipe mod is just a folder you drop in `Mods/VeinCF/mods/`:
```
my_mod/
├── manifest.json        # the recipe(s), in plain JSON
├── MyRecipes_P.pak      # the cooked recipe shell(s)
└── AssetRegistry.bin    # cooked alongside the pak
```
And the recipe itself reads like English:
```json
"recipes": [{
  "asset": "/Game/Vein/New/CR_MyThing",
  "registry_bin": "AssetRegistry.bin",
  "makes": ["/Game/Vein/Items/.../BP_Result"],
  "needs": ["/Game/Vein/Items/.../BP_IngredientA", "/Game/Vein/Items/.../BP_IngredientB"],
  "tab": "Weapons",
  "bench": "Standard"
}]
```

A working example is in **[examples/banana_plunger/](examples/banana_plunger/)** — a craftable
Banana Plunger (Banana + Nail → Plunger, at the Standard workbench).

## Credits & license
Built on **RE-UE4SS** (MIT) and **xmathayus's** VEIN port. Full credits and license text in
**[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)**. Vein Toolkit by **Alustrial**.
