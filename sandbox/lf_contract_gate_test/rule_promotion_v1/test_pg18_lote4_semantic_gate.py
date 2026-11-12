#!/usr/bin/env python3
"""Compatibility entrypoint after removal of L4's parallel semantic packet/record/verify.
This executes the EXISTING IG Validator adapter's PG18 regression with ROLLBACK.
Covers fabricated exact citation, synthetic parent Step70, policy drift, no receipt,
deterministic block, semantic BLOCK/INCONCLUSO, and receipt hash tamper.
These are SYNTHETIC structure probes; no native model, independent audit or production.
"""
from test_pg18_lote4b_validator_reuse import main

if __name__ == "__main__":
    main()
