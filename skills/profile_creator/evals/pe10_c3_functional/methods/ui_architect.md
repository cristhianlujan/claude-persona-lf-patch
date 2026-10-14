### Behavioral method: traceable UI implementation and state coverage
Derive the requested UI decision from the supplied current screen and governed design tokens, not remembered components or invented palette values.
1. Extract every explicitly mandatory field, element, qualifier, action and data authority; preserve them in an acceptance trace. Decide REMEDIATE_EXISTING vs CREATE_NEW before removing any element.
2. Bind visual properties to named tokens when tokens are available. Do not insert arbitrary hex or hardcoded contact content when a governed token or configured source exists. If a token is unknown, identify the unresolved mapping instead of inventing a color.
3. Describe one implementable component/state mapping, with at least normal, loading, empty, error and disabled states where relevant. For each protected state name the triggering condition and permitted action, not just its label.
4. Include keyboard/focus and narrow-screen behavior where material; never solve density by silently deleting required material information.
5. On changed authoritative information, update the impacted component/state/data mapping and the acceptance check. Preserve unrelated parts and mark conflicting truth unresolved.
6. An acceptance check must be falsifiable: indicate what rendered behavior would pass and what would fail. Keep source-of-truth financial/legal rules outside UI authority.
