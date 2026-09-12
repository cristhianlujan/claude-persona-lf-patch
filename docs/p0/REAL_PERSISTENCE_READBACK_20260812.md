# REAL PERSISTENCE READBACK — 2026-08-12

## Fuente real recuperada

External durable evidence:

- external ref: `DRIVE-P0-HUMAN-REVIEW-V3-20260810-01`
- source execution: `EXEC-P0-VQ-FINAL-20260810`
- provider: Google Drive
- packet: `P0_HUMAN_REVIEW_V3_20260810.zip`
- bytes: `5,023,337`
- SHA-256: `acfa623917fc8fb9058a6908cd0908584dfbc163a83fe5e72eb04b47c73d433e`
- authenticated download readback: verified
- source image SHA-256: `e308b66778d1108241e2832997f6628f47841d7da1fc53820007834fdbb720d7`

The Drive packet was downloaded again during this continuation and recomputed to the exact registered SHA-256.

## Normalized execution

`EXEC-P0-REAL-PERSIST-NORM-20260812-001`

Configuration:

- `P0-PERSISTENCE-NORMALIZATION-v1`
- configuration SHA-256: `0785b977fc3f2117e2b28be93060c59b00368554ac6d44ca30b09ec553edb0ac`
- code HEAD bound at normalization: `40e7fe010cdee25ba4de2d283bd16125c2ef399f`

Readback:

| Item | Count |
|---|---:|
| real consolidated elements | 97 |
| real crop evidence units | 97 |
| element→evidence links | 97 |
| records | 6 |
| artifacts | 6 |
| transitions | 3 |
| orphan parents | 0 |
| elements without evidence | 0 |
| orphan evidence | 0 |

Request fingerprint:

`3f1c57acaaeea847179c518a7351b82f8256025063675e1b246b837eadb8dc42`

## Integrity links

The normalized graph binds:

- source image + exact SHA;
- 97 preserved regions and parent relationships;
- one real crop evidence unit per consolidated element;
- receipt;
- packet manifest;
- machine audit;
- normalization configuration;
- external durable packet reference with authenticated readback.

## Verdict

`BLOCKED_REAL_EVIDENCE`

This is intentional. The historical V3 packet proves that a real execution can now be reconstructed end-to-end through the new persistence layer, but it is not promoted to a current PASS because:

1. it is historical rather than a same-HEAD current rerun;
2. current atomicity controls evolved after that packet;
3. the real-screen corpus gate remains below threshold;
4. human adjudication remains `NOT_PERFORMED`;
5. P0-5 and production remain unauthorized.

No historical machine PASS was converted into a current PASS.
