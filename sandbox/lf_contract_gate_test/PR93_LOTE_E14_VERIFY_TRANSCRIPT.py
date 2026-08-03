#!/usr/bin/env python3
"""Transcript verification for PR #93 LOTE-E.14."""
from __future__ import annotations

import json
from typing import Any

import PR93_LOTE_E14_SEMANTICS as semantics
from PR93_LOTE_E14_VERIFY_COMMON import (
    canonical_json_bytes,
    exact_index,
    fail,
    parse_bool_line,
    parse_int_line,
    prefix_index,
)

def verify_transcript(
    receipt: dict[str, Any],
    loaded: dict[str, bytes],
) -> None:
    full_lines = loaded["PR93_E14_FULL_TRANSCRIPT.log"].decode(
        "utf-8", "strict"
    ).splitlines()
    t1_lines = loaded["PR93_E14_T1_TRANSCRIPT.log"].decode(
        "utf-8", "strict"
    ).splitlines()
    t2_lines = loaded["PR93_E14_T2_TRANSCRIPT.log"].decode(
        "utf-8", "strict"
    ).splitlines()
    if not full_lines or full_lines[0] != "E14_CAPTURE_BEGIN":
        fail("full transcript must start with E14_CAPTURE_BEGIN")
    if full_lines[-1] != "E14_CAPTURE_END":
        fail("full transcript must end with E14_CAPTURE_END")

    i_head = prefix_index(full_lines, "E14_HEAD_SHA=")
    i_started = prefix_index(full_lines, "E14_STARTED_AT=")
    i_t1_begin = exact_index(full_lines, "E14_T1_PROCESS_BEGIN")
    i_t1_exit = prefix_index(full_lines, "E14_T1_PROCESS_EXIT=")
    i_pre_begin = exact_index(full_lines, "E14_T2_PRE_STATE_BEGIN")
    i_pre_exit = prefix_index(full_lines, "E14_T2_PRE_STATE_EXIT=")
    i_t2_begin = exact_index(full_lines, "E14_T2_PROCESS_BEGIN")
    i_t2_exit = prefix_index(full_lines, "E14_T2_PROCESS_EXIT=")
    i_post_begin = exact_index(full_lines, "E14_T2_POST_STATE_BEGIN")
    i_post_exit = prefix_index(full_lines, "E14_T2_POST_STATE_EXIT=")
    i_match = prefix_index(full_lines, "E14_T2_STATE_MATCH=")
    i_rollback = prefix_index(full_lines, "E14_T2_ROLLBACK_STATUS=")
    i_overall = prefix_index(full_lines, "E14_OVERALL_STATUS=")
    i_finished = prefix_index(full_lines, "E14_FINISHED_AT=")
    i_end = exact_index(full_lines, "E14_CAPTURE_END")

    indexes = [
        0, i_head, i_started, i_t1_begin, i_t1_exit, i_pre_begin, i_pre_exit,
        i_t2_begin, i_t2_exit, i_post_begin, i_post_exit, i_match, i_rollback,
        i_overall, i_finished, i_end,
    ]
    if indexes != sorted(indexes) or len(indexes) != len(set(indexes)):
        fail("full transcript markers are not in strict order")
    if i_head != 1 or i_started != 2 or i_t1_begin != 3:
        fail("unexpected content exists before T1")
    if i_end != len(full_lines) - 1:
        fail("content exists after E14_CAPTURE_END")
    if full_lines[i_head].split("=", 1)[1] != receipt.get("head_sha"):
        fail("full transcript head differs from receipt")

    if full_lines[i_t1_begin + 1:i_t1_exit] != t1_lines:
        fail("embedded T1 differs from T1 evidence file")
    if full_lines[i_t2_begin + 1:i_t2_exit] != t2_lines:
        fail("embedded T2 differs from T2 evidence file")

    pre_lines = full_lines[i_pre_begin + 1:i_pre_exit]
    post_lines = full_lines[i_post_begin + 1:i_post_exit]
    if pre_lines != loaded["PR93_E14_PRE_STATE.json"].decode(
        "utf-8", "strict"
    ).splitlines():
        fail("embedded pre-state differs from state file")
    if post_lines != loaded["PR93_E14_POST_STATE.json"].decode(
        "utf-8", "strict"
    ).splitlines():
        fail("embedded post-state differs from state file")

    computed_semantics = semantics.parse_t1_semantics(
        loaded["PR93_E14_T1_TRANSCRIPT.log"],
        receipt["head_sha"],
    )
    if computed_semantics != receipt.get("t1", {}).get("semantic_checks"):
        fail("T1 semantic checks differ from independently computed result")
    if receipt.get("t1", {}).get("status") == "PASS":
        if computed_semantics.get("all_pass") is not True:
            fail("T1 PASS lacks complete semantic readiness")

    if any(line.startswith("E13_T1_HEAD_SHA=") for line in t2_lines):
        fail("T1 head marker is forbidden inside T2")
    if any(line.startswith("E14_HEAD_SHA=") for line in t2_lines):
        fail("capture-envelope head marker is forbidden inside T2")
    expected_t2_head = f"E13_T2_HEAD_SHA={receipt['head_sha']}"
    receipt_t2_exit = receipt.get("t2", {}).get("exit_code")
    if receipt_t2_exit == 99:
        if t2_lines != ["E14_T2_NOT_EXECUTED"]:
            fail("non-executed T2 transcript is not canonical")
    elif sum(line == expected_t2_head for line in t2_lines) != 1:
        fail("T2 head marker is missing, duplicated or contradictory")

    pre_state_data = loaded["PR93_E14_PRE_STATE.json"]
    post_state_data = loaded["PR93_E14_POST_STATE.json"]
    try:
        pre_state = json.loads(pre_state_data.decode("utf-8", "strict"))
        post_state = json.loads(post_state_data.decode("utf-8", "strict"))
    except json.JSONDecodeError as exc:
        raise ValueError("state JSON is invalid") from exc
    if pre_state_data != canonical_json_bytes(pre_state):
        fail("pre-state JSON is not canonical")
    if post_state_data != canonical_json_bytes(post_state):
        fail("post-state JSON is not canonical")

    t1_exit = parse_int_line(full_lines, "E14_T1_PROCESS_EXIT=")
    t2_exit = parse_int_line(full_lines, "E14_T2_PROCESS_EXIT=")
    pre_exit = parse_int_line(full_lines, "E14_T2_PRE_STATE_EXIT=")
    post_exit = parse_int_line(full_lines, "E14_T2_POST_STATE_EXIT=")
    state_match = parse_bool_line(full_lines, "E14_T2_STATE_MATCH=")

    def parse_state_log(name: str, exit_code: int, state_value: Any) -> None:
        data = loaded[name]
        if exit_code == 0:
            try:
                parsed = json.loads(data.decode("utf-8", "strict").strip())
            except json.JSONDecodeError as exc:
                raise ValueError(f"{name} is not valid JSON") from exc
            if parsed != state_value:
                fail(f"{name} differs from canonical state file")
        elif state_value is not None:
            fail(f"{name} failed but state file is not null")

    parse_state_log("PR93_E14_PRE_STATE_COMMAND.log", pre_exit, pre_state)
    parse_state_log("PR93_E14_POST_STATE_COMMAND.log", post_exit, post_state)

    for label, state_value, exit_code in (
        ("pre-state", pre_state, pre_exit),
        ("post-state", post_state, post_exit),
    ):
        if exit_code == 0:
            if not isinstance(state_value, dict):
                fail(f"{label} must be a JSON object when readback succeeds")
            if state_value.get("state_strength") != "ROWSET_SHA256_WITH_KEY_MATERIAL_DIGEST":
                fail(f"{label} strength does not cover key material")
        elif state_value is not None:
            fail(f"{label} must be null when readback fails")

    rollback_status = full_lines[i_rollback].split("=", 1)[1]
    overall_status = full_lines[i_overall].split("=", 1)[1]

    t1_receipt = receipt.get("t1", {})
    t2_receipt = receipt.get("t2", {})
    if t1_exit != t1_receipt.get("exit_code"):
        fail("T1 exit code mismatch")
    if t2_exit != t2_receipt.get("exit_code"):
        fail("T2 exit code mismatch")
    if pre_exit != t2_receipt.get("pre_state_exit_code"):
        fail("pre-state exit mismatch")
    if post_exit != t2_receipt.get("post_state_exit_code"):
        fail("post-state exit mismatch")
    if state_match != t2_receipt.get("state_match"):
        fail("state_match mismatch")
    if state_match != (pre_state == post_state):
        fail("state_match disagrees with state payloads")
    if rollback_status != t2_receipt.get("rollback_status"):
        fail("rollback status mismatch")
    if overall_status != receipt.get("overall_status"):
        fail("overall status mismatch")

    explicit_count = sum(line == "ROLLBACK" for line in t2_lines)
    if explicit_count != t2_receipt.get("explicit_rollback_marker_count"):
        fail("explicit rollback marker count mismatch")
    if rollback_status == "EXPLICIT":
        if not (t2_exit == 0 and explicit_count == 1 and state_match):
            fail("EXPLICIT rollback semantics are not satisfied")
    elif rollback_status == "IMPLICIT_ON_DISCONNECT":
        if not (t2_exit != 0 and explicit_count == 0 and state_match):
            fail("IMPLICIT_ON_DISCONNECT semantics are not satisfied")
    elif rollback_status == "NOT_VERIFIED":
        if receipt.get("overall_status") == "PASS":
            fail("PASS cannot use NOT_VERIFIED rollback")
    else:
        fail("invalid rollback status")

    if receipt.get("overall_status") == "PASS":
        if receipt.get("t1", {}).get("status") != "PASS":
            fail("overall PASS requires T1 PASS")
        if receipt.get("t2", {}).get("status") != "PASS":
            fail("overall PASS requires T2 PASS")
        if rollback_status != "EXPLICIT":
            fail("overall PASS requires explicit rollback")


