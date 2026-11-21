#!/usr/bin/env python3
"""Run the actual LF/SALY migrations and 17 autopruebas in a disposable PG17 container."""
import argparse
import pathlib
import re
import subprocess
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent
MIG = ROOT / "supabase" / "migrations"
CORE_NAME = re.compile(r"^\d{14}_lf_nucleo_.+\.sql$")
CORE_TEXT = re.compile(r"\b(?:nucleo_\w+|lf_nucleo_\w+|lf_puente2?_autotest_v1)\b", re.I)
TESTS = {
    f"{schema}.nucleo_autotest_{name}_v1": expected
    for schema in ("lf_ops", "saly")
    for name, expected in (
        ("puerta", "PUERTA 26/26"),
        ("evaluacion", "EVALUACION 23/23"),
        ("cambio", "CAMBIO 16/16"),
        ("contrato", "CONTRATO 4/4 (12 casos)"),
        ("calculo", "CALCULO 36/36"),
        ("profundidad", "PROFUNDIDAD 13/13"),
        ("alcance_inverso", "ALCANCE_INVERSO 10/10"),
    )
}
TESTS.update({
    "public.lf_nucleo_autotest_conjunto_v1": "CONJUNTO 5/5",
    "lf_ops.lf_puente_autotest_v1": "PUENTE 8/8",
    "lf_ops.lf_puente2_autotest_v1": "PUENTE2 6/6",
})
FIRST = "20261120215000_lf_nucleo_familias_v1.sql"

def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True)

def changed_core(base, head):
    if not base or not head or set(base) == {"0"}:
        raise RuntimeError("NUCLEO_CI_MISSING_BASE_OR_HEAD")
    paths = git("diff", "--name-only", base, head).splitlines()
    relevant = []
    for path in paths:
        if path == ".github/workflows/pase.yml" or path.startswith(str(HERE.relative_to(ROOT)) + "/"):
            relevant.append(path)
        elif path.startswith("supabase/migrations/") and path.endswith(".sql"):
            diff = git("diff", "--unified=0", base, head, "--", path)
            # Include changed code even if a migration has a nonstandard name.
            if CORE_NAME.fullmatch(pathlib.Path(path).name) or CORE_TEXT.search(diff):
                relevant.append(path)
    return relevant

def run_cmd(args, *, data=None, check=True):
    return subprocess.run(args, input=data, text=True, capture_output=True, check=check, timeout=180)

def psql(container, data, *, check=True):
    return run_cmd(["docker", "exec", "-i", container, "psql", "-X", "-U", "postgres", "-d", "postgres",
                    "-v", "ON_ERROR_STOP=1", "-At"], data=data, check=check)

def sql_literal(value):
    return "'" + value.replace("'", "''") + "'"

def suite_sql(mutate=False):
    out = ["BEGIN;", "DO $parity$\nBEGIN\n IF EXISTS(SELECT * FROM lf_ops.reglas EXCEPT ALL SELECT * FROM lf_ops.v_reglas_compat_v1 WHERE id IS NOT NULL) OR\n    EXISTS(SELECT * FROM lf_ops.v_reglas_compat_v1 WHERE id IS NOT NULL EXCEPT ALL SELECT * FROM lf_ops.reglas)\n THEN RAISE EXCEPTION 'AM_COEX_LEGACY_PARITY_FAILED'; END IF;\n IF EXISTS(SELECT codigo FROM lf_ops.v_reglas_compat_v1 GROUP BY codigo HAVING count(*)>1)\n THEN RAISE EXCEPTION 'AM_COEX_DUPLICATE_CODE'; END IF;\n RAISE NOTICE 'AM_COEX_LEGACY_PARITY_OK';\nEND $parity$;\n"]
    if mutate:
        # Deliberate real DB mutation of a single test, rolled back when the session exits.
        out.append("CREATE OR REPLACE FUNCTION lf_ops.nucleo_autotest_puerta_v1() RETURNS text LANGUAGE sql AS $$ SELECT 'PUERTA 0/26'::text $$;")
    out.append("DO $gate$ DECLARE got text; BEGIN")
    for f, expected in TESTS.items():
        out.extend([f"got := {f}();", f"IF got IS DISTINCT FROM {sql_literal(expected)} THEN",
                    f"RAISE EXCEPTION 'NUCLEO_CI_BAD_VERDICT {f}: %', got; END IF;",
                    f"RAISE NOTICE 'NUCLEO_CI_OK {f}: %', got;"])
    out.extend(["END $gate$;", "ROLLBACK;"])
    return "\n".join(out) + "\n"

def replay_paths(relevant):
    paths = {p.name: p for p in MIG.glob("*.sql") if CORE_NAME.fullmatch(p.name)}
    # This EKB transition updates an existing finding. Replay its real source
    # migration and resolution in order so the isolated catalog is reproducible.
    am_ekb = re.compile(r"^\d{14}_lf_ekb_nucleo_am_(?:checkout_coexistencia_20261121_v1|coexistencia_revision_v1|revision_resuelta_20261121_v1)\.sql$")
    paths.update({p.name: p for p in MIG.glob("*.sql") if am_ekb.fullmatch(p.name)})
    if FIRST not in paths:
        raise RuntimeError("NUCLEO_CI_MISSING_FIRST_MIGRATION")
    for name in relevant:
        if name.startswith("supabase/migrations/"):
            path = ROOT / name
            if not path.is_file():
                raise RuntimeError(f"NUCLEO_CI_REMOVED_MIGRATION {name}")
            paths[path.name] = path
    return [paths[name] for name in sorted(paths)]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--head", required=True)
    ap.add_argument("--force-fail", action="store_true")
    args = ap.parse_args()
    if git("rev-parse", "HEAD").strip() != args.head:
        raise RuntimeError("NUCLEO_CI_HEAD_MISMATCH")
    relevant = changed_core(args.base, args.head)
    if not relevant and not args.force_fail:
        print("NUCLEO_CI_NOT_APPLICABLE")
        return
    print("NUCLEO_CI_APPLICABLE " + ",".join(relevant), flush=True)
    name = "lf-nucleo-ci-" + uuid.uuid4().hex
    try:
        # No host port, no external network, no production URL or credentials.
        run_cmd(["docker", "run", "-d", "--network", "none", "--name", name,
                 "-e", "POSTGRES_HOST_AUTH_METHOD=trust", "postgres:17"])
        for _ in range(60):
            ready = run_cmd(["docker", "exec", name, "pg_isready", "-U", "postgres"], check=False)
            if ready.returncode == 0:
                break
            time.sleep(1)
        else:
            raise RuntimeError("NUCLEO_CI_PG17_NOT_READY")
        version = psql(name, "SHOW server_version_num;").stdout.strip()
        if not version.isdigit() or not 170000 <= int(version) < 180000:
            raise RuntimeError("NUCLEO_CI_NOT_PG17 " + version)
        print("NUCLEO_CI_PG17 " + version, flush=True)
        fixture = HERE / "base_pg17.sql"
        if not fixture.is_file():
            raise RuntimeError("NUCLEO_CI_BASE_MISSING")
        psql(name, fixture.read_text())
        # SALY legadas existen en producción pero no en la dependencia sintética base.
        # Sólo PG17 aislado: reproducir las 14 fuentes antes de las migraciones gobernadas.
        replay = replay_paths(relevant)
        if any("_lf_nucleo_saly_14_candidatas_v1.sql" in p.name for p in replay):
            saly_fixture = HERE / "saly_am_14_fixture_pg17.sql"
            if not saly_fixture.is_file():
                raise RuntimeError("SALY_AM14_PG17_SOURCE_FIXTURE_MISSING")
            psql(name, saly_fixture.read_text())
            print("SALY_AM14_PG17_SOURCE_SEEDED 14/14", flush=True)
        if any("_lf_nucleo_f0_vocab36_enums_v1.sql" in p.name for p in replay):
            f0_fixture = HERE / "f0_vocab36_fixture_pg17.sql"
            if not f0_fixture.is_file():
                raise RuntimeError("F0_VOCAB36_PG17_FIXTURE_MISSING")
            psql(name, f0_fixture.read_text())
            print("F0_VOCAB36_PG17_SCHEMA_SEEDED", flush=True)
        for path in replay:
            print(f"NUCLEO_CI_REPLAY {path.name}", flush=True)
            replay = psql(name, path.read_text())
            if "_lf_nucleo_am_checkout_piloto_v1.sql" in path.name:
                lines = [line for line in replay.stderr.splitlines()
                         if "AM_CHECKOUT_RESULT " in line or "AM_CHECKOUT_NEGATIVE_" in line or "AM_CHECKOUT_PASS " in line]
                if sum("AM_CHECKOUT_RESULT " in line for line in lines) != 10 or sum("AM_CHECKOUT_NEGATIVE_HASH " in line for line in lines) != 10 or sum("AM_CHECKOUT_NEGATIVE_PUBLICATION " in line for line in lines) != 9 or sum("AM_CHECKOUT_PASS " in line for line in lines) != 1:
                    raise RuntimeError("AM_CHECKOUT_INCOMPLETE_REPLAY_EVIDENCE")
                print("\n".join(lines), flush=True)
            if "_lf_nucleo_am_checkout_revisiones_v2.sql" in path.name:
                lines = [line for line in replay.stderr.splitlines()
                         if "AM_V2_RESULT " in line or "AM_V2_PASS " in line]
                if sum("AM_V2_RESULT " in line for line in lines) != 8 or sum("AM_V2_PASS " in line for line in lines) != 1:
                    raise RuntimeError("AM_V2_INCOMPLETE_REPLAY_EVIDENCE")
                print("\n".join(lines), flush=True)
            if "_lf_nucleo_am_checkout_revisiones_v3.sql" in path.name:
                lines = [line for line in replay.stderr.splitlines()
                         if "AM_V3_RESULT " in line or "AM_V3_PASS " in line]
                if sum("AM_V3_RESULT " in line for line in lines) != 6 or sum("AM_V3_PASS " in line for line in lines) != 1:
                    raise RuntimeError("AM_V3_INCOMPLETE_REPLAY_EVIDENCE")
                print("\n".join(lines), flush=True)
            if "_lf_nucleo_f0_vocab36_enums_v1.sql" in path.name:
                lines = [line for line in replay.stderr.splitlines() if "F0_VOCAB_PASS " in line]
                if len(lines) != 1 or "36/36 familias" not in lines[0] or "25 CHECK, 94 valores" not in lines[0]:
                    raise RuntimeError("F0_VOCAB36_INCOMPLETE_REPLAY_EVIDENCE")
                print(lines[0], flush=True)
            if "_lf_nucleo_saly_14_candidatas_v1.sql" in path.name:
                lines = [line for line in replay.stderr.splitlines()
                         if "SALY_AM14_RESULT " in line or "SALY_AM14_PASS " in line]
                if sum("SALY_AM14_RESULT " in line for line in lines) != 14 or sum("SALY_AM14_PASS " in line for line in lines) != 1:
                    raise RuntimeError("SALY_AM14_INCOMPLETE_REPLAY_EVIDENCE")
                print("\n".join(lines), flush=True)
        # F4: verify committed TS against the real PostgreSQL-17 catalog; mutate a
        # family in the disposable DB under BEGIN/ROLLBACK and require drift detection.
        if any("_lf_nucleo_f4_tipos_constantes_v1.sql" in p.name for p in replay):
            codegen = HERE / "f4_codegen.py"
            generated = ROOT / "sdk" / "lf_nucleo_catalog.generated.ts"
            if not codegen.is_file() or not generated.is_file():
                raise RuntimeError("F4_CODEGEN_SOURCE_MISSING")
            cmd = ["python3", str(codegen), "--verify", str(generated)]
            raw_catalog = psql(name, "SELECT lf_ops.f4_tipos_catalogo_v1();").stdout
            positive = run_cmd(cmd, data=raw_catalog, check=False)
            if positive.returncode != 0 or "F4_CODEGEN_PASS families=64 enum_groups=25 enum_values=94" not in positive.stdout:
                raise RuntimeError("F4_CODEGEN_PRODUCTION_SOURCE_MISMATCH " + positive.stderr)
            print(positive.stdout.strip(), flush=True)
            mutation = psql(name, """BEGIN;
              INSERT INTO lf_ops.nucleo_familias
                (codigo,dominio,origen,descripcion,estado,min_pruebas,tipo)
              VALUES ('F4_MUTANTE_PG17','CALIDAD','NUEVA',
                      'Familia de mutación descartable para la prueba de tipado F4',
                      'EN_FORMACION',2,'TECNICA');
              SELECT lf_ops.f4_tipos_catalogo_v1();
              ROLLBACK;""")
            docs = [line for line in mutation.stdout.splitlines() if line.strip().startswith("{")]
            if len(docs) != 1:
                raise RuntimeError("F4_CODEGEN_MUTATION_PAYLOAD_MISSING")
            rejected = run_cmd(cmd, data=docs[0], check=False)
            if rejected.returncode == 0 or "F4_CODEGEN_DRIFT" not in rejected.stderr:
                raise RuntimeError("F4_CODEGEN_MUTANT_WAS_ACCEPTED")
            print("F4_CODEGEN_MUTATION_REJECTED", flush=True)
            if psql(name, "SELECT COUNT(*) FROM lf_ops.nucleo_familias WHERE codigo='F4_MUTANTE_PG17';").stdout.strip() != "0":
                raise RuntimeError("F4_CODEGEN_MUTATION_ROLLBACK_FAILED")
            again = run_cmd(cmd, data=psql(name, "SELECT lf_ops.f4_tipos_catalogo_v1();").stdout, check=False)
            if again.returncode != 0:
                raise RuntimeError("F4_CODEGEN_AFTER_ROLLBACK_FAILED " + again.stderr)
            print("F4_CODEGEN_AFTER_ROLLBACK_PASS", flush=True)
        if len(TESTS) != 17:
            raise RuntimeError("NUCLEO_CI_TEST_INVENTORY_DRIFT")
        result = psql(name, suite_sql(args.force_fail), check=False)
        print(result.stdout + result.stderr, flush=True)
        if result.returncode:
            raise RuntimeError("NUCLEO_CI_AUTOTESTS_FAILED")
        if result.stderr.count("NUCLEO_CI_OK ") != len(TESTS) or "AM_COEX_LEGACY_PARITY_OK" not in result.stderr:
            raise RuntimeError("NUCLEO_CI_INCOMPLETE_EVIDENCE")
        # Use precisely the same SQL gate; its failure must be caused by the injected verdict.
        negative = psql(name, suite_sql(True), check=False)
        if negative.returncode == 0 or "NUCLEO_CI_BAD_VERDICT lf_ops.nucleo_autotest_puerta_v1: PUERTA 0/26" not in negative.stderr:
            raise RuntimeError("NUCLEO_CI_NEGATIVE_NOT_DETECTED")
        print("NUCLEO_CI_NEGATIVE_DETECTED exit=" + str(negative.returncode), flush=True)
        restored = psql(name, suite_sql(), check=False)
        if restored.returncode or restored.stderr.count("NUCLEO_CI_OK ") != len(TESTS):
            raise RuntimeError("NUCLEO_CI_ROLLBACK_OR_RETEST_FAILED")
        print("NUCLEO_CI_PASS 17/17; negative detected; 17/17 after rollback", flush=True)
    except subprocess.CalledProcessError as err:
        print(err.stdout or "", err.stderr or "", flush=True)
        raise
    finally:
        run_cmd(["docker", "rm", "-f", name], check=False)

if __name__ == "__main__":
    main()
