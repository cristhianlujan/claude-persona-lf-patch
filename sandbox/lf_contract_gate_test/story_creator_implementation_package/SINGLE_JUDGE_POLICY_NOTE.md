# Story Creator single-judge closure policy

Applies to `STORY_CREATOR_IMPLEMENTATION_SPEC_REFACTOR_V1`.

- Owner scope: `SUPER_ADMIN`.
- A governed judge verdict is the semantic quality gate.
- After that judge verdict exists for the same candidate, a second semantic judge/reviewer/independent-review receipt is not required.
- Structural, currentness, authority and exact-head checks remain evidence checks; they do not introduce another semantic judge.
- `REVISION_INDEPENDIENTE_ESTRATEGIA_LF` is Strategy-specific and must not be used for Story artifacts.
- Do not create a parallel review engine.
- Any future Story unit that attempts to add a second semantic review after an already-satisfied judge gate must fail its plan validation unless `SUPER_ADMIN` explicitly authorizes a true two-judge design for a distinct requirement.
