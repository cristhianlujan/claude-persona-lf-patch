# LF Reusable Profile Policy Resolution V1

## Principle

Policies are reusable assets. Profiles do not own static policy lists.

For each profile execution:

1. Resolve the selected profile and its declared capabilities.
2. Run deterministic policy discovery using:
   - business
   - channel
   - profile capabilities
   - action family
   - asset type
3. Produce a bounded shortlist.
4. Run semantic selection only over that shortlist.
5. The semantic stage may select zero or more candidates, but it may never add a policy outside the deterministic shortlist.
6. Deliver only the selected policy set to profile execution.

## Performance rule

The semantic model MUST NOT receive the complete policy registry. It receives only the deterministic shortlist.

## Reuse rule

A policy is registered once with reusable applicability metadata. Any current or future profile whose capabilities and execution context match can consume it without editing that profile.

## No-policy rule

If deterministic discovery yields zero candidates, the profile executes under its normal contract without an additional policy set.

## Authority boundaries

- Router chooses the profile.
- Profile capabilities are canonical registry data.
- Deterministic discovery identifies eligible policies.
- Semantic selection decides material applicability within that shortlist.
- Semantic selection has no authority to expand the shortlist.
- Policies constrain profile execution; they do not select or invoke profiles.
