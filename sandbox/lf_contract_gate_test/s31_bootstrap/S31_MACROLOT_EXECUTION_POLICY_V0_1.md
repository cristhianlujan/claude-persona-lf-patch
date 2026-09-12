# S31 Macrolot Execution Policy v0.1

Status: CANDIDATE / S31-LOCAL
Base main: `ee7aca94c672fcc555db90962f09fe439eedf4f0`

## Purpose

Prevent a single blocked causal gate from ending an otherwise safe S31 run.

## Core rule

`BLOCKED_CAUSAL != END_OF_RUN`.

A blocked lane stops only the affected causal chain. The orchestrator must recompute the frontier and continue any work explicitly classified as safe, independent, current, and inside ownership/write scope.

## Mandatory behavior

When a blocker appears:

1. Freeze the affected candidate and evidence boundary.
2. Record blocker code, affected scope, causal gate, owner and invalidation condition.
3. Recompute `safe_parallel_work` from the current Work Package/frontier.
4. Continue read-only or S31-owned material work that does not depend on the blocked result.
5. Do not weaken, bypass or self-certify the blocked gate.
6. Stop the full run only when no safe parallel work remains, currentness is invalid, ownership conflicts, or the remaining work requires new authority/scope.

## Positive example

S31-A waits for independent semantic review. S31-B Work Package evolution and S31-C Cards/Fallback vocabulary analysis may continue because they are explicitly safe parallel work and write only inside S31-owned paths.

## Negative example

S31-A waits for independent review, but S31 directly edits S26 runtime card resolver to unblock itself. This is forbidden cross-lane mutation and is not safe parallel work.

## Evidence rule

A continuation claim must name:
- blocked causal chain;
- blocker;
- independent work selected;
- dependency proof showing it does not consume the blocked result;
- current base/head;
- allowed write scope.

## Closure rule

Macrolot completion is based on exhausting safe work, not on the first blocker encountered.
