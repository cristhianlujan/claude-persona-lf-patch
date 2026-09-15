# Exploratory Profile Quality Rubric v0.1

Score only after hard-block checks.

| Dimension | Weight |
|---|---:|
| Breadth | 15 |
| Causal diversity | 15 |
| Non-redundancy | 10 |
| Business/data leverage | 15 |
| Frontier distance | 20 |
| Experimentability | 15 |
| Scope guard | 10 |

Target: **>= 80/100** and no hard governance failure.

Hard blocks override score:
- silent scope mutation;
- missing authority;
- free-search or invented Card context when governed context is required;
- runtime/production/scheduler/Golden/canonical-write claim;
- schema/output contract violation.

Return for repair:
- shallow or commodity-only set;
- materially redundant ideas;
- unsupported opportunities;
- missing experiment/evidence.
