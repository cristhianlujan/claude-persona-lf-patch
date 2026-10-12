# DEV_ARTIFACT_TRANSPORT_NO_ZIP_V1

Status: TEMPORARY_ACTIVE_RULE
Intended final home: development policy or development card (pending placement decision)
Scope: development, governance, CI diagnostics, agent handoffs, evidence readback and operational troubleshooting.

## Rule

Compressed archive bundles such as `.zip`, `.tar`, `.tar.gz` and equivalent formats MUST NOT be used as the normal transport, canonical evidence, handoff format, or readback dependency when the same information can be exposed as directly addressable files, logs, JSON, text, database rows, or repository artifacts.

The default is direct access to the exact underlying artifact. A workflow or agent MUST prefer, in this order:

1. directly readable repository file or exact path;
2. directly readable CI log / structured diagnostic;
3. directly queryable database evidence / receipt;
4. individually addressable artifact files;
5. archive only when the external platform provides no non-archive access path.

## Archive exception

An archive is allowed only when all of the following are true:

- the producing platform exposes no practical direct-file alternative;
- using the archive is necessary to continue the task;
- the archive is immediately unpacked once, and subsequent work uses the extracted individual files;
- the archive itself is never treated as the canonical evidence object;
- no downstream gate, agent, reviewer, handoff or replay is required to repeatedly download or reopen the archive;
- the extracted files preserve exact provenance back to the originating run/artifact.

## Fail-closed behavior

If a workflow requires repeated archive download/extraction for routine verification, the workflow design is considered non-compliant and must be changed to publish directly readable evidence before it is treated as operationally closed.

A ZIP-only handoff MUST NOT be accepted as sufficient readback when a direct structured or file-level representation can be materialized.

## Rationale

Archive-only evidence increases latency and failure surface for agents and reviewers, makes selective readback slower, encourages repeated materialization, and obscures exact file-level provenance. Development evidence should therefore remain directly addressable and incrementally readable.

## Non-goal

This temporary rule does not redesign the current Work Protocol, G12, migration governance, CI architecture, or development-card taxonomy. It exists only to establish the no-ZIP operating constraint now, pending relocation into the final development policy/card authority.
