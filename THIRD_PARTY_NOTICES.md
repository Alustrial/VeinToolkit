# Third-Party Notices & Credits

Vein Toolkit stands on the work of others. Credit where it's due.

## RE-UE4SS (the foundation)
Vein Toolkit's runtime DLL is a fork of **RE-UE4SS** — the Unreal Engine scripting
system that makes all of this possible.

- Project: https://github.com/UE4SS-RE/RE-UE4SS
- Docs: https://docs.ue4ss.com
- License: **MIT** (see below)

```
MIT License

Copyright (c) 2022 Narknon

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Plus thanks to the wider UE4SS-RE team and contributors credited in the upstream
project (CasualGamer, SunBeam, Archengius, trumank, localcc, and many others).

## xmathayus — the original VEIN port
**xmathayus** did the original VEIN port of RE-UE4SS — the first attempt to get UE4SS
running on VEIN, which seeded this work. That fork is no longer maintained/working, so the
runtime here is built from a reworked VEIN fork (below), but credit where it started. Thanks.

## VEIN RE-UE4SS fork (the working base)
The `UE4SS.dll` shipped in `runtime/` is built from a reworked, working VEIN port of RE-UE4SS
maintained by **Alustrial** (the original being broken). Still RE-UE4SS under the hood (MIT,
above); see `src/README.md` to rebuild.

## Zydis
Used by the runtime for x86-64 disassembly during native resolution.
- https://github.com/zyantific/zydis — MIT License

## FModel
Not bundled, but the recommended tool for inspecting VEIN's assets and finding
the content paths you reference in recipes.
- https://fmodel.app

## Vein Toolkit
By **Alustrial**. The recipe-content framework, the manifest system, and the
custom natives layered on top of the above.
