# P0 Dual OCR Adversarial Suite — 2026-08-14

## Status

**REGRESSION_CONTRACT_EXPANDED — NOT RUNTIME-PROMOTED**

This evidence note expands the governed dual-OCR reconciliation contract from the original 12 core invariants to an additional adversarial battery of 35 routing cases. It does not load PaddleOCR in runtime, does not authorize production, and grants zero P0-5 or real-corpus credit.

## Source separation

The 35 adversarial cases are deliberately split:

- **8 SOURCE_BOUND_TECHNICAL_SLICE cases**: only the eight durable target slices already recorded in `OCR_DUAL_ENGINE_MICROBENCHMARK_20260814.md` for source SHA-256 `e308b66778d1108241e2832997f6628f47841d7da1fc53820007834fdbb720d7`.
- **27 SYNTHETIC_ADVERSARIAL cases**: designed regression fixtures for failure families that must be handled before any future runtime promotion. They are not observations from additional real screens.

No synthetic fixture is relabeled as real evidence.

## Durable source-bound cases

1. accented name — exact agreement;
2. document number — exact agreement;
3. `+51` phone prefix — exact agreement;
4. phone placeholder — exact agreement;
5. email label — exact agreement;
6. email placeholder `Ej. miguelxcorreo.com` vs `Ej. miguel@correo.com` — challenger structural correction because the baseline violates the email invariant;
7. privacy sentence punctuation disagreement — preserve valid baseline;
8. small footer — exact agreement.

## Synthetic adversarial families

The additional fixtures cover:

- `0/O` in money;
- `1/l` in identifiers;
- decimal/thousands separator corruption;
- tildes and `ñ` disagreements;
- small-gray-text omission;
- visible truncation without forbidden completion;
- disabled-control omission;
- empty and checked checkbox false OCR;
- notification badge separation;
- lock icon false OCR;
- two-column ordering;
- repeated-label ownership;
- strikethrough amount corruption;
- tooltip/layer ordering;
- viewport/scroll visibility;
- decorative illustration false text;
- responsive order reconstruction;
- QR/barcode false OCR;
- `O/0` in years;
- `O/0` in percentages;
- structurally valid money disagreement;
- structurally valid identifier disagreement;
- missing invalid email -> review;
- missing baseline + structurally valid email challenger;
- generic valid disagreement with baseline preservation.

## Mandatory safety invariants retained

The original 12 reconciliation invariants remain in the same mandatory contract and still execute before the 35-case battery. In particular:

- cross-engine confidence values never choose a winner;
- exact agreement accepts baseline;
- structural correction is allowed only when the challenger repairs a machine-checkable invalid baseline;
- valid baseline + invalid challenger preserves baseline;
- both valid but different preserves baseline and records disagreement;
- ambiguous missing evidence abstains / requires review;
- detector-classified icon/decorative/QR evidence is not converted into text;
- truncation remains visible-only and cannot be silently completed;
- layout and omission families route to reconstruction or targeted reread instead of unrestricted challenger voting.

## Expected contract output

```text
PASS_P0_DUAL_OCR_RECONCILIATION_CONTRACT=12/12
PASS_P0_DUAL_OCR_ADVERSARIAL_CONTRACT=35/35
SOURCE_BOUND_TECHNICAL_SLICES=8
SYNTHETIC_ADVERSARIAL_FIXTURES=27
REAL_CORPUS_CREDIT=0
P0_5_CREDIT=0
RUNTIME_PROMOTED=false
PRODUCTION_AUTHORIZED=false
HOLDOUT_ACCESSED=false
```

## Interpretation

This closes a regression-design gap, not the runtime-promotion gate. The topology remains:

`Tesseract primary -> structural/layout/materiality checks -> selective targeted crop -> PaddleOCR challenger only when objectively triggered -> preserve baseline or abstain when disagreement is not safely resolvable.`

The next adoption evidence still requires broader authorized real-screen benchmarking and end-to-end immutable model-source pinning. Authentic P0-4/P0-5 human evidence remains separate.
