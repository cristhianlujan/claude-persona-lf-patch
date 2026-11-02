# Chat-assisted programming smoke (Paulo)

**Purpose:** prove that a ChatGPT conversation can author code, commit it through connected GitHub, execute tests from the exact published HEAD, and open a reviewable draft PR.

**Scope:** isolated synthetic helper only, no functional LF code, no changes to Supabase. The test is *not* the PG pipeline or authorized execution from a real PG-01 package.

Flow: ChatGPT authors minimal change → GitHub branch/commits → remote checkout at exact SHA → tests → draft PR. The positive result is evidence for the chat-assisted *transport* and code review workflow, not for PG-03 strategy, PG-04 partitioning, Worker readiness, PG-07/08 formal closure or required validation bindings.

Run: `python3 -m unittest test_safe_task_scope.py -v`

**No Worker**, no inference API, no production authority, no protected main changes.
