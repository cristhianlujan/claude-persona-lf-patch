"""Pruebas locales del fixture leído: sin red/DB/Git y sin ejecutar scripts ajenos."""
import ast
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
from datetime import datetime, timezone

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "reports/forward_v2"
RAW = ROOT / "fixtures/forward_v2/raw"
CORRECT = ROOT / "fixtures/forward_v2/correct"

# El import de jsonschema no usa red: no hay $ref remoto en los schemas del fixture.
from jsonschema import Draft202012Validator


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def modules(folder, label):
    saved = {k: sys.modules.get(k) for k in ("producer", "consumer")}
    try:
        producer = load(label + "_producer", folder / "producer.py")
        consumer = load(label + "_consumer", folder / "consumer.py")
        sys.modules["producer"] = producer
        sys.modules["consumer"] = consumer
        pipeline = load(label + "_pipeline", folder / "pipeline.py")
        return producer, consumer, pipeline
    finally:
        for key, old in saved.items():
            if old is None:
                sys.modules.pop(key, None)
            else:
                sys.modules[key] = old


def observe(fn, *args, **kwargs):
    try:
        return {"kind": "RETURN", "value": fn(*args, **kwargs)}
    except Exception as exc:
        return {"kind": "RAISE", "exception": type(exc).__name__, "message": str(exc)}


def schema_observe(schema, payload):
    errors = sorted(Draft202012Validator(schema).iter_errors(payload), key=lambda e: (list(map(str, e.path)), e.message))
    return {
        "kind": "SCHEMA", "valid": not errors,
        "errors": [{"path": list(e.path), "validator": e.validator, "message": e.message} for e in errors],
    }


def main():
    raw = modules(RAW, "raw")
    correct = modules(CORRECT, "correct")
    schema_raw = json.loads((RAW / "input.schema.json").read_text())
    schema_correct = json.loads((CORRECT / "input.schema.json").read_text())
    for schema in (schema_raw, schema_correct):
        Draft202012Validator.check_schema(schema)
    cases = []

    def record(case_id, objective, actual, expected, scope="FIXTURE_ONLY"):
        ok = all(actual.get(k) == v for k, v in expected.items())
        cases.append({"id": case_id, "objective": objective, "observed": actual, "expected": expected, "assertion_pass": ok, "scope": scope})

    good = {"portfolio_key": "portfolio-A", "execution_id": "run-A", "currency": "PEN", "source_revision": "revision-1", "as_of": "revision-1"}
    ready = {"kind": "RETURN", "value": {"decision": "READY", "execution_id": "run-A"}}
    message = {k: v for k, v in good.items() if k != "as_of"}
    rp, rc, rr = raw
    cp, cc, cr = correct
    prepared_raw = rp.prepare(good["portfolio_key"], good["execution_id"], currency=good["currency"], source_revision=good["source_revision"])
    prepared_correct = cp.prepare(good["portfolio_key"], good["execution_id"], currency=good["currency"], source_revision=good["source_revision"])

    record("RAW_RUN_VALID", "Entrada nominal por run: primer fallo de binding", observe(rr.run, **good), {"kind": "RAISE", "exception": "TypeError", "message": "assess() missing 1 required keyword-only argument: 'as_of'"})
    record("RAW_PREPARE_LOSS", "Readback del mensaje producido", {"kind": "RETURN", "value": prepared_raw}, {"kind": "RETURN", "value": {"portfolio_key": "portfolio-A", "execution_id": "run-A"}})
    record("RAW_AFTER_BINDING_ONLY", "Probar defecto latente tras entregar as_of", observe(rc.assess, prepared_raw, as_of=good["as_of"]), {"kind": "RAISE", "exception": "KeyError", "message": "'currency'"})
    record("RAW_AFTER_CURRENCY_ONLY", "Descubrir segunda clave perdida sin confundir causa", observe(rc.assess, dict(prepared_raw, currency="PEN"), as_of="revision-1"), {"kind": "RAISE", "exception": "KeyError", "message": "'source_revision'"})
    record("RAW_DIRECT_CONSUMER_PEN", "Positivo del consumidor sin pipeline", observe(rc.assess, message, as_of="revision-1"), ready)
    record("RAW_DIRECT_CONSUMER_USD", "Segunda moneda admitida", observe(rc.assess, dict(message, currency="USD"), as_of="revision-1"), ready)
    record("RAW_UNSUPPORTED", "Negativo del emisor READY: moneda inválida", observe(rc.assess, dict(message, currency="EUR"), as_of="revision-1"), {"kind": "RAISE", "exception": "ValueError", "message": "CURRENCY_UNSUPPORTED"})
    record("RAW_STALE", "Negativo del emisor READY: revisión distinta", observe(rc.assess, dict(message, source_revision="revision-0"), as_of="revision-1"), {"kind": "RAISE", "exception": "ValueError", "message": "SOURCE_REVISION_STALE"})
    record("RAW_ERROR_PRECEDENCE", "Ambos defectos: comprobar primer rechazo", observe(rc.assess, dict(message, currency="EUR", source_revision="revision-0"), as_of="revision-1"), {"kind": "RAISE", "exception": "ValueError", "message": "CURRENCY_UNSUPPORTED"})
    minimal = {"portfolio_key": "portfolio-A", "execution_id": "run-A"}
    record("RAW_SCHEMA_MINIMAL", "Schema actual admite entrada incompleta para run", schema_observe(schema_raw, minimal), {"kind": "SCHEMA", "valid": True})
    record("RAW_MINIMAL_TO_RUN", "Misma entrada admitida: run no puede ejecutarse", observe(rr.run, **minimal), {"kind": "RAISE", "exception": "TypeError", "message": "run() missing 3 required keyword-only arguments: 'currency', 'source_revision', and 'as_of'"})
    record("RAW_SCHEMA_UNSUPPORTED", "Enum de consumidor no está declarado", schema_observe(schema_raw, dict(good, currency="EUR")), {"kind": "SCHEMA", "valid": True})

    record("CORRECT_RUN_PEN", "Positivo del pipeline corregido", observe(cr.run, **good), ready)
    record("CORRECT_RUN_USD", "Regresión del segundo valor admitido", observe(cr.run, **dict(good, currency="USD")), ready)
    record("CORRECT_PREPARE_READBACK", "Readback de cuatro campos preservados", {"kind": "RETURN", "value": prepared_correct}, {"kind": "RETURN", "value": message})
    record("CORRECT_UNSUPPORTED", "Negativo moneda por pipeline completo local", observe(cr.run, **dict(good, currency="EUR")), {"kind": "RAISE", "exception": "ValueError", "message": "CURRENCY_UNSUPPORTED"})
    record("CORRECT_STALE", "Negativo revisión por pipeline completo local", observe(cr.run, **dict(good, source_revision="revision-0")), {"kind": "RAISE", "exception": "ValueError", "message": "SOURCE_REVISION_STALE"})
    record("CORRECT_ERROR_PRECEDENCE", "Regresión de prioridad del error", observe(cr.run, **dict(good, currency="EUR", source_revision="revision-0")), {"kind": "RAISE", "exception": "ValueError", "message": "CURRENCY_UNSUPPORTED"})
    record("CORRECT_EXECUTION_ID", "Otro ID regresa sin reescritura", observe(cr.run, **dict(good, execution_id="run-B")), {"kind": "RETURN", "value": {"decision": "READY", "execution_id": "run-B"}})
    for key in ("currency", "source_revision", "execution_id"):
        broken = {k: v for k, v in message.items() if k != key}
        record("CORRECT_MISSING_" + key.upper(), "Clave ausente no debe emitir READY", observe(cc.assess, broken, as_of="revision-1"), {"kind": "RAISE", "exception": "KeyError", "message": repr(key)})
    record("CORRECT_SCHEMA_NOMINAL", "Schema propuesto admite nominal", schema_observe(schema_correct, good), {"kind": "SCHEMA", "valid": True})
    for key in ("currency", "source_revision", "as_of"):
        record("CORRECT_SCHEMA_MISSING_" + key.upper(), "Required propuesto rechaza falta de " + key, schema_observe(schema_correct, {k: v for k, v in good.items() if k != key}), {"kind": "SCHEMA", "valid": False})
    record("CORRECT_SCHEMA_UNSUPPORTED", "Enum propuesto rechaza EUR", schema_observe(schema_correct, dict(good, currency="EUR")), {"kind": "SCHEMA", "valid": False})
    record("CORRECT_SCHEMA_STALE", "Límite: JSON Schema no comprueba igualdad entre tokens", schema_observe(schema_correct, dict(good, source_revision="revision-0")), {"kind": "SCHEMA", "valid": True})
    record("CORRECT_NULL_REVISION_BOUNDARY", "Límite observado: sin política de tipo, null==null emite READY", observe(cr.run, **dict(good, source_revision=None, as_of=None)), ready)
    record("CORRECT_WRONG_AS_OF_BOUNDARY", "Límite: caller puede igualar dos tokens ajenos; no prueba currentness", observe(cr.run, **dict(good, source_revision="untrusted-revision", as_of="untrusted-revision")), ready)
    record("CORRECT_SCHEMA_EXTRA_BOUNDARY", "Extensibilidad heredada del schema", schema_observe(schema_correct, dict(good, extra="x")), {"kind": "SCHEMA", "valid": True})
    record("CORRECT_RUN_EXTRA_BOUNDARY", "Sin loader no hay proyección de campos extra a firma", observe(cr.run, **dict(good, extra="x")), {"kind": "RAISE", "exception": "TypeError", "message": "run() got an unexpected keyword argument 'extra'"})

    sources = {}
    for label, folder in (("raw", RAW), ("correct", CORRECT)):
        for path in sorted(folder.iterdir()):
            if path.is_file():
                sources[str(path.relative_to(ROOT))] = {"sha256": sha(path), "bytes": path.stat().st_size}
    # La enumeración AST solo documenta el alcance conocido y no llama funciones descubiertas.
    ast_inventory = []
    for path in sorted(RAW.glob("*.py")):
        tree = ast.parse(path.read_text())
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef):
                ast_inventory.append({"file": str(path.relative_to(ROOT)), "function": node.name, "line": node.lineno, "end_line": node.end_lineno, "parameters": [a.arg for a in node.args.args], "keyword_only": [a.arg for a in node.args.kwonlyargs]})

    result = {
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "command": "python -B reports/forward_v2/reproduce.py",
        "working_directory": str(ROOT),
        "source_revision": None, "source_state": "FIXTURE_COMMIT_NOT_RESOLVED",
        "runtime": {"python": sys.version, "jsonschema_draft": "2020-12"},
        "execution_scope": "FIXTURE_ONLY", "new_lf_e2e_executed": False,
        "cases": cases,
        "summary": {"total": len(cases), "assertions_passed": sum(c["assertion_pass"] for c in cases), "assertions_failed": sum(not c["assertion_pass"] for c in cases)},
        "source_hashes": sources,
        "ast_inventory": ast_inventory,
        "harness_sha256": sha(Path(__file__)),
        "limits": ["No red/DB/Git/PR/CI ni ejecución LF", "READY local no prueba autoridad, independencia, despliegue ni E2E", "Tipos y procedencia de tokens no resueltos", "Schema no está integrado en ningún loader descubierto", "Positivos del harness incluyen errores esperados; assertion_pass no significa flujo válido"]
    }
    target = OUT / "reproduction.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result["summary"], ensure_ascii=False))
    for c in cases:
        print(c["id"], "ASSERT_OK" if c["assertion_pass"] else "ASSERT_FAIL", json.dumps(c["observed"], ensure_ascii=False))
    return int(any(not c["assertion_pass"] for c in cases))


if __name__ == "__main__":
    raise SystemExit(main())
