# Architecture V4 signed-writer readback

Purpose: trigger a post-merge reconciliation after enabling HMAC-authenticated evidence writers.

The cycle must verify:

- GitHub OIDC identity;
- source workflow and merged pull request;
- governed workflow and validator bundle;
- all governed artifact bytes, SHA-256 hashes, and Git blob hashes;
- HMAC authentication for reconciliation and gate-test persistence;
- rejection of unsigned direct RPC calls.

This file does not authorize production or runtime by itself.
