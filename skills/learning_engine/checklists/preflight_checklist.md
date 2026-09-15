# Preflight Checklist — LF Learning Engine

- [ ] Router route applied.
- [ ] Supabase source verification performed or limitation declared.
- [ ] ACT-0046 identified and respected as candidate/read-only.
- [ ] ACT-0045 checked when profile/card handoff is involved.
- [ ] Learning signal is clear.
- [ ] Evidence is sufficient.
- [ ] Existing assets checked to avoid duplicates.
- [ ] For materializing work, `causal_lane_key = EKB_code + target_asset + primary_gate` is computed canonically.
- [ ] Exactly one lane, one owner and one primary gate are declared for the PR/materializing unit.
- [ ] Fresh `main` currentness is bound from `GITHUB_PUBLIC_API_EXACT_REF_V1` before a writer claim.
- [ ] Active writer state for the exact `causal_lane_key` is read from Supabase.
- [ ] Writer has an exact Supabase ownership claim, or the current role is explicitly `REVIEWER_READ_ONLY` with no write intent.
- [ ] A second writer on the same causal key is routed to `WAITING_UPSTREAM`, not allowed to copy or advance the owner lane.
- [ ] A successor invalidates stale/currentness receipts and reacquires ownership after the prior owner closes.
- [ ] Runtime remains disabled.
- [ ] Automatic impact remains blocked.
- [ ] Output target is candidate, not final operational impact.
