# hookem 0.1.0 — 2026-10-26

New, separate Coworld `hookem`, ID `cow_38363d7c-d7e7-4559-b2e6-626707f5da39`.
Pudge Wars listing, website, game IDs and leagues are unchanged.

Human wall-clock pacing is now 32 TPS. The bottom-left HUD shows measured TPS,
target TPS and FPS. Fixed simulation outcomes, timing in ticks, and replay hashes
are unchanged. Cowboys use overhead rope swings, casts and gathering animations;
the lasso loops have no inward-facing spikes.

- Local preview: http://127.0.0.1:8766/
- Public browser: https://hookem-polyworld.vercel.app
- Immutable client: https://hookem-polyworld.vercel.app/builds/12c19343500af5e2/index.html
- Source: `b9726ec` on `hookem-western`.
- Manifest: `sha256:94517b673c0072f585f8257f7ee070e4fceb0db799bd79289c18d504b9e2909d`.

Pacing regressions and browser-launcher tests pass. The public WASM runs live
with no JavaScript errors. Downloaded JS, WASM and data match the local deployed
bundle by SHA-256. The registered replay viewer has identical WASM and data;
its JS differs only in Emscripten temporary-file comments.

Publication status is recorded in `coworld/hookem-deployment.json`. Hosted
certification is asynchronous; an uploaded public version is not necessarily
canonical until the platform reports certification success.
