# Pudge Wars 0.1.5: compact HUD

The canonical BASIC release is `pudge-wars-basic:0.1.5`
(`cow_20ccb941-a3e4-4cf1-9cb3-f7376cb61dac`). Its browser client is built
from `ab2f756`. It reuses 0.1.4's certified host image: simulator 38 and wire
protocol 14 are unchanged.

The score banner is 440 × 44 HUD units (formerly 765 × 66), the minimap
panel is 208 × 240 (formerly 334 × 338), and the empty-bag hero bar is
672 × 88 (formerly 793 × 108). HUD scaling follows display density without
enlarging panels to fill wider windows. Live players no longer see replay
controls. Event messages wrap within their own column, with a shadow for
contrast and a position below the scoreboard when the side column cannot fit.

- Manifest: `sha256:81862e632d5b721ffcfda51a583924dc9d544c2cc077bd961a20ee9a56b8e779`
- Viewer bundle: `sha256:c3ff4c068f9100d1f2517f6e5cc77a78da33648256d9e1ca789b2cadbbc1212e`
- Browser: https://pudge-wars-site-theta.vercel.app/play/bundles/c3ff4c068f9100d1/pw.html
- IDE runtime update: `Metta-AI/coplay` commit `61e431e`. Previous releases
  remain pinned separately for existing lobbies.

Validation: WASM build; local human plus five BASIC bots; native-hosted human
plus five BASIC bots; screenshots at 1280, 1440, 1920, and 2560 widths and 2×
display density; a visual fixture using the long player names from the reported
cut-off events; five hosted smoke episodes and all ten hosted certification
checks. Public and Observatory JS/WASM/data downloads match their SHA-256 pins.
The signed desktop package passed its real-game boot/play test and was installed.

Desktop runtime/league unit checks and all five game-loading UI checks passed.
The separate embedded-game fullscreen test failed twice at its third native
fullscreen toggle (`tests/embedded-game.spec.mjs:110`); this release does not
modify that test or the fullscreen implementation.
