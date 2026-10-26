# Pudge Wars 0.1.6: dark scoreboard

The canonical release is `pudge-wars-basic:0.1.6`
(`cow_c026028d-8796-40fc-83a4-97e0a1007dae`). Browser source: `f1ab29d`.

The scoreboard uses a near-black background across both teams and the clock.
Muted red/blue team labels and a dark YOU badge retain team identification
without the previous bright background panels. Layout and gameplay are unchanged;
this release reuses 0.1.5's host image (simulator 38, wire protocol 14).

- Manifest: `sha256:8679e95f67513a51d2422ccfc6c4b33f4a3ae0cf3ef057571bd3d72f6469f9d8`
- Viewer: `sha256:3115a0709de5c7e300a201a742f9b83c238c9086ef98189c3ddc52bc30f45223`
- Browser: https://pudge-wars-site-theta.vercel.app/play/bundles/3115a0709de5c7e3/pw.html

Validation: clean-source WASM build, live local human/five-bot play with no
browser errors, visual inspection of the scoreboard, five hosted smoke matches,
and all ten hosted certification checks. Public and Observatory JS/WASM/data
files match the published SHA-256 pins. The league resolves to this canonical
release; the website's production COWORLD_ID and IDE runtime pins are updated.
