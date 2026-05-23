# Missing Input Policy — LF Profile Creator

When required inputs are missing, do not invent governance facts or create a final profile.

## Missing input handling

Return `RETURN_TO_ORCHESTRATOR` when any of the following is unavailable:

- Profile purpose.
- Target scope.
- Source authority.
- Governing asset.
- Allowed impact level.
- Existing asset check.

## Allowed assumptions

Only low-risk formatting assumptions are allowed, such as file naming convention or candidate folder structure.

## Forbidden assumptions

- Assuming ACT-0045 changed state.
- Assuming Supabase writes are allowed.
- Assuming runtime can be enabled.
- Assuming a final profile can be created without review gates.
