# Adapter V2 Validation Matrix

| Concern | Deterministic | Semantic | Runtime evidence |
|---|---|---|---|
| Required fields | yes | no | no |
| Adapter identity/version | yes | no | yes |
| Source/capsule hashes | yes | no | yes |
| Protected/writable overlap | yes | no | no |
| Authority meaning | partial | yes | yes |
| Unsupported invention | partial | yes | raw output |
| Exactly-once application | receipt check | no | yes |
| Zero cost when unbound | payload check | no | yes |
| Second model call absent | trace check | no | yes |
