# Pudge Wars replay startup fix — 0.1.9 (2026-10-27)

The Observatory replay viewer loaded its WASM, then crashed before drawing the first frame. Its touch-device probe used `emscripten_run_script_int`, which evaluates a JavaScript string. Observatory's Content Security Policy intentionally permits WebAssembly without permitting JavaScript `eval`.

Commit `ad1174ef44661d75fc86d688239740c798b4347b` compiles the probe with `EM_ASM_INT`. Replay startup also skips the optional decorative loading scene, whose CDN module import is blocked by the same policy. The normal progress indicator remains available. No CSP permissions were relaxed.

## Published release

- Coworld: `cow_d96d9b33-32d7-4ab3-b41d-6f84a29808a3`, `pudge-wars-basic:0.1.9`.
- Manifest: `sha256:8dca6e73709aaf1a1449224e2565a8bd301e09569c68753c14288a5c309e6e73`.
- Replay viewer: `sha256:3207f251a64aa8ff246a56a7349d79437353fc7fcb09f07313feb41fff8e0cdf`.
- Certification: certified and canonical; five hosted smoke episodes completed.
- Server image: unchanged from 0.1.8, `public.ecr.aws/q5f4m8t9/cogames@sha256:01caef1ddfcf33cc83d1be502a2f5cdb0c41d78d3046a3b1e25592240e996bc0`.
- Bundled policies and hosted live-client URL: unchanged from 0.1.8.

This release is canonical Pudge Wars. Hookem remains in its separate worktree.

## Verification

- Built the replay viewer with `coworld/tools/build_replay_viewer.sh`.
- `tests/test_pw_replay_browser.mjs` played the reported recording on desktop and touch layouts under Observatory's exact CSP; both advanced past tick 64 without browser errors or desyncs.
- Headless verification replayed all 12,127 ticks and 103,858 recorded actions with matching hashes. Final score: West 30, East 9.

To run the browser regression, supply a built viewer directory and a replay artifact:

```sh
node tests/test_pw_replay_browser.mjs path/to/viewer path/to/episode.replay
```

Set `PLAYWRIGHT_MODULE` to an absolute Playwright module path if it is installed outside this repository. `REPLAY_SCREENSHOT_DIR` optionally saves desktop and touch screenshots.

## Historical replay links

Existing Observatory URLs pin the original Coworld ID and its immutable viewer bundle. Publishing 0.1.9 does not replace the broken viewer embedded by 0.1.8 links. Substituting the new Coworld ID in a historical Observatory URL fails the platform's replay/version association check.

The public content-origin viewer serves the fixed bundle independently of that page. [Watch the reported recording with the corrected viewer](https://api.observatory.softmax-research.net/v2/coworlds/replays/static/cow_d96d9b33-32d7-4ab3-b41d-6f84a29808a3/sha256%3A8dca6e73709aaf1a1449224e2565a8bd301e09569c68753c14288a5c309e6e73/index.html?v=2&replay=https%3A%2F%2Fd1kovwradqjymp.cloudfront.net%2Freplays%2F8b16b44b-62bb-4162-b586-b3fcf6a0ec42.replay). Verified HTTP 200, a rendered arena screenshot, replay progress through tick 101, and no browser errors.

The authenticated session endpoint returned HTTP 500 for a new private smoke recording (request ID `f127c2e2-5b7e-4a8b-8988-fc1c417a8349`); that separate platform session issue was not changed in this game-only fix.
