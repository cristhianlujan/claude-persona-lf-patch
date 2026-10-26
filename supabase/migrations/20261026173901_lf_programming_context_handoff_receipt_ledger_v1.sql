/*
 * D7 option A — PG-01 programming context handoff receipt ledger.
 *
 * Phase 1:
 *   - append-only receipt storage;
 *   - governed writer;
 *   - exact-binding resolver;
 *   - admission gate remains CLOSED.
 *
 * No row created by this migration is admissible for programming.
 */

DO $$
BEGIN
    IF to_regnamespace('private') IS NULL THEN
        RAISE EXCEPTION
            'PG01_RECEIPT_LEDGER_PREREQUISITE_MISSING:private_schema';
    END IF;

    IF to_regclass('private.lf_decision_context_asof_v1') IS NULL THEN
        RAISE EXCEPTION
            'PG01_RECEIPT_LEDGER_PREREQUISITE_MISSING:lf_decision_context_asof_v1';
    END IF;

    IF to_regclass('public.lf_operation_execution') IS NULL THEN
        RAISE EXCEPTION
            'PG01_RECEIPT_LEDGER_PREREQUISITE_MISSING:lf_operation_execution';
    END IF;

    IF to_regprocedure('extensions.digest(bytea,text)') IS NULL THEN
        RAISE EXCEPTION
            'PG01_RECEIPT_LEDGER_PREREQUISITE_MISSING:extensions.digest';
    END IF;
END
$$;


CREATE TABLE IF NOT EXISTS private.lf_programming_context_handoff_receipts_v1
(
    receipt_record_id uuid
        NOT NULL
        DEFAULT pg_catalog.gen_random_uuid(),

    binding_key_sha256 text
        NOT NULL,

    context_id uuid
        NOT NULL,

    context_sha256 text
        NOT NULL,

    receipt jsonb
        NOT NULL,

    receipt_sha256 text
        NOT NULL,

    envelope jsonb
        NOT NULL,

    envelope_sha256 text
        NOT NULL,

    verdict text
        NOT NULL,

    created_by_execution_id text
        NOT NULL,

    created_at timestamptz
        NOT NULL
        DEFAULT pg_catalog.now(),

    CONSTRAINT pk_lf_programming_context_handoff_receipts_v1
        PRIMARY KEY (receipt_record_id),

    CONSTRAINT uq_lf_programming_context_handoff_receipts_v1_binding
        UNIQUE (binding_key_sha256),

    CONSTRAINT fk_lf_programming_context_handoff_receipts_v1_context
        FOREIGN KEY (context_id)
        REFERENCES private.lf_decision_context_asof_v1 (context_id),

    CONSTRAINT ck_lf_programming_context_handoff_receipts_v1_binding_sha
        CHECK (binding_key_sha256 ~ '^[0-9a-f]{64}$'),

    CONSTRAINT ck_lf_programming_context_handoff_receipts_v1_context_sha
        CHECK (context_sha256 ~ '^[0-9a-f]{64}$'),

    CONSTRAINT ck_lf_programming_context_handoff_receipts_v1_receipt_sha
        CHECK (receipt_sha256 ~ '^[0-9a-f]{64}$'),

    CONSTRAINT ck_lf_programming_context_handoff_receipts_v1_envelope_sha
        CHECK (envelope_sha256 ~ '^[0-9a-f]{64}$'),

    CONSTRAINT ck_lf_programming_context_handoff_receipts_v1_verdict
        CHECK (verdict IN ('ACCEPT', 'BLOCK')),

    CONSTRAINT ck_lf_programming_context_handoff_receipts_v1_verdict_copy
        CHECK (receipt->>'verdict' = verdict)
);


DO $$
DECLARE
    v_columns text[];
BEGIN
    SELECT array_agg(a.attname ORDER BY a.attname)
      INTO v_columns
      FROM pg_catalog.pg_attribute a
     WHERE a.attrelid =
               'private.lf_programming_context_handoff_receipts_v1'::regclass
       AND a.attnum > 0
       AND NOT a.attisdropped;

    IF v_columns IS DISTINCT FROM ARRAY[
        'binding_key_sha256',
        'context_id',
        'context_sha256',
        'created_at',
        'created_by_execution_id',
        'envelope',
        'envelope_sha256',
        'receipt',
        'receipt_record_id',
        'receipt_sha256',
        'verdict'
    ]::text[] THEN
        RAISE EXCEPTION
            'PG01_RECEIPT_LEDGER_SCHEMA_MISMATCH:COLUMNS';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM (
              VALUES
                  ('receipt_record_id', 'uuid'),
                  ('binding_key_sha256', 'text'),
                  ('context_id', 'uuid'),
                  ('context_sha256', 'text'),
                  ('receipt', 'jsonb'),
                  ('receipt_sha256', 'text'),
                  ('envelope', 'jsonb'),
                  ('envelope_sha256', 'text'),
                  ('verdict', 'text'),
                  ('created_by_execution_id', 'text'),
                  ('created_at', 'timestamp with time zone')
          ) AS expected(column_name, data_type)
          LEFT JOIN pg_catalog.pg_attribute a
            ON a.attrelid =
               'private.lf_programming_context_handoff_receipts_v1'::regclass
           AND a.attname = expected.column_name
           AND a.attnum > 0
           AND NOT a.attisdropped
         WHERE a.attname IS NULL
            OR pg_catalog.format_type(a.atttypid, a.atttypmod)
               <> expected.data_type
    ) THEN
        RAISE EXCEPTION
            'PG01_RECEIPT_LEDGER_SCHEMA_MISMATCH:TYPES';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_constraint c
         WHERE c.conrelid =
               'private.lf_programming_context_handoff_receipts_v1'::regclass
           AND c.conname =
               'uq_lf_programming_context_handoff_receipts_v1_binding'
           AND c.contype = 'u'
    ) THEN
        RAISE EXCEPTION
            'PG01_RECEIPT_LEDGER_SCHEMA_MISMATCH:BINDING_UNIQUE';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_constraint c
         WHERE c.conrelid =
               'private.lf_programming_context_handoff_receipts_v1'::regclass
           AND c.conname =
               'fk_lf_programming_context_handoff_receipts_v1_context'
           AND c.contype = 'f'
    ) THEN
        RAISE EXCEPTION
            'PG01_RECEIPT_LEDGER_SCHEMA_MISMATCH:CONTEXT_FK';
    END IF;
END
$$;


CREATE INDEX IF NOT EXISTS
    idx_lf_programming_context_handoff_receipts_v1_context
ON private.lf_programming_context_handoff_receipts_v1
    (context_id, context_sha256);


CREATE OR REPLACE FUNCTION
private.fn_lf_programming_context_handoff_receipt_immutable_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'private'
AS $function$
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        RAISE EXCEPTION
            'BLOCK_PG01_RECEIPT_LEDGER_APPEND_ONLY:%',
            TG_OP;
    END IF;

    RETURN NEW;
END
$function$;


DROP TRIGGER IF EXISTS
    trg_00_guard_lf_programming_context_handoff_receipts_v1
ON private.lf_programming_context_handoff_receipts_v1;

CREATE TRIGGER
    trg_00_guard_lf_programming_context_handoff_receipts_v1
BEFORE UPDATE OR DELETE
ON private.lf_programming_context_handoff_receipts_v1
FOR EACH ROW
EXECUTE FUNCTION
    private.fn_lf_programming_context_handoff_receipt_immutable_v1();


CREATE OR REPLACE FUNCTION
private.fn_lf_programming_context_handoff_receipt_record_v1(
    p_receipt jsonb,
    p_envelope jsonb,
    p_binding jsonb,
    p_execution_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'private', 'public', 'extensions'
AS $function$
DECLARE
    /*
     * Phase-1 allow-list.
     *
     * Add future governed runtime writer operation codes here only after
     * their authority contract is released.
     */
    v_allowed_operation_codes CONSTANT text[] :=
        ARRAY['ACTUALIZACION_DB_LF']::text[];

    v_receiver_digest CONSTANT text :=
        'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8';

    v_execution_count bigint;

    v_receipt_key_count integer;
    v_context_id uuid;

    v_requested_scope_ids jsonb;
    v_binding_canonical jsonb;

    v_binding_key_sha256 text;
    v_receipt_sha256 text;
    v_envelope_sha256 text;

    v_inserted_record_id uuid;
    v_inserted_created_at timestamptz;

    v_existing private.lf_programming_context_handoff_receipts_v1%ROWTYPE;
BEGIN
    /*
     * 1. Governed execution.
     */
    SELECT count(*)
      INTO v_execution_count
      FROM public.lf_operation_execution e
     WHERE e.execution_id = p_execution_id
       AND e.operation_code = ANY (v_allowed_operation_codes)
       AND e.status = 'IN_PROGRESS'
       AND e.manifest->>'producer' = 'lf-migration-merge-train';

    IF v_execution_count <> 1 THEN
        RAISE EXCEPTION
            'PG01_RECEIPT_WRITER_EXECUTION_NOT_AUTHORIZED';
    END IF;


    /*
     * 2. Exact PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1 shape.
     */
    IF p_receipt IS NULL
       OR pg_catalog.jsonb_typeof(p_receipt) <> 'object'
    THEN
        RAISE EXCEPTION 'PG01_RECEIPT_SHAPE_INVALID';
    END IF;

    SELECT count(*)
      INTO v_receipt_key_count
      FROM pg_catalog.jsonb_object_keys(p_receipt);

    IF v_receipt_key_count <> 8
       OR NOT (
           p_receipt ?& ARRAY[
               'schema_version',
               'context_id',
               'context_sha256',
               'snapshot_schema_digest_sha256',
               'receiver_schema_digest_sha256',
               'material_projection_sha256',
               'validated_material_paths',
               'verdict'
           ]
       )
    THEN
        RAISE EXCEPTION 'PG01_RECEIPT_SHAPE_INVALID';
    END IF;

    IF pg_catalog.jsonb_typeof(p_receipt->'schema_version') <> 'string'
       OR p_receipt->>'schema_version'
          <> 'PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1'

       OR pg_catalog.jsonb_typeof(p_receipt->'context_id') <> 'string'
       OR NOT (
           p_receipt->>'context_id'
           ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       )

       OR pg_catalog.jsonb_typeof(p_receipt->'context_sha256') <> 'string'
       OR NOT (
           p_receipt->>'context_sha256' ~ '^[0-9a-f]{64}$'
       )

       OR pg_catalog.jsonb_typeof(
              p_receipt->'snapshot_schema_digest_sha256'
          ) <> 'string'
       OR NOT (
           p_receipt->>'snapshot_schema_digest_sha256'
           ~ '^[0-9a-f]{64}$'
       )

       OR pg_catalog.jsonb_typeof(
              p_receipt->'receiver_schema_digest_sha256'
          ) <> 'string'
       OR NOT (
           p_receipt->>'receiver_schema_digest_sha256'
           ~ '^[0-9a-f]{64}$'
       )

       OR pg_catalog.jsonb_typeof(
              p_receipt->'material_projection_sha256'
          ) <> 'string'
       OR NOT (
           p_receipt->>'material_projection_sha256'
           ~ '^[0-9a-f]{64}$'
       )

       OR pg_catalog.jsonb_typeof(
              p_receipt->'validated_material_paths'
          ) <> 'array'
       OR pg_catalog.jsonb_array_length(
              p_receipt->'validated_material_paths'
          ) = 0

       OR EXISTS (
           SELECT 1
             FROM pg_catalog.jsonb_array_elements(
                      p_receipt->'validated_material_paths'
                  ) AS item(value)
            WHERE pg_catalog.jsonb_typeof(item.value) <> 'string'
       )

       OR pg_catalog.jsonb_typeof(p_receipt->'verdict') <> 'string'
       OR p_receipt->>'verdict' NOT IN ('ACCEPT', 'BLOCK')
    THEN
        RAISE EXCEPTION 'PG01_RECEIPT_SHAPE_INVALID';
    END IF;


    /*
     * 3. Current receiver contract.
     */
    IF p_receipt->>'receiver_schema_digest_sha256'
       <> v_receiver_digest
    THEN
        RAISE EXCEPTION
            'PG01_RECEIPT_RECEIVER_DIGEST_MISMATCH';
    END IF;


    /*
     * 4. Context pair must exist exactly in the persisted as-of snapshot.
     */
    v_context_id := (p_receipt->>'context_id')::uuid;

    PERFORM 1
      FROM private.lf_decision_context_asof_v1 c
     WHERE c.context_id = v_context_id
       AND c.context_sha256 = p_receipt->>'context_sha256';

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'PG01_RECEIPT_CONTEXT_NOT_FOUND_OR_HASH_MISMATCH';
    END IF;


    /*
     * 5. Binding contract.
     *
     * Extra JSON keys are ignored by the identity function. Only these six
     * fields define binding_key_sha256.
     */
    IF p_binding IS NULL
       OR pg_catalog.jsonb_typeof(p_binding) <> 'object'
       OR NOT (
           p_binding ?& ARRAY[
               'context_id',
               'context_sha256',
               'target_ref',
               'requested_scope_ids',
               'producer_execution_ref',
               'entry_contract_digest_sha256'
           ]
       )

       OR pg_catalog.jsonb_typeof(p_binding->'context_id') <> 'string'
       OR NOT (
           p_binding->>'context_id'
           ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       )

       OR pg_catalog.jsonb_typeof(p_binding->'context_sha256') <> 'string'
       OR NOT (
           p_binding->>'context_sha256' ~ '^[0-9a-f]{64}$'
       )

       OR pg_catalog.jsonb_typeof(p_binding->'target_ref') <> 'string'
       OR pg_catalog.btrim(p_binding->>'target_ref') = ''

       OR pg_catalog.jsonb_typeof(
              p_binding->'requested_scope_ids'
          ) <> 'array'

       OR EXISTS (
           SELECT 1
             FROM pg_catalog.jsonb_array_elements(
                      p_binding->'requested_scope_ids'
                  ) AS item(value)
            WHERE pg_catalog.jsonb_typeof(item.value) <> 'string'
       )

       OR pg_catalog.jsonb_typeof(
              p_binding->'producer_execution_ref'
          ) <> 'string'
       OR pg_catalog.btrim(
              p_binding->>'producer_execution_ref'
          ) = ''

       OR pg_catalog.jsonb_typeof(
              p_binding->'entry_contract_digest_sha256'
          ) <> 'string'
       OR NOT (
           p_binding->>'entry_contract_digest_sha256'
           ~ '^[0-9a-f]{64}$'
       )

       OR p_binding->>'context_id' <> v_context_id::text
       OR p_binding->>'context_sha256'
          <> p_receipt->>'context_sha256'
    THEN
        RAISE EXCEPTION 'PG01_RECEIPT_BINDING_INVALID';
    END IF;


    /*
     * Normalize requested_scope_ids as a sorted unique JSON string array.
     */
    SELECT COALESCE(
               pg_catalog.jsonb_agg(scope_id ORDER BY scope_id),
               '[]'::jsonb
           )
      INTO v_requested_scope_ids
      FROM (
          SELECT DISTINCT value AS scope_id
            FROM pg_catalog.jsonb_array_elements_text(
                     p_binding->'requested_scope_ids'
                 )
      ) AS normalized_scopes;


    v_binding_canonical :=
        pg_catalog.jsonb_build_object(
            'context_id',
                v_context_id::text,
            'context_sha256',
                p_binding->>'context_sha256',
            'target_ref',
                p_binding->>'target_ref',
            'requested_scope_ids',
                v_requested_scope_ids,
            'producer_execution_ref',
                p_binding->>'producer_execution_ref',
            'entry_contract_digest_sha256',
                p_binding->>'entry_contract_digest_sha256'
        );

    v_binding_key_sha256 :=
        pg_catalog.encode(
            extensions.digest(
                pg_catalog.convert_to(
                    v_binding_canonical::text,
                    'UTF8'
                ),
                'sha256'
            ),
            'hex'
        );


    /*
     * 6. Envelope: phase 1 stores it, but does not release its admission
     * semantics. Only a non-empty schema_version is required.
     */
    IF p_envelope IS NULL
       OR pg_catalog.jsonb_typeof(p_envelope) <> 'object'
       OR NOT (p_envelope ? 'schema_version')
       OR pg_catalog.jsonb_typeof(
              p_envelope->'schema_version'
          ) <> 'string'
       OR pg_catalog.btrim(
              p_envelope->>'schema_version'
          ) = ''
    THEN
        RAISE EXCEPTION 'PG01_RECEIPT_ENVELOPE_INVALID';
    END IF;


    v_receipt_sha256 :=
        pg_catalog.encode(
            extensions.digest(
                pg_catalog.convert_to(
                    p_receipt::text,
                    'UTF8'
                ),
                'sha256'
            ),
            'hex'
        );

    v_envelope_sha256 :=
        pg_catalog.encode(
            extensions.digest(
                pg_catalog.convert_to(
                    p_envelope::text,
                    'UTF8'
                ),
                'sha256'
            ),
            'hex'
        );


    /*
     * 7. Atomic record-or-replay.
     *
     * The unique binding key is the concurrency arbiter.
     */
    INSERT INTO private.lf_programming_context_handoff_receipts_v1
    (
        binding_key_sha256,
        context_id,
        context_sha256,
        receipt,
        receipt_sha256,
        envelope,
        envelope_sha256,
        verdict,
        created_by_execution_id
    )
    VALUES
    (
        v_binding_key_sha256,
        v_context_id,
        p_receipt->>'context_sha256',
        p_receipt,
        v_receipt_sha256,
        p_envelope,
        v_envelope_sha256,
        p_receipt->>'verdict',
        p_execution_id
    )
    ON CONFLICT (binding_key_sha256) DO NOTHING
    RETURNING
        receipt_record_id,
        created_at
    INTO
        v_inserted_record_id,
        v_inserted_created_at;


    IF v_inserted_record_id IS NOT NULL THEN
        RETURN pg_catalog.jsonb_build_object(
            'schema_version',
                'PG01_RECEIPT_LEDGER_RECORD_RESULT_V1',
            'status',
                'RECORDED',
            'receipt_record_id',
                v_inserted_record_id,
            'binding_key_sha256',
                v_binding_key_sha256,
            'receipt_sha256',
                v_receipt_sha256,
            'envelope_sha256',
                v_envelope_sha256,
            'created_by_execution_id',
                p_execution_id
        );
    END IF;


    SELECT *
      INTO STRICT v_existing
      FROM private.lf_programming_context_handoff_receipts_v1
     WHERE binding_key_sha256 = v_binding_key_sha256;


    IF v_existing.receipt_sha256 = v_receipt_sha256
       AND v_existing.envelope_sha256 = v_envelope_sha256
    THEN
        RETURN pg_catalog.jsonb_build_object(
            'schema_version',
                'PG01_RECEIPT_LEDGER_RECORD_RESULT_V1',
            'status',
                'IDEMPOTENT_REPLAY',
            'receipt_record_id',
                v_existing.receipt_record_id,
            'binding_key_sha256',
                v_existing.binding_key_sha256,
            'receipt_sha256',
                v_existing.receipt_sha256,
            'envelope_sha256',
                v_existing.envelope_sha256,
            'created_by_execution_id',
                v_existing.created_by_execution_id
        );
    END IF;


    RAISE EXCEPTION
        'PG01_RECEIPT_BINDING_REPLAY_CONFLICT';
END
$function$;


CREATE OR REPLACE FUNCTION
private.fn_lf_programming_context_handoff_receipt_resolve_v1(
    p_binding jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path TO 'pg_catalog', 'private', 'public', 'extensions'
AS $function$
DECLARE
    v_context_id uuid;
    v_requested_scope_ids jsonb;
    v_binding_canonical jsonb;
    v_binding_key_sha256 text;

    v_row private.lf_programming_context_handoff_receipts_v1%ROWTYPE;

    v_computed_receipt_sha256 text;
    v_computed_envelope_sha256 text;

    v_hashes_verified boolean;
BEGIN
    /*
     * The resolver uses exactly the same binding identity as the writer.
     * Invalid bindings do not participate in lookup.
     */
    IF p_binding IS NULL
       OR pg_catalog.jsonb_typeof(p_binding) <> 'object'
       OR NOT (
           p_binding ?& ARRAY[
               'context_id',
               'context_sha256',
               'target_ref',
               'requested_scope_ids',
               'producer_execution_ref',
               'entry_contract_digest_sha256'
           ]
       )

       OR pg_catalog.jsonb_typeof(p_binding->'context_id') <> 'string'
       OR NOT (
           p_binding->>'context_id'
           ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       )

       OR pg_catalog.jsonb_typeof(p_binding->'context_sha256') <> 'string'
       OR NOT (
           p_binding->>'context_sha256'
           ~ '^[0-9a-f]{64}$'
       )

       OR pg_catalog.jsonb_typeof(p_binding->'target_ref') <> 'string'
       OR pg_catalog.btrim(p_binding->>'target_ref') = ''

       OR pg_catalog.jsonb_typeof(
              p_binding->'requested_scope_ids'
          ) <> 'array'

       OR EXISTS (
           SELECT 1
             FROM pg_catalog.jsonb_array_elements(
                      p_binding->'requested_scope_ids'
                  ) AS item(value)
            WHERE pg_catalog.jsonb_typeof(item.value) <> 'string'
       )

       OR pg_catalog.jsonb_typeof(
              p_binding->'producer_execution_ref'
          ) <> 'string'
       OR pg_catalog.btrim(
              p_binding->>'producer_execution_ref'
          ) = ''

       OR pg_catalog.jsonb_typeof(
              p_binding->'entry_contract_digest_sha256'
          ) <> 'string'
       OR NOT (
           p_binding->>'entry_contract_digest_sha256'
           ~ '^[0-9a-f]{64}$'
       )
    THEN
        RAISE EXCEPTION 'PG01_RECEIPT_BINDING_INVALID';
    END IF;


    v_context_id := (p_binding->>'context_id')::uuid;

    SELECT COALESCE(
               pg_catalog.jsonb_agg(scope_id ORDER BY scope_id),
               '[]'::jsonb
           )
      INTO v_requested_scope_ids
      FROM (
          SELECT DISTINCT value AS scope_id
            FROM pg_catalog.jsonb_array_elements_text(
                     p_binding->'requested_scope_ids'
                 )
      ) AS normalized_scopes;


    v_binding_canonical :=
        pg_catalog.jsonb_build_object(
            'context_id',
                v_context_id::text,
            'context_sha256',
                p_binding->>'context_sha256',
            'target_ref',
                p_binding->>'target_ref',
            'requested_scope_ids',
                v_requested_scope_ids,
            'producer_execution_ref',
                p_binding->>'producer_execution_ref',
            'entry_contract_digest_sha256',
                p_binding->>'entry_contract_digest_sha256'
        );

    v_binding_key_sha256 :=
        pg_catalog.encode(
            extensions.digest(
                pg_catalog.convert_to(
                    v_binding_canonical::text,
                    'UTF8'
                ),
                'sha256'
            ),
            'hex'
        );


    /*
     * Exact lookup only.
     *
     * No latest-row semantics.
     * No ORDER BY.
     * No fallback to another receipt.
     */
    SELECT *
      INTO v_row
      FROM private.lf_programming_context_handoff_receipts_v1
     WHERE binding_key_sha256 = v_binding_key_sha256;


    IF NOT FOUND THEN
        RETURN pg_catalog.jsonb_build_object(
            'found',
                false,
            'admissible',
                false,
            'reason',
                'PG01_RECEIPT_NOT_FOUND'
        );
    END IF;


    v_computed_receipt_sha256 :=
        pg_catalog.encode(
            extensions.digest(
                pg_catalog.convert_to(
                    v_row.receipt::text,
                    'UTF8'
                ),
                'sha256'
            ),
            'hex'
        );

    v_computed_envelope_sha256 :=
        pg_catalog.encode(
            extensions.digest(
                pg_catalog.convert_to(
                    v_row.envelope::text,
                    'UTF8'
                ),
                'sha256'
            ),
            'hex'
        );

    v_hashes_verified :=
        v_computed_receipt_sha256 = v_row.receipt_sha256
        AND
        v_computed_envelope_sha256 = v_row.envelope_sha256;


    /*
     * PHASE 2 MUST NOT OPEN ADMISSION UNTIL IT ALSO VERIFIES:
     *   1. the registered/authorized A9 judge;
     *   2. admitted requested scopes;
     *   3. envelope/decision validity period;
     *   4. revocation state.
     *
     * Phase 1 deliberately has no admissible=true branch.
     */
    RETURN pg_catalog.jsonb_build_object(
        'found',
            true,
        'hashes_verified',
            v_hashes_verified,
        'admissible',
            false,
        'reason',
            'PG01_ADMISSION_ENVELOPE_CONTRACT_NOT_RELEASED',
        'record',
            pg_catalog.jsonb_build_object(
                'receipt_record_id',
                    v_row.receipt_record_id,
                'binding_key_sha256',
                    v_row.binding_key_sha256,
                'context_id',
                    v_row.context_id,
                'context_sha256',
                    v_row.context_sha256,
                'receipt',
                    v_row.receipt,
                'receipt_sha256',
                    v_row.receipt_sha256,
                'envelope',
                    v_row.envelope,
                'envelope_sha256',
                    v_row.envelope_sha256,
                'verdict',
                    v_row.verdict,
                'created_by_execution_id',
                    v_row.created_by_execution_id,
                'created_at',
                    v_row.created_at
            )
    );
END
$function$;


/*
 * Ownership.
 */
ALTER TABLE
    private.lf_programming_context_handoff_receipts_v1
OWNER TO postgres;

ALTER FUNCTION
    private.fn_lf_programming_context_handoff_receipt_immutable_v1()
OWNER TO postgres;

ALTER FUNCTION
    private.fn_lf_programming_context_handoff_receipt_record_v1(
        jsonb,
        jsonb,
        jsonb,
        text
    )
OWNER TO postgres;

ALTER FUNCTION
    private.fn_lf_programming_context_handoff_receipt_resolve_v1(jsonb)
OWNER TO postgres;


/*
 * Closed permissions.
 *
 * No runtime privilege is released in phase 1.
 */
REVOKE ALL
ON TABLE private.lf_programming_context_handoff_receipts_v1
FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL
ON FUNCTION
    private.fn_lf_programming_context_handoff_receipt_immutable_v1()
FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL
ON FUNCTION
    private.fn_lf_programming_context_handoff_receipt_record_v1(
        jsonb,
        jsonb,
        jsonb,
        text
    )
FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL
ON FUNCTION
    private.fn_lf_programming_context_handoff_receipt_resolve_v1(jsonb)
FROM PUBLIC, anon, authenticated, service_role;


/*
 * Documentation.
 */
COMMENT ON TABLE
private.lf_programming_context_handoff_receipts_v1
IS
'D7 option A phase 1 append-only PG-01 receipt ledger. Stores ACCEPT/BLOCK handoff receipts and envelopes bound to the existing decision-context as-of snapshot. Storage only; admission remains closed.';


COMMENT ON FUNCTION
private.fn_lf_programming_context_handoff_receipt_record_v1(
    jsonb,
    jsonb,
    jsonb,
    text
)
IS
'D7 option A phase 1 governed PG-01 receipt writer. Verifies Train execution, receipt shape, persisted context binding, envelope presence and idempotent binding replay. Does not authorize programming admission.';


COMMENT ON FUNCTION
private.fn_lf_programming_context_handoff_receipt_resolve_v1(jsonb)
IS
'D7 option A phase 1 exact-binding PG-01 receipt resolver. Never uses latest/fallback semantics and always returns admissible=false until the admission envelope contract is released.';


COMMENT ON FUNCTION
private.fn_lf_programming_context_handoff_receipt_immutable_v1()
IS
'Append-only guard for the D7 option A phase 1 PG-01 receipt ledger.';
