import hashlib

STATEMENTS = {
    "A_INVALIDATED_TERMINAL_COMPACTION": """UPDATE programacion.input_family_assessments a
SET validator_evidence =
      (a.validator_evidence - 'assertions')
      || jsonb_build_object('assertion_set_sha256',s.assertion_set_sha256)
FROM programacion.input_validator_assertion_sets_v1 s
WHERE a.id=21079
  AND s.assertions=a.validator_evidence->'assertions'
RETURNING a.validator_sha256,a.validator_evidence""",
    "B_CURRENT_TERMINAL_COMPACTION": """UPDATE programacion.input_family_assessments a
SET validator_evidence =
      (a.validator_evidence - 'assertions')
      || jsonb_build_object('assertion_set_sha256',s.assertion_set_sha256)
FROM programacion.input_validator_assertion_sets_v1 s
WHERE a.id=21689
  AND s.assertions=a.validator_evidence->'assertions'
RETURNING a.validator_sha256,a.validator_evidence""",
    "C1_NEGATIVE_OTHER_ASSERTIONS": """UPDATE programacion.input_family_assessments a
SET validator_evidence =
      (a.validator_evidence - 'assertions')
      || jsonb_build_object(
           'assertion_set_sha256',
           (
             SELECT s.assertion_set_sha256
             FROM programacion.input_validator_assertion_sets_v1 s
             WHERE s.assertions<>a.validator_evidence->'assertions'
             ORDER BY s.assertion_set_sha256
             LIMIT 1
           )
         )
WHERE a.id=21078""",
    "C2_NEGATIVE_VALIDATOR_SHA": """UPDATE programacion.input_family_assessments a
SET validator_evidence =
      (a.validator_evidence - 'assertions')
      || jsonb_build_object('assertion_set_sha256',s.assertion_set_sha256),
    validator_sha256 =
      (CASE WHEN left(a.validator_sha256,1)='0' THEN '1' ELSE '0' END)
      || substring(a.validator_sha256 from 2)
FROM programacion.input_validator_assertion_sets_v1 s
WHERE a.id=21077
  AND s.assertions=a.validator_evidence->'assertions'""",
    "D_PENDING_TO_TERMINAL_COMPACT": """UPDATE programacion.input_family_assessments a
SET validator_outcome=p.validator_outcome,
    validator_findings=p.validator_findings,
    validator_evidence=p.compact_evidence,
    validator_identity=p.validator_identity,
    validator_sha256=p.inline_validator_sha256,
    validator_assessed_at=p.validator_assessed_at
FROM _r5c_d_payload p
WHERE a.id=p.assessment_id
RETURNING a.validator_sha256""",
}

EXPECTED = {
    "A_INVALIDATED_TERMINAL_COMPACTION": "2fa1492dee91273fdd34b040dcda7bdacf78c071787987426b99efbcb24d9ec4",
    "B_CURRENT_TERMINAL_COMPACTION": "204845c680f366c1433465e04bf90dcab2180716082733ae02cc8c7fbc346aeb",
    "C1_NEGATIVE_OTHER_ASSERTIONS": "c84f1b24ca71205912d4e3d4a690c4fc6cfa81a3755c103a90cfa010846bf0dc",
    "C2_NEGATIVE_VALIDATOR_SHA": "fc521184a590e0c7f4829fae09bf73e4bc1474e301ed4999b23a24f525bc3720",
    "D_PENDING_TO_TERMINAL_COMPACT": "13a2ac2a5975ce535e36406593a135063c9e6e8df0494ab092da7dad9ea211e4",
}


def test_r5c_live_probe_statement_sha256_receipts():
    assert set(STATEMENTS) == set(EXPECTED)
    for name, statement in STATEMENTS.items():
        assert hashlib.sha256(statement.encode("utf-8")).hexdigest() == EXPECTED[name]
