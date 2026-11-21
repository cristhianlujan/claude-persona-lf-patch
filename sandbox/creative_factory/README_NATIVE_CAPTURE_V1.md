# Creative Factory — Native transport capture V1

## Objective and boundary

Capture exactly the **already-sealed** `SALY_NATIVE_TRANSPORT_V2.payload`,
verify the bytes seen by an offline sink and register only
`LOCAL_READBACK_MATCH_REVIEW_ONLY`. A local echo is **not** a GPT Native
acceptance, provider callback, image result, or an independent QA decision.

## Data authorities

1. Get the current item L2C work packet **through its authorized service-role
   route**. The read-only role cannot execute the private L2C function.
2. Call the deployed, service-role-only
   `saly.creative_assert_native_transport_v2(envelope)` immediately before
   local capture. A test double can exercise local behavior but **cannot**
   constitute evidence of this SQL check.
3. Compare exact prompt UTF-8 bytes, prompt SHA-256, contract SHA-256,
   attachments and item identity. Reject unsolicited text or composition
   assets in the Native payload; these belong to the compositor.
4. Serialize only the payload (prompt and attachments) with canonical UTF-8
   JSON. The sink must return the **actual bytes** it read. Missing readback,
   altered wire, malformed JSON and duplicate JSON keys are blocking failures.
5. Optional persistence: the governed
   `saly.creative_capture_append_v1(item_id,request_id,wire_base64,readback_base64)`
   recomputes the hashes from both captured streams on Supabase, rechecks the
   current packet against the existing SQL V2 validator, and appends an
   immutable local-only record. Duplicate IDs reject; the table cannot be
   updated, used as a provider receipt or written directly by service_role.

## Terminal statuses (never conflated)

| Boundary | State | Evidence |
|---|---|---|
| Verified payload / local sink | LOCAL_READBACK_MATCH_REVIEW_ONLY | Two byte streams and hashes |
| Actual GPT Native receiver | NOT_VERIFIED | No eligible SDK/host request receipt here |
| Generated body artifact | NOT_EXECUTED | No provider image bytes or job ID |
| Independent QA | NOT_EVALUATED | No visual/semantic QA evaluation |
| Production render | NOT_AUTHORIZED | Order, RUN and policy still block |

The function `validate_provider_ack` always rejects with
`NATIVE_PROVIDER_ATTESTATION_UNAVAILABLE`. Only a separately approved,
provider-specific adapter with trusted response provenance, recorded request
identifier, image bytes and independent QA can change this boundary. **Do
not** use user-supplied JSON, a mock sink or a captured PNG as proof of Native
receipt. Do not alter an order's render authority in this macrolote.

## Evidence and tests

```sh
cd sandbox/creative_factory
python -m unittest -v test_native_transport_capture_v1.py
```

Synthetic test matrix: positive Unicode and exact-byte capture, replay,
wrong schema/hash/item, prompt mutation, extra attachments, forged preflight,
missing/modified receiver echo, duplicate JSON keys, malformed UTF-8 and
unverified provider ACK. Test fixtures do not send external requests.

Database migration self-test runs on real sealed Home B item 9, writes
synthetic local-capture evidence only in a subtransaction, proves three
specific rejections and rolls back the evidence before commit. Any DB change
must be deployed via the governed one-at-a-time Merge Train. There is no ZIP,
font binary or copied logo in this PR.
