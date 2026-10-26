# Pudge Wars 0.1.4 release

The BASIC league and public browser client now use certified, canonical
`pudge-wars-basic:0.1.4` (`cow_1138ecba-2cd6-4115-9194-bc3cb5521643`).

The release combines main's HUD readability changes with the already deployed
simulator-38 human-play branch. Main alone was simulator 37 and could not join
the deployed wire-protocol-14 host. The merged engine is `cd8111a`; browser
asset packaging (including the Grapple icon) is `2ffb5cc`.

- Manifest: `sha256:7b2bd24443156b38232d45ee87a8f9526da56762fe2b407513f72d8ddfb304ec`
- Browser bundle: `sha256:5fb1947dbfb26bae7c5ebee8167d1d838ce1ef3e7e8a4c22dc76a50e1848c8c6`
- Browser URL: https://pudge-wars-site-theta.vercel.app/play/bundles/5fb1947dbfb26bae/pw.html
- The site's production COWORLD_ID points to the release above. Older immutable
  browser bundles are retained for existing sessions.
- The desktop runtime manifest pins these exact published files. Its local
  BASIC bot was updated together with the interpreter; the old bot failed with
  exact-int32 errors. Previous Coworld versions retain separate verified pins.

Validation: full native league suite; mixed human/BASIC joins, reconnect,
seat isolation and pacing; all ten hosted certification steps and five smoke
episodes; real WASM local play and a native-hosted human seat with five BASIC
bots (ticks and scoring advance without protocol or replay-hash errors).
The production registry and league were read back to confirm the canonical ID.

0.1.3 was the intermediate certified release before adding the missing browser
Grapple icon. 0.1.4 reuses its exact host image with the corrected viewer.
