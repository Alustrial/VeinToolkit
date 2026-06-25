# Vein Toolkit

A modding framework for **VEIN**, in two halves:
- **Content** — add **new craftable recipes** that show up and craft in the game's own system, from a
  small JSON manifest. No editing game files.
- **Scripting** — write small **Lua** mods against a clean verb API (`veincf.world.spawn`,
  `veincf.world.on`, `veincf.player.heal`, …) to make things *happen* in the live game: spawn, hook
  events, mechanics, timers. No Unreal editor, no reverse-engineering the game.

> **Recipes = what exists; scripting = how it behaves.** Most mods use one or the other; big ones use
> both. All of it is zero-art, runs on launch, and nothing existing is overwritten.

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

## Scripting — make things *happen* (the verb kit)
Recipes add *content*; scripting adds *behavior*. A script mod is just a folder with a `manifest.json`
and a `scripts/main.lua` — drop it in `Mods/VeinCF/mods/`, and your Lua runs in the live game with the
`veincf` API in scope. **No pak, no Unreal.**

```lua
-- the whole mod: log a line every time a zombie dies
veincf.world.on("BP_Zombie_C", "OnDeath", function(who)
    veincf.log.info("another one down")
end)
```

The verbs (the framework gives you the blocks; the *mechanic* is your script):

| Namespace | Verbs |
|-----------|-------|
| `veincf.world`  | `spawn(class, opts)` (body + AI), `on(class,"Event",fn)` / `off`, `is_dead`, `get_health`, `destroy`, `find`, `find_class`, `set_weather`, `add_time`, `teleport_to`, `explosion`, `zombify` |
| `veincf.player` | `heal`, `damage`, `give_item(name,n)`, `has_item(class)`, `remove_amount(class,n)`, `set_condition(name,amt)`, `add_xp`, `power_up`, `get_health/conditions/stats/inventory` |
| `veincf.actor`  | `location`, `set_location`, `set_scale`, `distance` |
| `veincf.timer`  | `loop(ms,fn)` (return `true` to stop), `after(ms,fn)`, `cancel(handle)` |

A handful of verbs compose into a real mechanic — a self-refilling brood encounter, "when a zombie dies
two more rise," heal-on-kill, a triggered ambush. Runnable examples are in **[examples/](examples/)**
(`death_message`, `they_multiply`) — drop a folder into `Mods/VeinCF/mods/` and launch.

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

## Source / rebuilding
This repo ships the prebuilt runtime so you can just *use* it. The DLL is compiled from the VEIN
UE4SS fork — **https://github.com/Alustrial/UE4SS-Vein** — which is the engine base (UE4SS + VEIN
signatures + stability patches). You only need that repo if you want to **rebuild or extend the
DLL itself**; the recipe framework (Lua) is right here in `runtime/.../VeinCF/` and `src/`.

## Credits & license
Vein Toolkit is **MIT licensed** — see **[LICENSE](LICENSE)**. Built on **RE-UE4SS** (MIT) with
the original VEIN port by **xmathayus**; full credits and third-party license text in
**[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)**. Vein Toolkit by **Alustrial**.
