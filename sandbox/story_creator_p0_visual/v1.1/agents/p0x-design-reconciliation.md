# P0X — auxiliary design reconciliation contract v1

P0X runs only after the blind consolidated v2 artifact is locked and hashed. Accepted auxiliary sources are source-versioned DOM snapshots, computed-style snapshots, stylesheets, Figma exports/nodes, design-token bundles and design-system specifications with source SHA, capture time, screen mapping, provenance, trust and authorization.

For every reconciliable property, preserve observed/estimated and declared values separately and emit `MATCH`, `APPROX_MATCH`, `MISMATCH`, `NOT_COMPARABLE`, `DECLARED_ONLY` or `OBSERVED_ONLY`. Never overwrite the blind value. A stale/mis-mapped auxiliary source, missing source SHA, hidden critical mismatch or blind SHA mutation is fail-closed.
