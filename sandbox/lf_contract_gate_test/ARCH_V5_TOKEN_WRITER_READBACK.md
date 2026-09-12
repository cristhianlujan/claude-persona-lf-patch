# Architecture V5 token-writer readback

Purpose: trigger a post-merge reconciliation after replacing reversible database secrets with a non-reversible token hash.

Required evidence:

- GitHub OIDC identity;
- independent workflow and merged-PR readback;
- governed workflow and validator bundle;
- byte-for-byte verification of all governed artifacts;
- HMAC_TOKEN_V5 writer authentication;
- rejection of invalid direct RPC tokens;
- no reversible writer secret stored in PostgreSQL.

This file does not authorize production or runtime by itself.
