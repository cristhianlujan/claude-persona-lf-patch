# LF Design Token Reference Policy V1

**Policy code:** `LF-DESIGN-TOKEN-REFERENCE-POLICY-V1`  
**Status:** VIGENTE  
**Scope:** LF Design System, UI definitions, component tokens, stories, profiles, skills, migrations, generators and implementation packages that reference visual design values.

## 1. Purpose

Preserve the LF Design System as the single source of truth for visual values and prevent hardcoded or duplicated design values from leaking into component definitions, generated UI, migrations or implementation artifacts.

## 2. Normative rule

Every governed visual value MUST be consumed by canonical token reference, never by copying its resolved literal value.

Examples:

- Correct: `background = "error_bg"`
- Correct: `border = "error_text"`
- Correct: `radius = "radius_12"`
- Incorrect: `background = "#FEE2E2"`
- Incorrect: `border = "#991B1B"`
- Incorrect: creating a second color token only to duplicate an existing HEX when no distinct semantic authority is required.

The literal value belongs only to its canonical token table. Consumers store the token name/code.

## 3. Required behavior

1. Components MUST reference canonical tokens by name/code in `token_bindings`.
2. HEX, RGB, RGBA, HSL, HSLA and equivalent literal visual values are forbidden in component bindings and downstream governed artifacts.
3. A new semantic token MAY be created only when a genuinely distinct semantic role exists. It MUST NOT be created merely to alias/copy a literal value already governed elsewhere.
4. A `VIGENTE` component may reference only `VIGENTE` canonical tokens for governed bindings.
5. A deprecated token MUST NOT be introduced into a new or modified governed component.
6. Product/UI/Profile/Skill outputs MUST preserve token references when handing work downstream; they MUST NOT resolve them to literals.
7. Generators/renderers may resolve a canonical token to a literal at render time, but that resolved value is derived output and MUST NOT become the stored authority.
8. If a token value changes centrally, all consumers using the token reference inherit that change without rewriting their definitions.
9. Any exception requires an explicit governed decision naming the exception, scope, reason, owner and expiry/review condition. Silent exceptions are forbidden.

## 4. Status propagation

- `VIGENTE component` → referenced governed tokens MUST be `VIGENTE`.
- `CANDIDATO component` → may reference `VIGENTE` or explicitly governed candidate tokens, but may not promote itself.
- `DEPRECADO token` → cannot be newly introduced into any modified component.
- Historical drift is not silently grandfathered: when a historical component is modified, it must comply with the current policy before the write is accepted.

## 5. Enforcement

This policy is enforced at multiple layers:

- **Database:** `lf_design.guard_component_token_bindings_v1()` / `trg_guard_component_token_bindings_v1`.
- **Story/implementation validation:** token validators must report hardcoded visual values and unregistered token references.
- **Profiles/skills:** UI/Product/implementation profiles must preserve canonical token references rather than literalize values.
- **CI/migrations:** governed changes must fail if they introduce literal colors or invalid/deprecated token references.
- **Repository governance:** this policy is pinned as a governed source and cannot be silently replaced.

## 6. Evidence and currentness

A compliant artifact must be able to show:

- the consumer;
- the token reference used;
- the canonical token source;
- the token status;
- the governing decision when applicable;
- no duplicated literal value in the consumer definition.

## 7. Anti-patterns

The following are policy violations:

- copying `#991B1B` from `error_text` into a component;
- creating `critical_action=#991B1B` only to avoid referencing `error_text`;
- storing `rgb(...)` or `#...` in `component_tokens.token_bindings`;
- making a component `VIGENTE` while it points to a candidate/deprecated color token;
- resolving token values in Product/UI output and persisting the literal instead of the token identity.

## 8. Canonical interpretation

The canonical identity is the token name/code. The literal value is an implementation-time resolution of that identity, not the authority itself.
