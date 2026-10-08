# PROFILE_CANDIDATE_MATERIALIZER V1

Deterministic transport for an already-authored Profile Evolution overlay.

It does **not** author, improve, rewrite, score, admit, merge, promote, or activate a profile. Semantic delta authoring remains owned by the existing Profile Creator worker. This component only verifies the exact baseline revision and per-file before hashes, confines paths to `profiles/<slug>/**`, materializes the overlay outside the authority repository, and emits a hash-bound receipt.

A PASS means only that the candidate overlay was materialized reversibly and the source profile remained byte-identical. It is not semantic approval and not write authority.
