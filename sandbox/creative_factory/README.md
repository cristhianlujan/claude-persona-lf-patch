# Creative compositor — reviewed runtime

This folder holds a **brand-neutral, offline** renderer. Brand tokens, official source
assets, images and approval decisions are **not** embedded in the engine or the repository.

## Input boundary

The owner supplies a frozen composition manifest from the governed work packet
(`creative_item_work_packet_l2c` or its equivalent for another business), the
corresponding registered SVG/PNG bytes and a transparent body image. Every
registered source byte (including installed font files) is checked against its
pinned SHA-256 **before** composition. The native body is permitted to draw only
the frozen `primary` and `details` slots. Header/logo, CTA, footer and frame
are rendered deterministically. Unpinned and extra assets are rejected.

The tool does **not** reconstruct prompts, invoke GPT Native, validate the
provider's receipt, approve QA, update Supabase or authorize production.
`COMPOSITION_REVIEW_V1` is strictly review-only.

## Example

```sh
python sandbox/creative_factory/compositor_core_v1.py \
  /secure/work_packet_composition_manifest.json \
  /secure/native_body_only.png \
  /tmp/composition_review.png \
  --receipt /tmp/composition_local_receipt.json
```

The receipt says `native_transmitted=false`, `qa_verdict=NOT_EVALUATED`
and `production_approved=false`. These fields cannot prove Native delivery.

## Tests

```sh
PYTHONPATH=sandbox/creative_factory python -m unittest -v \
  sandbox/creative_factory/test_compositor_core_v1.py
```

The stand-alone local/isolated test uses synthetic, in-memory files and installed DejaVu fonts. It must run before requesting governed merge; the repository intentionally retains only its existing ordinary PR workflow.
**No ZIP, font binary, SALY asset or brand logo is distributed in Git.**
A separate sandbox pilot tested the real SALY Home B pinned SVGs and approved
logo (6/6 source hashes) and a synthetic body; it is *not* a native render.
