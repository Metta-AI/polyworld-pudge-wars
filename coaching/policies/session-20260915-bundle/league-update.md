# League update: pudge-wars-rusher:v16

The exact retained E06b combined coaching policy is now the active 3v3 scoring
champion in Pudge Wars. A separate API read verified `competing`, `active`, and
`is_champion=true` at 2026-09-16T02:05:57.776453+00:00.

- Policy version: `bdc7ac29-743d-4ace-b1cc-3b0529cef552`.
- Membership: `lpm_9ea237d9-25d6-4578-a8a3-7a3620c36a25`.
- League: `league_84ab9f1e-5fb8-4b62-a3ac-e49026bd12d0`.
- Submission: `sub_5008e920-16db-42cc-b073-91bf584ce914`.
- Policy SHA-256: `26d787a61bfc20b58dc261965558e50395bf2eb8cee1e21aa2531101333ac7ea`.
- Uploaded image digest: `sha256:d8413008c797bd6bb206d0aec735b8b2e12f640b3623d5088e5cd325b75db4d8`.
- IR: [retained.ir.md](retained.ir.md); policy: [retained.policy.py](retained.policy.py).
- User authorization: “update policy on league”.

## Validation and limits

Native confirmation was 67 wins in 96 games against v14, with mean kill margin
+7.1458 and seed-bootstrap 95% interval [4.9479, 9.1979]. The separate screen was
38/48. The exact uploaded image passed 1,004 semantic/lifecycle probes.

All ten short hosted runtime episodes on Coworld 0.3.21 completed. Each of the
30 candidate processes connected in combined mode, threw hooks, and logged a
clean final exit without a traceback. The request was
`xreq_89c3f929-0f24-4311-8b70-b27cefa9cb3b`: 960 ticks per match against pinned
Richard v7. These checks establish runtime operation, not hosted competitive
improvement. Fresh hosted A/B strength and a broad-field guardrail remain
unmeasured. This publication follows the user's explicit update instruction
based on the already disclosed native evidence.

The old v14 behavior suite has 39 passing checks and three movement expectations
changed by the requested CurveHook priority: shop travel, rally movement, and
fishing spacing during a hook. The new complete-package contracts pass. No
selected policy bytes or legacy test source were changed to obtain this result.

## Provenance and rollback

The semantic IR and selected symbolic policy are unchanged from the validated
E06b pair. Captured session inputs and original coaching evidence still match
their recorded hashes. Full deployment evidence is in
`duels/coaching-20260915-bundle-hosted`; the JSON companion pins the session export.

The 1v1 champion remains unchanged. v14 remains available for rollback by
promoting membership `lpm_a897a072-a07b-4aef-90fe-ef6e256640b5` and verifying its
champion flag. This submission uses `auto_champion=never`; v16 was promoted
explicitly once.
