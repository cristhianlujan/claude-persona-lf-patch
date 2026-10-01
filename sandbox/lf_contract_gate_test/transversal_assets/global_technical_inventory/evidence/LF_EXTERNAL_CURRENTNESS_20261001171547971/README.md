# External currentness evidence — snapshot #11

This directory preserves the exact detector inputs used for inventory snapshot `LF_EXTERNAL_CURRENTNESS_20261001171547971`.

Observed repository main: `1f18636503cdaeda79a8df6cced0d0f2e5353c14`.

The files under `inputs/` parse to the exact structures whose canonical JSON SHA-256 values are:

- git_tree: `cb45f89d93595361f430ebfa2b68799ac5c27d53e6a23e0bec79603b7c7a68a6`
- repo_inventory: `f201d1223a517924348a8117d746a9724c6b3d28139451905fbfcead0a625da0`
- edge_runtime: `44f60d90786ea1106da244297d569ac4d851d7d80593937f35e8ef75c30ede60`
- edge_inventory: `b00ba0b3b127e09bb5789e8b62fc1299e28d708eeae2496450f22db4ac7ca404`
- scope_policy: `56b9368e260355109c966cd1673cca861f95381ab23283b361b8ca3a12b587f0`

Digest contract: `SHA256_CANONICAL_JSON_V1` = JSON object keys sorted recursively, UTF-8, separators `,` and `:`, no formatting whitespace.

`repo_inventory.json` records the detector input before the Block 3 write. Its 13 subsequently-MISSING rows therefore have `active=true`, exactly as they did at detection time.

`apply_external_currentness_observation.sql` records the operational SQL used for the classifications. It is evidence, not a migration.

`deactivate_missing_dependencies.sql` records the Block 3 closeout that deactivates historical graph edges touching the 13 MISSING repo objects without deleting them.

NEW repository paths remain report-only and are intentionally absent from `inventory.objects`.
