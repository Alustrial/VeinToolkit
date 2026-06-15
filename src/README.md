# Source

You don't need any of this to *use* Vein Toolkit — the runtime is prebuilt in `runtime/`.
This folder is here for transparency and for anyone who wants to rebuild.

## `veincf_natives/` — the custom DLL functions
`LuaMod.cpp` is the file we modified inside the UE4SS fork. Our additions are the native Lua
functions the recipe framework calls (registry merge, native resolution, reflection helpers,
`RegisterPreloadedAsset`, etc.).

**To build the DLL:**
1. Get the working VEIN RE-UE4SS fork — **`<our fork repo URL — TBD>`**. (Note: the original
   xmathayus VEIN port is broken/unmaintained; this fork is the working base.)
2. Drop this `LuaMod.cpp` in at `UE4SS/src/Mod/LuaMod.cpp`.
3. Build (`build_veincf.bat`, or `cmake --build ... --target UE4SS`).
4. The output `UE4SS.dll` is what ships in `runtime/`.

The DLL is a fork of RE-UE4SS (MIT). Credit/history in `../THIRD_PARTY_NOTICES.md`.

## `ue_recipe_stub/` — the cook stub classes
`BaseRecipe.h` / `RecipeType.h` / `WorkbenchType.h` are the minimal C++ classes you add to a
VEIN UE project so you can author + cook recipe shells (see `docs/MAKING_RECIPES.md`, step A).
They mirror VEIN's real classes so the cooked asset binds correctly at runtime.
