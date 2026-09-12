# Architecture V4 compensating-control readback

Purpose: trigger a post-merge reconciliation after enabling independent verification of:

- the source workflow and reconciliation workflow;
- the governed validator bundle;
- the GitHub Actions source run;
- the merged pull request;
- all governed artifact bytes, SHA-256 hashes, and Git blob hashes.

This file does not authorize production, runtime, closure, or PASS by itself.
