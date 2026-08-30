#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CLI = Path(os.environ['LF_LLAMA_CLI_PATH'])
MODEL = Path(os.environ['LF_MODEL_PATH'])
MMPROJ = Path(os.environ['LF_MMPROJ_PATH'])

SCHEMA = {
    'type': 'object',
    'additionalProperties': False,
    'properties': {'x': {'type': 'string'}},
    'required': ['x'],
}


def run(label: str, ignore_eos: bool) -> dict:
    with tempfile.TemporaryDirectory(prefix='c3-jf-smoke-', dir=ROOT) as td:
        d = Path(td)
        system = d / 'system.txt'
        schema = d / 'schema.json'
        output = d / 'output.txt'
        system.write_text('Return exactly one compact JSON object matching the supplied schema. No prose.', encoding='utf-8')
        schema.write_text(json.dumps(SCHEMA, separators=(',', ':')), encoding='utf-8')
        command = [
            str(CLI), '-m', str(MODEL), '-mm', str(MMPROJ), '-sysf', str(system),
            '--prompt', 'Set x to ok.', '-st', '--simple-io', '--no-display-prompt',
            '--no-show-timings', '-co', 'off', '-c', '4096', '-n', '64',
            '-t', '4', '--temp', '0.0', '-s', '42', '-o', str(output),
            '-jf', str(schema),
        ]
        if ignore_eos:
            command.append('--ignore-eos')
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
            'label': label,
            'returncode': cp.returncode,
            'raw_repr': repr(raw),
            'cleaned_repr': repr(cleaned),
            'stderr_tail': cp.stderr[-2400:].replace('\n', ' | '),
            'pass': passed,
        }


def main() -> int:
    baseline = run('jf_default', False)
    print('C3_JF_SMOKE=' + json.dumps(baseline, ensure_ascii=False, sort_keys=True))
    if baseline['pass']:
        print('C3_JF_SMOKE_VERDICT=JF_DEFAULT_PASS')
        return 0
    ignore = run('jf_ignore_eos', True)
    print('C3_JF_SMOKE=' + json.dumps(ignore, ensure_ascii=False, sort_keys=True))
    if ignore['pass']:
        print('C3_JF_SMOKE_VERDICT=JF_REQUIRES_IGNORE_EOS')
        return 3
    print('C3_JF_SMOKE_VERDICT=JF_RUNTIME_OR_SCHEMA_CONVERTER_FAIL')
    return 2


if __name__ == '__main__':
    raise SystemExit(main())
