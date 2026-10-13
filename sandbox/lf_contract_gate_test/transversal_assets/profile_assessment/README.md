# PROFILE_ASSESSMENT v1

Transversal read-only capability for measuring profile capability maturity separately from S26 structural compatibility.

## Boundary

Input claims must be expressed as evidence records with status `PASS | FAIL | UNKNOWN` and evidence refs. A `PASS` without refs is normalized to `UNKNOWN`.

Outputs:

- maturity: `GENERIC | SPECIALIZED | ADAPTIVE | EXPERT | EVIDENCE_OPTIMIZED`;
- structural compatibility as a separate field;
- evidence-bound gaps;
- evolution mode: `NO_CHANGE | PATCH | SPECIALIZE | ADAPT | REARCHITECT | OPTIMIZE`;
- typed signals for downstream selection.

This capability never authorizes a write, runtime activation, promotion, or admission.
