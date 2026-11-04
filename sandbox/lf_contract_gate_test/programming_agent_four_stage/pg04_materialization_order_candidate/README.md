# LF Fase 2 — PG-04 materialization order (Paulo)

**Status:** SOURCE_ONLY_CANDIDATE, no operational authority. This isolated proposal contains only the order-check of the materialization circuit and its six tests, not the full 59-test local package.

The state machine models PG-01 admission, task DRAFT/SEALED, blind independent test contract DRAFT/SEALED, delivery contract DRAFT/SEALED and DB readiness. It *does not* authenticate the supplied `authenticated` boolean, query Supabase, grant any permission, insert rows, or dispatch a Worker.

Run from this directory:
```bash
python3 -m unittest test_materialization_circuit.py -v
```

It must not become a required checkpoint validator or be treated as proof of PG-01/J02 admission. The actual pending integrations are independently authenticated receipts, guarded database writes, calibrated sizing, independent test generation, the delivery contract and Worker readiness.

**Author:** Paulo. **PR intent:** draft only; no merge, runtime activation or database writes.
