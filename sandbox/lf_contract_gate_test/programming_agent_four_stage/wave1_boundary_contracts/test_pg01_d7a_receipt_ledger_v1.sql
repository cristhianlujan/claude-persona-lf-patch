\set ON_ERROR_STOP on

BEGIN;

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE SCHEMA IF NOT EXISTS private;


DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_roles
         WHERE rolname = 'anon'
    ) THEN
        EXECUTE 'CREATE ROLE anon NOLOGIN';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_roles
         WHERE rolname = 'authenticated'
    ) THEN
        EXECUTE 'CREATE ROLE authenticated NOLOGIN';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_catalog.pg_roles
         WHERE rolname = 'service_role'
    ) THEN
        EXECUTE 'CREATE ROLE service_role NOLOGIN';
    END IF;
END
$$;


/*
 * Minimal as-of snapshot stub.
 */
CREATE TABLE private.lf_decision_context_asof_v1
(
    context_id uuid NOT NULL PRIMARY KEY,
    decision_ref text NOT NULL UNIQUE,
    consumer_code text NOT NULL,
    subject_ref text NOT NULL,
    subject_version text NOT NULL,
    decided_at timestamptz NOT NULL,
    effective_at timestamptz NOT NULL,
    context_payload jsonb NOT NULL,
    context_sha256 text NOT NULL UNIQUE
        CHECK (context_sha256 ~ '^[0-9a-f]{64}$'),
    created_by_execution_id text NOT NULL,
    created_at timestamptz NOT NULL
);


CREATE OR REPLACE FUNCTION
private.fn_lf_decision_context_asof_immutable_v1()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'private'
AS $function$
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        RAISE EXCEPTION
            'BLOCK_DECISION_CONTEXT_ASOF_APPEND_ONLY:%',
            TG_OP;
    END IF;

    RETURN NEW;
END
$function$;


CREATE TRIGGER trg_00_guard_lf_decision_context_asof_v1
BEFORE INSERT OR DELETE OR UPDATE
ON private.lf_decision_context_asof_v1
FOR EACH ROW
EXECUTE FUNCTION
    private.fn_lf_decision_context_asof_immutable_v1();


/*
 * Minimal governed-execution stub.
 */
CREATE TABLE public.lf_operation_execution
(
    execution_id text NOT NULL,
    operation_code text NOT NULL,
    target_type text NOT NULL,
    target_code text NOT NULL,
    target_repo text,
    target_path text,
    status text NOT NULL,
    manifest jsonb NOT NULL,
    started_at timestamptz NOT NULL,
    completed_at timestamptz
);


/*
 * Apply the migration under test.
 *
 * Run this script from the repository root.
 */
\i supabase/migrations/20261026180000_lf_programming_context_handoff_receipt_ledger_v1.sql


CREATE TEMP TABLE pg01_test_results
(
    test_name text PRIMARY KEY
);


/*
 * Fixtures.
 */
INSERT INTO private.lf_decision_context_asof_v1
(
    context_id,
    decision_ref,
    consumer_code,
    subject_ref,
    subject_version,
    decided_at,
    effective_at,
    context_payload,
    context_sha256,
    created_by_execution_id,
    created_at
)
VALUES
(
    'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
    'TEST-D7-A-CONTEXT-1',
    'PROGRAMMING',
    'TEST-SUBJECT-1',
    'v1',
    now(),
    now(),
    '{"test":true}'::jsonb,
    repeat('1', 64),
    'EXEC-CONTEXT-TEST',
    now()
);


INSERT INTO public.lf_operation_execution
(
    execution_id,
    operation_code,
    target_type,
    target_code,
    target_repo,
    target_path,
    status,
    manifest,
    started_at,
    completed_at
)
VALUES
(
    'EXEC-PG01-OK',
    'ACTUALIZACION_DB_LF',
    'MIGRATION',
    '20261026180000_lf_programming_context_handoff_receipt_ledger_v1',
    'cristhianlujan/claude-persona-lf-patch',
    'supabase/migrations/20261026180000_lf_programming_context_handoff_receipt_ledger_v1.sql',
    'IN_PROGRESS',
    '{"producer":"lf-migration-merge-train"}'::jsonb,
    now(),
    NULL
),
(
    'EXEC-PG01-COMPLETED',
    'ACTUALIZACION_DB_LF',
    'MIGRATION',
    '20261026180000_lf_programming_context_handoff_receipt_ledger_v1',
    'cristhianlujan/claude-persona-lf-patch',
    'supabase/migrations/20261026180000_lf_programming_context_handoff_receipt_ledger_v1.sql',
    'COMPLETED',
    '{"producer":"lf-migration-merge-train"}'::jsonb,
    now(),
    now()
),
(
    'EXEC-PG01-OTHER-OP',
    'OTHER_OPERATION',
    'MIGRATION',
    '20261026180000_lf_programming_context_handoff_receipt_ledger_v1',
    'cristhianlujan/claude-persona-lf-patch',
    'supabase/migrations/20261026180000_lf_programming_context_handoff_receipt_ledger_v1.sql',
    'IN_PROGRESS',
    '{"producer":"lf-migration-merge-train"}'::jsonb,
    now(),
    NULL
),
(
    'EXEC-PG01-NO-PRODUCER',
    'ACTUALIZACION_DB_LF',
    'MIGRATION',
    '20261026180000_lf_programming_context_handoff_receipt_ledger_v1',
    'cristhianlujan/claude-persona-lf-patch',
    'supabase/migrations/20261026180000_lf_programming_context_handoff_receipt_ledger_v1.sql',
    'IN_PROGRESS',
    '{}'::jsonb,
    now(),
    NULL
);


/*
 * Test 1:
 * valid ACCEPT -> RECORDED;
 * identical replay -> IDEMPOTENT_REPLAY and same receipt_record_id.
 */
DO $$
DECLARE
    v_receipt jsonb;
    v_envelope jsonb;
    v_binding jsonb;
    v_first jsonb;
    v_second jsonb;
BEGIN
    v_receipt := jsonb_build_object(
        'schema_version',
            'PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1',
        'context_id',
            'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
        'context_sha256',
            repeat('1', 64),
        'snapshot_schema_digest_sha256',
            repeat('2', 64),
        'receiver_schema_digest_sha256',
            'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8',
        'material_projection_sha256',
            repeat('3', 64),
        'validated_material_paths',
            jsonb_build_array(
                'extensions.programming_context_snapshot.objective'
            ),
        'verdict',
            'ACCEPT'
    );

    v_envelope := jsonb_build_object(
        'schema_version',
        'PG01_TEST_ENVELOPE_V1'
    );

    v_binding := jsonb_build_object(
        'context_id',
            'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
        'context_sha256',
            repeat('1', 64),
        'target_ref',
            'TARGET-A',
        'requested_scope_ids',
            jsonb_build_array('scope.beta', 'scope.alpha', 'scope.alpha'),
        'producer_execution_ref',
            'PRODUCER-A',
        'entry_contract_digest_sha256',
            'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8'
    );

    v_first :=
        private.fn_lf_programming_context_handoff_receipt_record_v1(
            v_receipt,
            v_envelope,
            v_binding,
            'EXEC-PG01-OK'
        );

    IF v_first->>'status' <> 'RECORDED' THEN
        RAISE EXCEPTION 'TEST_FAIL:01_accept_recorded';
    END IF;

    v_second :=
        private.fn_lf_programming_context_handoff_receipt_record_v1(
            v_receipt,
            v_envelope,
            v_binding,
            'EXEC-PG01-OK'
        );

    IF v_second->>'status' <> 'IDEMPOTENT_REPLAY'
       OR v_second->>'receipt_record_id'
          <> v_first->>'receipt_record_id'
    THEN
        RAISE EXCEPTION 'TEST_FAIL:01_idempotent_replay';
    END IF;

    INSERT INTO pg01_test_results VALUES ('01');
END
$$;


/*
 * Test 2: valid BLOCK receipt can be recorded.
 */
DO $$
DECLARE
    v_result jsonb;
BEGIN
    v_result :=
        private.fn_lf_programming_context_handoff_receipt_record_v1(
            jsonb_build_object(
                'schema_version',
                    'PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1',
                'context_id',
                    'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
                'context_sha256',
                    repeat('1', 64),
                'snapshot_schema_digest_sha256',
                    repeat('2', 64),
                'receiver_schema_digest_sha256',
                    'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8',
                'material_projection_sha256',
                    repeat('4', 64),
                'validated_material_paths',
                    jsonb_build_array('path.block'),
                'verdict',
                    'BLOCK'
            ),
            '{"schema_version":"PG01_TEST_ENVELOPE_V1"}'::jsonb,
            jsonb_build_object(
                'context_id',
                    'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
                'context_sha256',
                    repeat('1', 64),
                'target_ref',
                    'TARGET-B',
                'requested_scope_ids',
                    jsonb_build_array('scope.block'),
                'producer_execution_ref',
                    'PRODUCER-B',
                'entry_contract_digest_sha256',
                    'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8'
            ),
            'EXEC-PG01-OK'
        );

    IF v_result->>'status' <> 'RECORDED' THEN
        RAISE EXCEPTION 'TEST_FAIL:02_block_recorded';
    END IF;

    INSERT INTO pg01_test_results VALUES ('02');
END
$$;


/*
 * Test 3:
 * same binding plus different persisted content -> conflict.
 */
DO $$
DECLARE
    v_failed boolean := false;
BEGIN
    BEGIN
        PERFORM private.fn_lf_programming_context_handoff_receipt_record_v1(
            jsonb_build_object(
                'schema_version',
                    'PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1',
                'context_id',
                    'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
                'context_sha256',
                    repeat('1', 64),
                'snapshot_schema_digest_sha256',
                    repeat('2', 64),
                'receiver_schema_digest_sha256',
                    'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8',
                'material_projection_sha256',
                    repeat('3', 64),
                'validated_material_paths',
                    jsonb_build_array(
                        'extensions.programming_context_snapshot.objective'
                    ),
                'verdict',
                    'ACCEPT'
            ),
            '{"schema_version":"DIFFERENT_ENVELOPE_V1"}'::jsonb,
            jsonb_build_object(
                'context_id',
                    'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
                'context_sha256',
                    repeat('1', 64),
                'target_ref',
                    'TARGET-A',
                'requested_scope_ids',
                    jsonb_build_array(
                        'scope.alpha',
                        'scope.beta'
                    ),
                'producer_execution_ref',
                    'PRODUCER-A',
                'entry_contract_digest_sha256',
                    'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8'
            ),
            'EXEC-PG01-OK'
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE
               'PG01_RECEIPT_BINDING_REPLAY_CONFLICT%'
            THEN
                v_failed := true;
            ELSE
                RAISE;
            END IF;
    END;

    IF NOT v_failed THEN
        RAISE EXCEPTION 'TEST_FAIL:03_binding_conflict';
    END IF;

    INSERT INTO pg01_test_results VALUES ('03');
END
$$;


/*
 * Test 4:
 * nonexistent context and mismatching context hash.
 */
DO $$
DECLARE
    v_expected boolean;
BEGIN
    v_expected := false;

    BEGIN
        PERFORM private.fn_lf_programming_context_handoff_receipt_record_v1(
            jsonb_build_object(
                'schema_version',
                    'PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1',
                'context_id',
                    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                'context_sha256',
                    repeat('5', 64),
                'snapshot_schema_digest_sha256',
                    repeat('2', 64),
                'receiver_schema_digest_sha256',
                    'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8',
                'material_projection_sha256',
                    repeat('3', 64),
                'validated_material_paths',
                    jsonb_build_array('path'),
                'verdict',
                    'ACCEPT'
            ),
            '{"schema_version":"E1"}'::jsonb,
            jsonb_build_object(
                'context_id',
                    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                'context_sha256',
                    repeat('5', 64),
                'target_ref',
                    'TARGET-X',
                'requested_scope_ids',
                    jsonb_build_array('scope.x'),
                'producer_execution_ref',
                    'PRODUCER-X',
                'entry_contract_digest_sha256',
                    repeat('6', 64)
            ),
            'EXEC-PG01-OK'
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE
               'PG01_RECEIPT_CONTEXT_NOT_FOUND_OR_HASH_MISMATCH%'
            THEN
                v_expected := true;
            ELSE
                RAISE;
            END IF;
    END;

    IF NOT v_expected THEN
        RAISE EXCEPTION 'TEST_FAIL:04_context_not_found';
    END IF;


    v_expected := false;

    BEGIN
        PERFORM private.fn_lf_programming_context_handoff_receipt_record_v1(
            jsonb_build_object(
                'schema_version',
                    'PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1',
                'context_id',
                    'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
                'context_sha256',
                    repeat('9', 64),
                'snapshot_schema_digest_sha256',
                    repeat('2', 64),
                'receiver_schema_digest_sha256',
                    'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8',
                'material_projection_sha256',
                    repeat('3', 64),
                'validated_material_paths',
                    jsonb_build_array('path'),
                'verdict',
                    'ACCEPT'
            ),
            '{"schema_version":"E1"}'::jsonb,
            jsonb_build_object(
                'context_id',
                    'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
                'context_sha256',
                    repeat('9', 64),
                'target_ref',
                    'TARGET-X',
                'requested_scope_ids',
                    jsonb_build_array('scope.x'),
                'producer_execution_ref',
                    'PRODUCER-X',
                'entry_contract_digest_sha256',
                    repeat('6', 64)
            ),
            'EXEC-PG01-OK'
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE
               'PG01_RECEIPT_CONTEXT_NOT_FOUND_OR_HASH_MISMATCH%'
            THEN
                v_expected := true;
            ELSE
                RAISE;
            END IF;
    END;

    IF NOT v_expected THEN
        RAISE EXCEPTION 'TEST_FAIL:04_context_hash_mismatch';
    END IF;

    INSERT INTO pg01_test_results VALUES ('04');
END
$$;


/*
 * Test 5:
 * extra key, missing key, invalid verdict and malformed digest
 * all fail at receipt shape validation.
 */
DO $$
DECLARE
    v_base jsonb;
    v_binding jsonb;
    v_expected boolean;
BEGIN
    v_base := jsonb_build_object(
        'schema_version',
            'PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1',
        'context_id',
            'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
        'context_sha256',
            repeat('1', 64),
        'snapshot_schema_digest_sha256',
            repeat('2', 64),
        'receiver_schema_digest_sha256',
            'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8',
        'material_projection_sha256',
            repeat('3', 64),
        'validated_material_paths',
            jsonb_build_array('path'),
        'verdict',
            'ACCEPT'
    );

    v_binding := jsonb_build_object(
        'context_id',
            'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
        'context_sha256',
            repeat('1', 64),
        'target_ref',
            'TARGET-SHAPE',
        'requested_scope_ids',
            jsonb_build_array('scope'),
        'producer_execution_ref',
            'PRODUCER-SHAPE',
        'entry_contract_digest_sha256',
            repeat('6', 64)
    );


    v_expected := false;
    BEGIN
        PERFORM private.fn_lf_programming_context_handoff_receipt_record_v1(
            v_base || '{"extra":"forbidden"}'::jsonb,
            '{"schema_version":"E1"}',
            v_binding,
            'EXEC-PG01-OK'
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'PG01_RECEIPT_SHAPE_INVALID%' THEN
                v_expected := true;
            ELSE
                RAISE;
            END IF;
    END;

    IF NOT v_expected THEN
        RAISE EXCEPTION 'TEST_FAIL:05_extra_key';
    END IF;


    v_expected := false;
    BEGIN
        PERFORM private.fn_lf_programming_context_handoff_receipt_record_v1(
            v_base - 'material_projection_sha256',
            '{"schema_version":"E1"}',
            v_binding,
            'EXEC-PG01-OK'
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'PG01_RECEIPT_SHAPE_INVALID%' THEN
                v_expected := true;
            ELSE
                RAISE;
            END IF;
    END;

    IF NOT v_expected THEN
        RAISE EXCEPTION 'TEST_FAIL:05_missing_key';
    END IF;


    v_expected := false;
    BEGIN
        PERFORM private.fn_lf_programming_context_handoff_receipt_record_v1(
            jsonb_set(v_base, '{verdict}', '"MAYBE"'::jsonb),
            '{"schema_version":"E1"}',
            v_binding,
            'EXEC-PG01-OK'
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'PG01_RECEIPT_SHAPE_INVALID%' THEN
                v_expected := true;
            ELSE
                RAISE;
            END IF;
    END;

    IF NOT v_expected THEN
        RAISE EXCEPTION 'TEST_FAIL:05_invalid_verdict';
    END IF;


    v_expected := false;
    BEGIN
        PERFORM private.fn_lf_programming_context_handoff_receipt_record_v1(
            jsonb_set(
                v_base,
                '{material_projection_sha256}',
                '"not-a-sha256"'::jsonb
            ),
            '{"schema_version":"E1"}',
            v_binding,
            'EXEC-PG01-OK'
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'PG01_RECEIPT_SHAPE_INVALID%' THEN
                v_expected := true;
            ELSE
                RAISE;
            END IF;
    END;

    IF NOT v_expected THEN
        RAISE EXCEPTION 'TEST_FAIL:05_malformed_digest';
    END IF;

    INSERT INTO pg01_test_results VALUES ('05');
END
$$;


/*
 * Test 6:
 * well-formed but different receiver digest.
 */
DO $$
DECLARE
    v_expected boolean := false;
BEGIN
    BEGIN
        PERFORM private.fn_lf_programming_context_handoff_receipt_record_v1(
            jsonb_build_object(
                'schema_version',
                    'PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1',
                'context_id',
                    'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
                'context_sha256',
                    repeat('1', 64),
                'snapshot_schema_digest_sha256',
                    repeat('2', 64),
                'receiver_schema_digest_sha256',
                    repeat('f', 64),
                'material_projection_sha256',
                    repeat('3', 64),
                'validated_material_paths',
                    jsonb_build_array('path'),
                'verdict',
                    'ACCEPT'
            ),
            '{"schema_version":"E1"}',
            jsonb_build_object(
                'context_id',
                    'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
                'context_sha256',
                    repeat('1', 64),
                'target_ref',
                    'TARGET-DIGEST',
                'requested_scope_ids',
                    jsonb_build_array('scope'),
                'producer_execution_ref',
                    'PRODUCER-DIGEST',
                'entry_contract_digest_sha256',
                    repeat('6', 64)
            ),
            'EXEC-PG01-OK'
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE
               'PG01_RECEIPT_RECEIVER_DIGEST_MISMATCH%'
            THEN
                v_expected := true;
            ELSE
                RAISE;
            END IF;
    END;

    IF NOT v_expected THEN
        RAISE EXCEPTION 'TEST_FAIL:06_receiver_digest_mismatch';
    END IF;

    INSERT INTO pg01_test_results VALUES ('06');
END
$$;


/*
 * Test 7:
 * invalid writer executions.
 */
DO $$
DECLARE
    v_receipt jsonb;
    v_binding jsonb;
    v_exec text;
    v_expected boolean;
BEGIN
    v_receipt := jsonb_build_object(
        'schema_version',
            'PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1',
        'context_id',
            'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
        'context_sha256',
            repeat('1', 64),
        'snapshot_schema_digest_sha256',
            repeat('2', 64),
        'receiver_schema_digest_sha256',
            'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8',
        'material_projection_sha256',
            repeat('3', 64),
        'validated_material_paths',
            jsonb_build_array('path'),
        'verdict',
            'ACCEPT'
    );

    v_binding := jsonb_build_object(
        'context_id',
            'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
        'context_sha256',
            repeat('1', 64),
        'target_ref',
            'TARGET-AUTH',
        'requested_scope_ids',
            jsonb_build_array('scope'),
        'producer_execution_ref',
            'PRODUCER-AUTH',
        'entry_contract_digest_sha256',
            repeat('6', 64)
    );

    FOREACH v_exec IN ARRAY ARRAY[
        'EXEC-PG01-MISSING',
        'EXEC-PG01-COMPLETED',
        'EXEC-PG01-OTHER-OP',
        'EXEC-PG01-NO-PRODUCER'
    ]
    LOOP
        v_expected := false;

        BEGIN
            PERFORM private.fn_lf_programming_context_handoff_receipt_record_v1(
                v_receipt,
                '{"schema_version":"E1"}',
                v_binding,
                v_exec
            );
        EXCEPTION
            WHEN OTHERS THEN
                IF SQLERRM LIKE
                   'PG01_RECEIPT_WRITER_EXECUTION_NOT_AUTHORIZED%'
                THEN
                    v_expected := true;
                ELSE
                    RAISE;
                END IF;
        END;

        IF NOT v_expected THEN
            RAISE EXCEPTION
                'TEST_FAIL:07_writer_execution:%',
                v_exec;
        END IF;
    END LOOP;

    INSERT INTO pg01_test_results VALUES ('07');
END
$$;


/*
 * Test 8:
 * incomplete binding and context mismatch.
 */
DO $$
DECLARE
    v_receipt jsonb;
    v_expected boolean;
BEGIN
    v_receipt := jsonb_build_object(
        'schema_version',
            'PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1',
        'context_id',
            'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
        'context_sha256',
            repeat('1', 64),
        'snapshot_schema_digest_sha256',
            repeat('2', 64),
        'receiver_schema_digest_sha256',
            'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8',
        'material_projection_sha256',
            repeat('3', 64),
        'validated_material_paths',
            jsonb_build_array('path'),
        'verdict',
            'ACCEPT'
    );


    v_expected := false;

    BEGIN
        PERFORM private.fn_lf_programming_context_handoff_receipt_record_v1(
            v_receipt,
            '{"schema_version":"E1"}',
            jsonb_build_object(
                'context_id',
                    'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
                'context_sha256',
                    repeat('1', 64)
            ),
            'EXEC-PG01-OK'
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'PG01_RECEIPT_BINDING_INVALID%' THEN
                v_expected := true;
            ELSE
                RAISE;
            END IF;
    END;

    IF NOT v_expected THEN
        RAISE EXCEPTION 'TEST_FAIL:08_binding_incomplete';
    END IF;


    v_expected := false;

    BEGIN
        PERFORM private.fn_lf_programming_context_handoff_receipt_record_v1(
            v_receipt,
            '{"schema_version":"E1"}',
            jsonb_build_object(
                'context_id',
                    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                'context_sha256',
                    repeat('1', 64),
                'target_ref',
                    'TARGET-BINDING-MISMATCH',
                'requested_scope_ids',
                    jsonb_build_array('scope'),
                'producer_execution_ref',
                    'PRODUCER',
                'entry_contract_digest_sha256',
                    repeat('6', 64)
            ),
            'EXEC-PG01-OK'
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'PG01_RECEIPT_BINDING_INVALID%' THEN
                v_expected := true;
            ELSE
                RAISE;
            END IF;
    END;

    IF NOT v_expected THEN
        RAISE EXCEPTION 'TEST_FAIL:08_binding_context_mismatch';
    END IF;

    INSERT INTO pg01_test_results VALUES ('08');
END
$$;


/*
 * Test 9:
 * envelope without schema_version.
 */
DO $$
DECLARE
    v_expected boolean := false;
BEGIN
    BEGIN
        PERFORM private.fn_lf_programming_context_handoff_receipt_record_v1(
            jsonb_build_object(
                'schema_version',
                    'PROGRAMMING_CONTEXT_HANDOFF_RECEIPT_V1',
                'context_id',
                    'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
                'context_sha256',
                    repeat('1', 64),
                'snapshot_schema_digest_sha256',
                    repeat('2', 64),
                'receiver_schema_digest_sha256',
                    'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8',
                'material_projection_sha256',
                    repeat('3', 64),
                'validated_material_paths',
                    jsonb_build_array('path'),
                'verdict',
                    'ACCEPT'
            ),
            '{"payload":"missing schema version"}',
            jsonb_build_object(
                'context_id',
                    'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
                'context_sha256',
                    repeat('1', 64),
                'target_ref',
                    'TARGET-ENVELOPE',
                'requested_scope_ids',
                    jsonb_build_array('scope'),
                'producer_execution_ref',
                    'PRODUCER',
                'entry_contract_digest_sha256',
                    repeat('6', 64)
            ),
            'EXEC-PG01-OK'
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE 'PG01_RECEIPT_ENVELOPE_INVALID%' THEN
                v_expected := true;
            ELSE
                RAISE;
            END IF;
    END;

    IF NOT v_expected THEN
        RAISE EXCEPTION 'TEST_FAIL:09_envelope_invalid';
    END IF;

    INSERT INTO pg01_test_results VALUES ('09');
END
$$;


/*
 * Test 10:
 * UPDATE and DELETE are blocked.
 */
DO $$
DECLARE
    v_id uuid;
    v_update_blocked boolean := false;
    v_delete_blocked boolean := false;
BEGIN
    SELECT receipt_record_id
      INTO v_id
      FROM private.lf_programming_context_handoff_receipts_v1
     WHERE verdict = 'ACCEPT'
     LIMIT 1;

    IF v_id IS NULL THEN
        RAISE EXCEPTION 'TEST_FAIL:10_fixture_missing';
    END IF;


    BEGIN
        UPDATE private.lf_programming_context_handoff_receipts_v1
           SET verdict = verdict
         WHERE receipt_record_id = v_id;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE
               'BLOCK_PG01_RECEIPT_LEDGER_APPEND_ONLY:UPDATE%'
            THEN
                v_update_blocked := true;
            ELSE
                RAISE;
            END IF;
    END;


    BEGIN
        DELETE
          FROM private.lf_programming_context_handoff_receipts_v1
         WHERE receipt_record_id = v_id;
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM LIKE
               'BLOCK_PG01_RECEIPT_LEDGER_APPEND_ONLY:DELETE%'
            THEN
                v_delete_blocked := true;
            ELSE
                RAISE;
            END IF;
    END;


    IF NOT v_update_blocked OR NOT v_delete_blocked THEN
        RAISE EXCEPTION 'TEST_FAIL:10_append_only';
    END IF;

    INSERT INTO pg01_test_results VALUES ('10');
END
$$;


/*
 * Test 11:
 * exact reader:
 *   existing -> found, hashes verified, closed admission;
 *   absent exact binding -> found=false, no fallback.
 */
DO $$
DECLARE
    v_existing jsonb;
    v_missing jsonb;
    v_expected_id uuid;
BEGIN
    SELECT receipt_record_id
      INTO v_expected_id
      FROM private.lf_programming_context_handoff_receipts_v1
     WHERE verdict = 'ACCEPT'
       AND receipt->>'material_projection_sha256' = repeat('3', 64)
     LIMIT 1;

    v_existing :=
        private.fn_lf_programming_context_handoff_receipt_resolve_v1(
            jsonb_build_object(
                'context_id',
                    'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
                'context_sha256',
                    repeat('1', 64),
                'target_ref',
                    'TARGET-A',
                'requested_scope_ids',
                    jsonb_build_array('scope.alpha', 'scope.beta'),
                'producer_execution_ref',
                    'PRODUCER-A',
                'entry_contract_digest_sha256',
                    'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8'
            )
        );

    IF COALESCE((v_existing->>'found')::boolean, false) IS NOT TRUE
       OR COALESCE(
              (v_existing->>'hashes_verified')::boolean,
              false
          ) IS NOT TRUE
       OR COALESCE(
              (v_existing->>'admissible')::boolean,
              true
          ) IS NOT FALSE
       OR v_existing->>'reason'
          <> 'PG01_ADMISSION_ENVELOPE_CONTRACT_NOT_RELEASED'
       OR v_existing#>>'{record,receipt_record_id}'
          <> v_expected_id::text
    THEN
        RAISE EXCEPTION 'TEST_FAIL:11_existing_reader';
    END IF;


    v_missing :=
        private.fn_lf_programming_context_handoff_receipt_resolve_v1(
            jsonb_build_object(
                'context_id',
                    'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
                'context_sha256',
                    repeat('1', 64),
                'target_ref',
                    'TARGET-NOT-RECORDED',
                'requested_scope_ids',
                    jsonb_build_array('scope.alpha'),
                'producer_execution_ref',
                    'PRODUCER-A',
                'entry_contract_digest_sha256',
                    'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8'
            )
        );

    IF COALESCE((v_missing->>'found')::boolean, true) IS NOT FALSE
       OR COALESCE((v_missing->>'admissible')::boolean, true) IS NOT FALSE
       OR v_missing->>'reason' <> 'PG01_RECEIPT_NOT_FOUND'
    THEN
        RAISE EXCEPTION 'TEST_FAIL:11_missing_reader';
    END IF;

    IF v_missing ? 'record' THEN
        RAISE EXCEPTION 'TEST_FAIL:11_no_fallback_row';
    END IF;

    INSERT INTO pg01_test_results VALUES ('11');
END
$$;


/*
 * Test 12:
 * requested_scope_ids order and duplication do not alter identity.
 */
DO $$
DECLARE
    v_a jsonb;
    v_b jsonb;
BEGIN
    v_a :=
        private.fn_lf_programming_context_handoff_receipt_resolve_v1(
            jsonb_build_object(
                'context_id',
                    'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
                'context_sha256',
                    repeat('1', 64),
                'target_ref',
                    'TARGET-A',
                'requested_scope_ids',
                    jsonb_build_array(
                        'scope.beta',
                        'scope.alpha',
                        'scope.alpha'
                    ),
                'producer_execution_ref',
                    'PRODUCER-A',
                'entry_contract_digest_sha256',
                    'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8'
            )
        );

    v_b :=
        private.fn_lf_programming_context_handoff_receipt_resolve_v1(
            jsonb_build_object(
                'context_id',
                    'c4f7d9e4-3d29-4d12-950b-0b7ef25e7c5c',
                'context_sha256',
                    repeat('1', 64),
                'target_ref',
                    'TARGET-A',
                'requested_scope_ids',
                    jsonb_build_array(
                        'scope.alpha',
                        'scope.beta'
                    ),
                'producer_execution_ref',
                    'PRODUCER-A',
                'entry_contract_digest_sha256',
                    'd2e347efe07a9971790f1a605f0b6ab93fa48a1608744330d1e49e59930d7fb8'
            )
        );

    IF COALESCE((v_a->>'found')::boolean, false) IS NOT TRUE
       OR COALESCE((v_b->>'found')::boolean, false) IS NOT TRUE
       OR v_a#>>'{record,binding_key_sha256}'
          <> v_b#>>'{record,binding_key_sha256}'
       OR v_a#>>'{record,receipt_record_id}'
          <> v_b#>>'{record,receipt_record_id}'
    THEN
        RAISE EXCEPTION 'TEST_FAIL:12_scope_normalization';
    END IF;

    INSERT INTO pg01_test_results VALUES ('12');
END
$$;


/*
 * Test 13:
 * anon and authenticated cannot read the ledger or execute either API.
 *
 * Lack of private-schema USAGE also counts as correctly closed access;
 * no privilege is granted merely to make the negative test reach the
 * underlying object.
 */

SET ROLE anon;

DO $$
DECLARE
    v_table_blocked boolean := false;
    v_writer_blocked boolean := false;
    v_reader_blocked boolean := false;
BEGIN
    BEGIN
        PERFORM count(*)
          FROM private.lf_programming_context_handoff_receipts_v1;
    EXCEPTION
        WHEN insufficient_privilege THEN
            v_table_blocked := true;
    END;

    BEGIN
        PERFORM private.fn_lf_programming_context_handoff_receipt_record_v1(
            '{}'::jsonb,
            '{}'::jsonb,
            '{}'::jsonb,
            'EXEC-PG01-OK'
        );
    EXCEPTION
        WHEN insufficient_privilege THEN
            v_writer_blocked := true;
    END;

    BEGIN
        PERFORM private.fn_lf_programming_context_handoff_receipt_resolve_v1(
            '{}'::jsonb
        );
    EXCEPTION
        WHEN insufficient_privilege THEN
            v_reader_blocked := true;
    END;

    IF NOT v_table_blocked
       OR NOT v_writer_blocked
       OR NOT v_reader_blocked
    THEN
        RAISE EXCEPTION 'TEST_FAIL:13_anon_permissions';
    END IF;
END
$$;

RESET ROLE;


SET ROLE authenticated;

DO $$
DECLARE
    v_table_blocked boolean := false;
    v_writer_blocked boolean := false;
    v_reader_blocked boolean := false;
BEGIN
    BEGIN
        PERFORM count(*)
          FROM private.lf_programming_context_handoff_receipts_v1;
    EXCEPTION
        WHEN insufficient_privilege THEN
            v_table_blocked := true;
    END;

    BEGIN
        PERFORM private.fn_lf_programming_context_handoff_receipt_record_v1(
            '{}'::jsonb,
            '{}'::jsonb,
            '{}'::jsonb,
            'EXEC-PG01-OK'
        );
    EXCEPTION
        WHEN insufficient_privilege THEN
            v_writer_blocked := true;
    END;

    BEGIN
        PERFORM private.fn_lf_programming_context_handoff_receipt_resolve_v1(
            '{}'::jsonb
        );
    EXCEPTION
        WHEN insufficient_privilege THEN
            v_reader_blocked := true;
    END;

    IF NOT v_table_blocked
       OR NOT v_writer_blocked
       OR NOT v_reader_blocked
    THEN
        RAISE EXCEPTION 'TEST_FAIL:13_authenticated_permissions';
    END IF;
END
$$;

RESET ROLE;

INSERT INTO pg01_test_results VALUES ('13');


/*
 * Final accounting.
 */
DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT count(*)
      INTO v_count
      FROM pg01_test_results;

    IF v_count <> 13 THEN
        RAISE EXCEPTION
            'TEST_FAIL:TOTAL_EXPECTED_13_GOT_%',
            v_count;
    END IF;

    RAISE NOTICE 'PG01_D7A_TESTS_PASSED:%', v_count;
END
$$;

ROLLBACK;
