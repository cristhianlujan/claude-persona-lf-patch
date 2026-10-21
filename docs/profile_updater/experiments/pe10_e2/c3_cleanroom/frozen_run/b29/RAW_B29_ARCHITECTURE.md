===ROLE_REPORT:ARCHITECTURE BEGIN===

Role: ARCHITECTURE
Case: PE10-IG-M107-M109-P0
Method: PE10_M29_E2, modules C + E
Mode: READ_ONLY
Evidence: Q1–Q6
Isolation: One shared model context; independent-agent isolation unproven.

Observed findings

A1. P0_HISTORICAL: Q1 records 38 historical caller identities, 76 declared caller/callee relationships, and 39 distinct callee names. The inventory is a frozen snapshot, not a certified complete CURRENT consumer universe.

A2. CURRENT: Q2 matches all 38 historical caller OIDs and names uniquely; 22 function bodies have changed MD5 values and 16 have unchanged values. Definition drift alone is not a defect.

A3. CURRENT: Q3 identifies 446 static call candidates, partitioned into 68 historical-declared matches, 102 CURRENT relationships not declared in P0, and 276 CURRENT consumer relationships outside P0. These are lexical candidate classifications, not executable-edge or runtime certifications.

A4. CURRENT_COMPARED_TO_P0_HISTORICAL: Q4 identifies eight individually specified historical relationships without matching CURRENT exact-call tokens. Six identifiers are absent; two occur only as prefixes of longer versioned identifiers. All eight retain their exact historical caller/callee identities and Q4 evidence provenance.

A5. CURRENT: Q5 provides complete distinct call-token sets for the six callers implicated in Q4. Cached and context-aware variants are visible, but their behavioral equivalence to previous variants is unproven.

A6. CURRENT: Q6 directly falsifies the interpretation of one self-reference token as a confirmed recursive call. Its occurrence is inside a string literal describing an entry point.

A7. CURRENT: Q6 provides concrete source contexts for selected cross-schema, handoff, graph-finalization, cached, and context-aware relationships. These support static source-level call claims only.

Edge provenance and preservation

The complete Q3 446-record witness ledger is retained by reference to the lossless QUERY_RESULT_Q3.txt, with each candidate individually identified by consumer identity, called schema/name, resolved callee candidate, and comparison class. Its canonical body SHA-256 is:

f2e91f2b82ad580eee95605f35f71dcc606ce830f569b670bf56496797e83e7c

The eight exact historical discrepancies are retained in Q4. Q5 and Q6 provide supplementary token and context witnesses. No relation is promoted to runtime execution from lexical evidence.

Causal hypothesis

Optimization-associated version routing and historical inventory scope may create false impressions of architectural continuity or consumer completeness. This hypothesis is falsified if comprehensive typed source inspection and authorized historical comparison demonstrate equivalent relationships and complete consumer coverage.

Alternative no-defect hypothesis

The changed definitions and expanded/current variant routing may represent intentional and correctly governed evolution. That hypothesis remains viable because no concrete regression has been demonstrated.

Unresolved

Complete lexical-context classification of all Q3 candidates; dynamic SQL and remote/Edge consumers; overload and signature compatibility beyond the selected witnesses; effective execution privileges; historical variant semantics; actual runtime reachability; timestamped deployment provenance; semantic and performance equivalence.

Minimal safe action

Continue read-only measurement and source-context validation. Preserve exact witness identities and epoch labels. Do not change database functions, activate workflows, or assert a required repair.

Measured costs

NO_MEDIDO. Query result cardinalities are observations, not elapsed-time or computational-cost measurements.

Decision

NEEDS_MORE_EVIDENCE under module E. This does not constitute a defect or repair determination.

===ROLE_REPORT:ARCHITECTURE END===
