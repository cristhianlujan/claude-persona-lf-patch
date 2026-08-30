#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CLI = Path(os.environ['LF_LLAMA_CLI_PATH']).resolve()
MODEL = Path(os.environ['LF_MODEL_PATH'])
MMPROJ = Path(os.environ['LF_MMPROJ_PATH'])
CONVERTER = (CLI.parents[2] / 'examples' / 'json_schema_to_grammar.py').resolve()

SCHEMA = {
    'type': 'object',
    'additionalProperties': False,
    'properties': {'x': {'type': 'string'}},
    'required': ['x'],
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def run() -> dict:
    if not CONVERTER.is_file():
        return {'pass': False, 'error': 'converter_missing', 'converter': str(CONVERTER)}
    with tempfile.TemporaryDirectory(prefix='c3-gbnf-smoke-', dir=ROOT) as td:
        d = Path(td)
        system = d / 'system.txt'
        schema = d / 'schema.json'
        grammar = d / 'schema.gbnf'
        output = d / 'output.txt'
        system.write_text('Return exactly one compact JSON object matching the supplied schema. No prose.', encoding='utf-8')
        schema.write_text(json.dumps(SCHEMA, separators=(',', ':')), encoding='utf-8')

        conversion = subprocess.run(
            [sys.executable, str(CONVERTER), str(schema)],
            cwd=ROOT, stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=120, check=False,
        )
        grammar_text = conversion.stdout.strip()
        if conversion.returncode != 0 or not grammar_text or 'root ::=' not in grammar_text:
            return {
                'pass': False,
                'error': 'conversion_failed',
                'conversion_returncode': conversion.returncode,
                'conversion_stderr_tail': conversion.stderr[-1600:].replace('\n', ' | '),
            }
        grammar.write_text(grammar_text + '\n', encoding='utf-8')

        command = [
            str(CLI), '-m', str(MODEL), '-mm', str(MMPROJ), '-sysf', str(system),
            '--prompt', 'Set x to ok.', '-st', '--simple-io', '--no-display-prompt',
            '--no-show-timings', '-co', 'off', '-c', '4096', '-n', '64',
            '-t', '4', '--temp', '0.0', '-s', '42', '-o', str(output),
            '--grammar-file', str(grammar),
        ]
        cp = subprocess.run(command, cwd=ROOT, stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=180, check=False)
        raw = output.read_text(encoding='utf-8') if output.exists() else ''
        cleaned = raw.rsplit('Assistant:', 1)[-1].strip() if 'Assistant:' in raw else raw.strip()
        parsed = None
        try:
            parsed = json.loads(cleaned)
        except Exception:
            pass
        passed = bool(cp.returncode == 0 and isinstance(parsed, dict) and isinstance(parsed.get('x'), str))
        return {
            'returncode': cp.returncode,
            'raw_repr': repr(raw),
            'cleaned_repr': repr(cleaned),
            'stderr_tail': cp.stderr[-2400:].replace('\n', ' | '),
            'converter_sha256': sha256_file(CONVERTER),
            'grammar_sha256': sha256_file(grammar),
            'transport': 'GBNF_PRECONVERTED',
            'pass': passed,
        }


def main() -> int:
    result = run()
    print('C3_GBNF_SMOKE=' + json.dumps(result, ensure_ascii=False, sort_keys=True))
    if result.get('pass'):
        print('C3_GBNF_SMOKE_VERDICT=GBNF_DIRECT_PASS')
        return 0
    print('C3_GBNF_SMOKE_VERDICT=GBNF_DIRECT_FAIL')
    return 2


if __name__ == '__main__':
    raise SystemExit(main())
