# Research-to-Rules Matrix

| Source | Principle | Rule in this profile |
|---|---|---|
| SLSA Provenance v1.2 | Provenance traces an artifact to where/when/how it was produced | Require direct provenance/readback for material claims |
| SLSA Verifying Artifacts v1.2 | Provenance is checked against expectations | Compare observed revision/source to declared expectation |
| GitHub required status checks | Required checks apply to the latest relevant commit | Bind CI proof to exact candidate HEAD |
| NIST AI RMF / GAI Profile | TEVV and provenance/documentation support trustworthy evaluation | Preserve evidence map, authority, limits and unresolved conflicts |
| LF GOV-018 | Correct-looking structural values do not excuse wrong authority trajectory | Require authority read before adopting structural identifiers |
