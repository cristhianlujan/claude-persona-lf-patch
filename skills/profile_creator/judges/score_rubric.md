# Score Rubric — LF Profile Creator

## PASS

- Router-first route is explicit.
- Supabase source verification is required.
- Active governing asset is checked.
- Output is a complete profile pack candidate.
- If `PROFILE_PACK_CREATED` is claimed, the created artifact is directly resolvable and contains the components claimed by the producer.
- The declared receiver can consume that artifact without inventing missing structure, content or intent.
- Runtime and automatic impact remain blocked.
- Review gates are preserved.
- Rules are consolidated as reusable mother rules.

## PASS_WITH_RESTRICTIONS

- Pack is complete and consumable but still requires sandbox evidence before use.
- Minor wording or adapter details remain open.

## FAIL

- Output is prompt-only.
- `PROFILE_PACK_CREATED` is claimed but no resolvable candidate artifact is delivered.
- The next worker must reconstruct the supposedly created pack from filenames, prose or assumptions.
- Final profile is created directly.
- Runtime or production general is enabled.
- Supabase write or ACT-0045 modification is proposed without explicit approval.
- Narrow rules are multiplied instead of consolidated.
