# Fresh Meat 0.1.7

Public game and ranked league names are now **Fresh Meat**. The supplied transparent logo appears on the website, game loading screen, IDE library, native icon exports, social preview, and published Coworld store page.

- Game source: `4d0530027cf20338b1d1131f191902c515e5087f`
- Coworld: `cow_ff292018-326f-4c2b-a64f-d6594ac52600` (canonical, all 5 hosted smoke episodes and 10 certification steps passed)
- Manifest: `sha256:1396bcebe89ab07a0e2e49d7adb2d6af179359783250e9cb6ed5b2f2c067594d`
- Browser bundle: `sha256:ad206cd384687db535259c95dbf4d2ba3f57bcdb2ac0f2cd9370b3f4ad2cbf68`
- Browser: https://pudge-wars-site-theta.vercel.app/play/bundles/ad206cd384687db5/pw.html
- Production site: https://pudge-wars-site-theta.vercel.app
- Vercel deployment: `dpl_FqcgkRmxfhJ9gSCikqoMDyHoTQWH`
- Simulator 38; wire protocol 14.
- IDE source: `f8c97b2`, using the same verified browser files.

The existing `pudge-wars-basic` namespace, game ID, league ID `league_84ab9f1e-5fb8-4b62-a3ac-e49026bd12d0`, division, policies, ratings, saves and historical replay pins are preserved. The game display-name override and league seed display name both read Fresh Meat. The store-page artwork revision is `spr_4ca9488e-fd94-4ab4-90f7-47d36953c8db` (published).

Validation: browser gameplay boot, movement and cast with no JavaScript errors; production title, logo and social image HTTP checks; byte-for-byte verification of API-served JS/WASM/data; 45 targeted IDE tests; IDE syntax/UI build; packaged macOS gameplay and logo test. Website source was deployed from the existing production snapshot with branding and bundle updates, preserving unrelated work in the website checkout.
