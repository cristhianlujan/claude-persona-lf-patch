# PIP-1 Carril D — D-07, 2026-10-28

Scope: pure isolated Python core; no operations, no changes to PG-00.

| Checkpoint | Status | Actual evidence | Blocking |
|---|---|---|---|
| D-07.1 authentic source execution | BLOCKED | #3220 HEAD eb0e4f3... checked; raw.githubusercontent.com DNS resolution failed | Original 44,704 bytes not present locally |
| D-07.2 authentic-source mutations | BLOCKED | Synthetic regression tests PASS; no mutations falsely described as authentic | Source unavailable |
| D-07.3 excluded_proposals issue | PASS local | New exact full-file SHA-256 input guard; four tests | Authority decision on external envelope fields remains separate |
| D-07.4 regression | PASS local | 57 PASS, 0 FAIL, 0 ERROR, 0 SKIP, compileall and git diff --cached --check PASS | PASE NOT_RUN |
| D-07.5 independent review package | PREPARED | Source, diff, logs, hashes, handoff | Claude review has NOT occurred |
| D-07.6 draft PR | PREPARED, NOT PUBLISHED | Body template and main base | Owner GO, exact-source validation, PASE |

## Authentic inventory
PR #3220 HEAD eb0e4f3f912538b1cd2f2c9635854cbf86aeb783; blob SHA-1 47dd1f611ac36325b57d5129a87dc57919de330f; expected raw SHA-256 fc4cd3a387858d3091bee99cbec85721744792db7fed5ffdc1cc348b1a2719c9; expected inventory_core SHA-256 cd2f7a964b9901d9e58b8d5f4271532f480966424d37fd2d9a40332a7b440ffb. These are REFERENCE values supplied by owner and previous checks, NOT locally calculated source hashes in D-07.

#3275 merged on main at a49bf2a59bb54869e829e49fc8d59e0bac813f9c (GitHub readback). This does not certify PG-00.

## Excluded proposals
Six proposal entries refer to existing REQUIRED checkpoint IDs. They are edits to checkpoint text, not excluded checkpoints. Only PG-07.C7 is an excluded non-baseline checkpoint. Because excluded_proposals lies outside inventory_core, the inner digest cannot protect its content. The new optional expected_file_sha256 on load_inventory permits fail-closed byte-exact verification of the WHOLE file. For a trusted candidate, callers MUST pass the expected full-file digest, ideally using verify_exact_inventory.py. Test demonstrates mutation outside core passes when no outer hash is provided; this is documented and must NOT be represented as an accredited validation.

## Runtime / governance
No Supabase write, no Router/Train modification, no push, no PR, no workflow or live external validator. PASE NOT_RUN: there is no full LF checkout nor candidate exact commit and corresponding base available locally. Synthetic receipts NEVER authorize production closure; all operational=True paths fail closed.

## Reproduction
Place byte-exact original at inventory_eb0e4f3.json. Run `python verify_exact_inventory.py --file inventory_eb0e4f3.json --out inventory_verified.json`, `python -m unittest discover -s tests -v`, `python -m compileall -q pip1_core tests verify_exact_inventory.py`. Obtain full LF checkout and run PASE emitter against committed exact head and current origin/main; do not reuse other SHA's result.
