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

## What you need (read this first)
**To USE recipe mods** (install + play someone's recipes): just the game + this toolkit. Copy it
in, done. No tools, no coding.

**To MAKE your own recipes**: you *also* need **Unreal Engine 5.6** and the ability to **build a
C++ UE project** (Visual Studio). You cook a small recipe "shell" in Unreal — it's the only step
that touches UE. The full steps are in **[docs/MAKING_RECIPES.md](docs/MAKING_RECIPES.md)**.

> If you don't have Unreal or don't know how to use it: that's the prerequisite, not a bug. Go
> install it and follow the guide — the instructions are complete and in plain English. The rest
> is on you.

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
Banana Plunger (Banana + Nail → Plunger, at the Standard workbench). **To try it:** copy the
`banana_plunger` folder into `ue4ss/Mods/VeinCF/mods/` and launch — it's in the Weapons tab.

## Extending it / continuing the work
Want to bulk-add recipes, hack on the framework, or branch into new content types? Read
**[docs/FRAMEWORK.md](docs/FRAMEWORK.md)** — the architecture, the manifest reference, the CF Lua
API, the engine toolkit, and how to add a new content type.

## FAQ
- **Do I need Unreal Engine?** To *make* recipes, yes (to cook the shell). To *use* recipes someone
  else made, no.
- **Do I need to code?** No to use. Basically no to make — you set values and run a cook command —
  but you do need to install Unreal and follow the cook steps.
- **Nothing shows up / it crashed.** Check `ue4ss/UE4SS.log` for the `VeinCF` lines. Usual causes:
  a wrong content path in the manifest, or the pak/registry not matching your game version.
- **Will it break when VEIN updates?** Possibly — the runtime is built for a specific VEIN version
  and cooked content is version-matched. A big game patch may need an updated build.
- **Can I make new items / guns?** Not in v1. v1 is recipes (combining existing items). New item
  types are a future version.

## Credits & license
Vein Toolkit is **MIT licensed** — see **[LICENSE](LICENSE)**. Built on **RE-UE4SS** (MIT) with
the original VEIN port by **xmathayus**; full credits and third-party license text in
**[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)**. Vein Toolkit by **Alustrial**.
