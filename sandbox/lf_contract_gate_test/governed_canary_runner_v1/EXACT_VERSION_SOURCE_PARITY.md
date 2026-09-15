# IG006/IG007 exact-version source parity

Candidate exact versions: `20260907193711` forward and `20260907193712` rollback.

Before any remote execution, both migration bodies must be byte-identical to the previously reviewed source bodies:

- forward source blob: `d806d88176e21bcee1de7545c65e776a6e051899`
- rollback source blob: `290ff2e1c50ca7d0bf2167a9f424380450de0c93`

The filenames provide fresh ledger identities only. Runtime behavior must not be re-authored for the transport proof.

Claim ceiling: source-parity control only; no execution, production, merge, or promotion authority.