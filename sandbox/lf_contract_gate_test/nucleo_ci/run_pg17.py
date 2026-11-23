#!/usr/bin/env python3
"""Run the actual LF/SALY migrations and 17 autopruebas in a disposable PG17 container."""
import argparse
import pathlib
import re
import subprocess
import time
import uuid
import f4_conformance

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
    if f4_conformance.needed(ROOT, base, head, paths):
        relevant.append(f4_conformance.MANIFEST)
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
        if any("_lf_nucleo_dpig03_contrato_lectura_v1.sql" in p.name for p in replay):
            dpig03_fixture = HERE / "dpig03_legacy_oracle_pg17.sql"
            if not dpig03_fixture.is_file():
                raise RuntimeError("DPIG03_ORACLE_FIXTURE_MISSING")
            psql(name, dpig03_fixture.read_text())
        replayed_names = [p.name for p in replay]
        for path in replay:
            print(f"NUCLEO_CI_REPLAY {path.name}", flush=True)
            if "_lf_nucleo_piloto_publicacion_2_v1.sql" in path.name:
                # Preserve original DP-IG-03 legacy-only cases on their original
                # screen before publication; after replay run them on unaffected 43.
                base_test = psql(name, (HERE / "dpig03_lectura_pg17.sql").read_text(), check=False)
                print(base_test.stdout + base_test.stderr, flush=True)
                if base_test.returncode or base_test.stderr.count("DPIG03_TEST_PASS ") != 14 or "DPIG03_ROLLBACK_PASS 14/14" not in base_test.stderr:
                    raise RuntimeError("PILOT_PRE_PUBLICATION_DPIG03_FAILED")
                # Exact migration under outer rollback before replaying its commit.
                snapshot = """SELECT jsonb_build_object(
                  'legacy',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.reglas r),
                  'core',(SELECT jsonb_agg(to_jsonb(n) ORDER BY codigo) FROM lf_ops.nucleo_reglas n),
                  'versions',(SELECT jsonb_agg(to_jsonb(v) ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones v),
                  'eval',(SELECT jsonb_agg(to_jsonb(e) ORDER BY id) FROM lf_ops.nucleo_evaluaciones e),
                  'history',(SELECT jsonb_agg(to_jsonb(d) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones d));"""
                prior = psql(name, snapshot).stdout
                source = path.read_text().rstrip()
                if not source.endswith("\nCOMMIT;") or source.count("\nCOMMIT;") != 1:
                    raise RuntimeError("PILOT_TRANSACTION_BOUNDARY")
                trial = psql(name, source[:-len("COMMIT;")] + "ROLLBACK;\n", check=False)
                print(trial.stdout + trial.stderr, flush=True)
                if (trial.returncode or trial.stderr.count("PILOT_PASS ") != 10
                        or trial.stderr.count("PILOT_PUBLISHED ") != 2
                        or trial.stderr.count("PILOT_DEPRECATED_TEST ") != 2
                        or psql(name, snapshot).stdout != prior):
                    raise RuntimeError("PILOT_OUTER_ROLLBACK_FAILED")
                print("PILOT_OUTER_ROLLBACK_PASS exact baseline, 10/10", flush=True)
            if "_lf_nucleo_m1_candidatas_v1.sql" in path.name:
                psql(name, (HERE / "m1_source_fixture_pg17.sql").read_text())
                snapshot = """SELECT jsonb_build_object(
                  'legacy',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.v_reglas_compat_v1 r),
                  'core',(SELECT jsonb_agg(to_jsonb(n) ORDER BY codigo) FROM lf_ops.nucleo_reglas n),
                  'versions',(SELECT jsonb_agg(to_jsonb(v) ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones v),
                  'facts',(SELECT jsonb_agg(to_jsonb(h) ORDER BY codigo) FROM lf_ops.nucleo_hechos h),
                  'vocab',(SELECT jsonb_agg(to_jsonb(v) ORDER BY familia,hecho) FROM lf_ops.nucleo_familia_vocabulario v),
                  'eval',(SELECT jsonb_agg(to_jsonb(e) ORDER BY id) FROM lf_ops.nucleo_evaluaciones e));"""
                prior = psql(name, snapshot).stdout
                source = path.read_text().rstrip()
                if not source.endswith("\nCOMMIT;") or source.count("\nCOMMIT;") != 1:
                    raise RuntimeError("M1_TRANSACTION_BOUNDARY")
                trial = psql(name, source[:-len("COMMIT;")] + "ROLLBACK;\n", check=False)
                print(trial.stdout + trial.stderr, flush=True)
                if trial.returncode or trial.stderr.count("M1_PROPOSE ") != 6 or trial.stderr.count("M1_EVALUATE ") != 6 or "M1_NEGATIVE_FIXED_COMMISSION" not in trial.stderr or "M1_PASS 6/6" not in trial.stderr or psql(name, snapshot).stdout != prior:
                    raise RuntimeError("M1_OUTER_ROLLBACK_FAILED")
                print("M1_OUTER_ROLLBACK_PASS exact baseline", flush=True)
            if "_lf_nucleo_m1_juicios_v1.sql" in path.name:
                snapshot = """SELECT jsonb_build_object(
                    'legacy',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.reglas r),
                    'core',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_reglas r),
                    'versions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones r),
                    'apps',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,nodo) FROM lf_ops.nucleo_aplicaciones r),
                    'juicios',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_juicios r),
                    'eval',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_evaluaciones r),
                    'deprec',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones r));"""
                prior = psql(name, snapshot).stdout
                source = path.read_text().rstrip()
                if not source.endswith("\nCOMMIT;") or source.count("\nCOMMIT;") != 1:
                    raise RuntimeError("M1_JUDGE_TRANSACTION_BOUNDARY")
                trial = psql(name, source[:-len("COMMIT;")] + "ROLLBACK;\n", check=False)
                print(trial.stdout + trial.stderr, flush=True)
                if (trial.returncode or trial.stderr.count("M1_JUDGE_RESULT ") != 6
                        or trial.stderr.count("M1_JUDGE_PASS ") != 1
                        or psql(name, snapshot).stdout != prior):
                    raise RuntimeError("M1_JUDGE_OUTER_ROLLBACK_FAILED")
                print("M1_JUDGE_OUTER_ROLLBACK_PASS exact baseline, six honest DEVOLVER", flush=True)
            if "_lf_saly_procesos_ekb_hallazgos_v1.sql" in path.name:
                # Fixture EKB solo para esta migracion, sin red ni datos productivos.
                psql(name, (HERE / "saly_ekb_hallazgos_fixture_pg17.sql").read_text())
                candidate = path.read_text()
                h1 = "SALY-PROCESOS-PANTALLA-CANAL-PENDIENTE-20261123-001"
                h2 = "SALY-PROCESOS-MODULO-NODOS-AUSENTES-20261123-001"
                query = ("SELECT count(*)||'|'||min(frecuencia)||'|'||max(frecuencia) "
                         "FROM transversal.error_knowledge WHERE codigo IN ('" + h1 + "','" + h2 + "');")
                # Positivo: ambas altas; ROLLBACK real elimina ambas.
                trial = psql(name, "BEGIN;\n" + candidate + "\n" + query + "\nROLLBACK;\n", check=False)
                if trial.returncode or "2|1|1" not in trial.stdout.splitlines() or "SALY_EKB_HALLAZGOS_2_2_PASS" not in trial.stderr:
                    raise RuntimeError("SALY_EKB_PG17_INSERT_OR_ROLLBACK_FAILED " + trial.stderr)
                if psql(name, "SELECT count(*) FROM transversal.error_knowledge;").stdout.strip() != "0":
                    raise RuntimeError("SALY_EKB_PG17_FIRST_ROLLBACK_RESIDUE")
                # Recurrencia exacta: H1 preexistente aumenta 2->3; H2 entra nueva.
                seed = ("INSERT INTO transversal.error_knowledge"
                        "(codigo,categoria,titulo,frecuencia,estado) VALUES ('" + h1 + "',"
                        "'QA','QA existente',2,'ACTIVO');\n")
                again = psql(name, "BEGIN;\n" + seed + candidate + "\n" +
                             "SELECT frecuencia FROM transversal.error_knowledge WHERE codigo='" + h1 + "';\n" +
                             "SELECT frecuencia FROM transversal.error_knowledge WHERE codigo='" + h2 + "';\n" +
                             "ROLLBACK;\n", check=False)
                if again.returncode or again.stdout.splitlines().count("3") != 1 or again.stdout.splitlines().count("1") != 1:
                    raise RuntimeError("SALY_EKB_PG17_RECURRENCE_FAILED " + again.stderr)
                if psql(name, "SELECT count(*) FROM transversal.error_knowledge;").stdout.strip() != "0":
                    raise RuntimeError("SALY_EKB_PG17_SECOND_ROLLBACK_RESIDUE")
                print("SALY_EKB_PG17_INSERT_RECURRENCE_ROLLBACK_PASS 2/2", flush=True)
            if "_lf_nucleo_m1_c03_revision_v2.sql" in path.name:
                snapshot = """SELECT jsonb_build_object(
                    'legacy',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.reglas r),
                    'core',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_reglas r),
                    'versions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones r),
                    'facts',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_hechos r),
                    'vocab',(SELECT jsonb_agg(to_jsonb(r) ORDER BY familia,hecho) FROM lf_ops.nucleo_familia_vocabulario r),
                    'tests',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version,n) FROM lf_ops.nucleo_regla_pruebas r),
                    'judges',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_juicios r),
                    'eval',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_evaluaciones r),
                    'deprec',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones r),
                    'ekb',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM public.lf_error_knowledge r));"""
                prior = psql(name, snapshot).stdout
                source = path.read_text().rstrip()
                if not source.endswith("\nCOMMIT;") or source.count("\nCOMMIT;") != 1:
                    raise RuntimeError("M1_C03_TRANSACTION_BOUNDARY")
                trial = psql(name, source[:-len("COMMIT;")] + "ROLLBACK;\n", check=False)
                print(trial.stdout + trial.stderr, flush=True)
                if (trial.returncode or "M1_C03_TESTS_PASS 7/7" not in trial.stderr
                        or "M1_C03_STALE_REPLAY_REJECTED" not in trial.stderr
                        or "M1_C03_V2_PASS" not in trial.stderr
                        or psql(name, snapshot).stdout != prior):
                    raise RuntimeError("M1_C03_ROLLBACK_OR_NEGATIVE_FAILED")
                print("M1_C03_OUTER_ROLLBACK_PASS exact baseline", flush=True)
            if "_lf_nucleo_m1_5_revisiones_v2.sql" in path.name:
                snapshot = """SELECT jsonb_build_object(
                    'legacy',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.reglas r),
                    'core',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_reglas r),
                    'versions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones r),
                    'facts',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_hechos r),
                    'vocab',(SELECT jsonb_agg(to_jsonb(r) ORDER BY familia,hecho) FROM lf_ops.nucleo_familia_vocabulario r),
                    'tests',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version,n) FROM lf_ops.nucleo_regla_pruebas r),
                    'judges',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_juicios r),
                    'eval',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_evaluaciones r),
                    'apps',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,nodo) FROM lf_ops.nucleo_aplicaciones r),
                    'deprec',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones r),
                    'ekb',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM public.lf_error_knowledge r));"""
                before = psql(name, snapshot).stdout
                source = path.read_text().rstrip()
                if not source.endswith("\nCOMMIT;") or source.count("\nCOMMIT;") != 1:
                    raise RuntimeError("M1_FIVE_TRANSACTION_BOUNDARY")
                trial = psql(name, source[:-len("COMMIT;")] + "ROLLBACK;\n", check=False)
                print(trial.stdout + trial.stderr, flush=True)
                if (trial.returncode or trial.stderr.count("M1_FIVE_CASES ") != 5
                        or trial.stderr.count("M1_FIVE_V2_RESULT ") != 5
                        or "M1_FIVE_V2_PASS 5/5" not in trial.stderr
                        or psql(name, snapshot).stdout != before):
                    raise RuntimeError("M1_FIVE_ROLLBACK_OR_TEST_FAILED")
                print("M1_FIVE_OUTER_ROLLBACK_PASS exact baseline", flush=True)
            if "_lf_nucleo_m2_offers_candidatas_v1.sql" in path.name:
                fixture_sql = (HERE / "m2_53_fixture_pg17.sql").read_text()
                seeded = psql(name, fixture_sql)
                if "M2_PG17_SOURCE_FIXTURE 53" not in seeded.stderr:
                    raise RuntimeError("M2_PG17_SOURCE_FIXTURE_FAIL")
                print("M2_PG17_SOURCE_SEEDED 53 synthetic-only", flush=True)
                snapshot = """SELECT jsonb_build_object(
                    'legacy',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.reglas r),
                    'core',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_reglas r),
                    'versions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones r),
                    'facts',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_hechos r),
                    'vocab',(SELECT jsonb_agg(to_jsonb(r) ORDER BY familia,hecho) FROM lf_ops.nucleo_familia_vocabulario r),
                    'tests',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version,n) FROM lf_ops.nucleo_regla_pruebas r),
                    'judges',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_juicios r),
                    'eval',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_evaluaciones r),
                    'apps',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,nodo) FROM lf_ops.nucleo_aplicaciones r),
                    'deprec',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones r),
                    'ekb',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM public.lf_error_knowledge r));"""
                before = psql(name, snapshot).stdout
                source = path.read_text().rstrip()
                if not source.endswith("\nCOMMIT;") or source.count("\nCOMMIT;") != 1:
                    raise RuntimeError("M2_TRANSACTION_BOUNDARY")
                trial = psql(name, source[:-len("COMMIT;")] + "ROLLBACK;\n", check=False)
                print(trial.stdout + trial.stderr, flush=True)
                if (trial.returncode or trial.stderr.count("M2_CASES ") != 6
                        or trial.stderr.count("M2_CANDIDATE ") != 6
                        or "M2_PASS 6/6 candidate-only" not in trial.stderr
                        or psql(name, snapshot).stdout != before):
                    raise RuntimeError("M2_ROLLBACK_OR_NEGATIVE_FAILED")
                print("M2_OUTER_ROLLBACK_PASS exact baseline", flush=True)
            if "_lf_nucleo_m3_financial_candidatas_v1.sql" in path.name:
                seed = psql(name, (HERE / "m3_16_fixture_pg17.sql").read_text())
                if "M3_PG17_SOURCE_FIXTURE 16" not in seed.stderr:
                    raise RuntimeError("M3_PG17_SOURCE_FIXTURE_FAILED")
                print("M3_PG17_SOURCE_SEEDED 16 synthetic-only", flush=True)
                snapshot = """SELECT jsonb_build_object(
                    'legacy',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.reglas r),
                    'core',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_reglas r),
                    'versions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones r),
                    'facts',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_hechos r),
                    'vocab',(SELECT jsonb_agg(to_jsonb(r) ORDER BY familia,hecho) FROM lf_ops.nucleo_familia_vocabulario r),
                    'tests',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version,n) FROM lf_ops.nucleo_regla_pruebas r),
                    'judges',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_juicios r),
                    'eval',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_evaluaciones r),
                    'apps',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,nodo) FROM lf_ops.nucleo_aplicaciones r),
                    'deprec',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones r),
                    'ekb',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM public.lf_error_knowledge r));"""
                before = psql(name, snapshot).stdout
                source = path.read_text().rstrip()
                if not source.endswith("\nCOMMIT;") or source.count("\nCOMMIT;") != 1:
                    raise RuntimeError("M3_TRANSACTION_BOUNDARY")
                trial = psql(name, source[:-len("COMMIT;")] + "ROLLBACK;\n", check=False)
                print(trial.stdout + trial.stderr, flush=True)
                if (trial.returncode or trial.stderr.count("M3_CASES ") != 5
                        or trial.stderr.count("M3_CANDIDATE ") != 5
                        or "M3_PASS 5/5 candidate-only" not in trial.stderr
                        or psql(name, snapshot).stdout != before):
                    raise RuntimeError("M3_ROLLBACK_OR_NEGATIVE_FAILED")
                print("M3_OUTER_ROLLBACK_PASS exact baseline", flush=True)
            if "_lf_nucleo_m4_security_candidatas_v1.sql" in path.name:
                seeded = psql(name, (HERE / "m4_112_fixture_pg17.sql").read_text())
                if "M4_PG17_SOURCE_FIXTURE 112" not in seeded.stderr:
                    raise RuntimeError("M4_SOURCE_FIXTURE_FAILED")
                print("M4_PG17_SOURCE_SEEDED 112 synthetic-only", flush=True)
                snapshot = """SELECT jsonb_build_object(
                    'legacy',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.reglas r),
                    'core',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_reglas r),
                    'versions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones r),
                    'facts',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_hechos r),
                    'vocab',(SELECT jsonb_agg(to_jsonb(r) ORDER BY familia,hecho) FROM lf_ops.nucleo_familia_vocabulario r),
                    'tests',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version,n) FROM lf_ops.nucleo_regla_pruebas r),
                    'judges',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_juicios r),
                    'eval',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_evaluaciones r),
                    'apps',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,nodo) FROM lf_ops.nucleo_aplicaciones r),
                    'deprec',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones r),
                    'ekb',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM public.lf_error_knowledge r));"""
                before = psql(name, snapshot).stdout
                source = path.read_text().rstrip()
                if not source.endswith("\nCOMMIT;") or source.count("\nCOMMIT;") != 1:
                    raise RuntimeError("M4_TRANSACTION_BOUNDARY")
                trial = psql(name, source[:-len("COMMIT;")] + "ROLLBACK;\n", check=False)
                print(trial.stdout + trial.stderr, flush=True)
                if (trial.returncode or trial.stderr.count("M4_CASES ") != 8
                        or trial.stderr.count("M4_CANDIDATE ") != 8
                        or "M4_PASS 8/8 candidate-only" not in trial.stderr
                        or psql(name, snapshot).stdout != before):
                    raise RuntimeError("M4_ROLLBACK_OR_NEGATIVE_FAILED")
                print("M4_OUTER_ROLLBACK_PASS exact baseline", flush=True)
            if "_lf_nucleo_m4b_otp_session_rate_candidatas_v1.sql" in path.name:
                snapshot = """SELECT jsonb_build_object(
                    'legacy',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.reglas r),
                    'core',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_reglas r),
                    'versions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones r),
                    'facts',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_hechos r),
                    'vocab',(SELECT jsonb_agg(to_jsonb(r) ORDER BY familia,hecho) FROM lf_ops.nucleo_familia_vocabulario r),
                    'tests',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version,n) FROM lf_ops.nucleo_regla_pruebas r),
                    'eval',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_evaluaciones r),
                    'deprec',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones r),
                    'ekb',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM public.lf_error_knowledge r));"""
                before = psql(name, snapshot).stdout
                source = path.read_text().rstrip()
                if not source.endswith("\nCOMMIT;") or source.count("\nCOMMIT;") != 1:
                    raise RuntimeError("M4B_TRANSACTION_BOUNDARY")
                trial = psql(name, source[:-len("COMMIT;")] + "ROLLBACK;\n", check=False)
                print(trial.stdout + trial.stderr, flush=True)
                if trial.returncode or trial.stderr.count("M4B_CASES ") != 8 or trial.stderr.count("M4B_CANDIDATE ") != 8 or "M4B_PASS 8/8 candidate-only" not in trial.stderr or psql(name, snapshot).stdout != before:
                    raise RuntimeError("M4B_ROLLBACK_OR_CASES_FAILED")
                print("M4B_OUTER_ROLLBACK_PASS exact baseline", flush=True)
            if "_lf_nucleo_m2_lote2_siete_grupos_candidatas_v1.sql" in path.name:
                snapshot = """SELECT jsonb_build_object(
                    'legacy',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.reglas r),
                    'core',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_reglas r),
                    'versions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones r),
                    'facts',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_hechos r),
                    'vocab',(SELECT jsonb_agg(to_jsonb(r) ORDER BY familia,hecho) FROM lf_ops.nucleo_familia_vocabulario r),
                    'tests',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version,n) FROM lf_ops.nucleo_regla_pruebas r),
                    'eval',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_evaluaciones r),
                    'deprec',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones r),
                    'ekb',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM public.lf_error_knowledge r));"""
                before = psql(name, snapshot).stdout
                source = path.read_text().rstrip()
                if not source.endswith("\nCOMMIT;") or source.count("\nCOMMIT;") != 1:
                    raise RuntimeError("M2L2_TRANSACTION_BOUNDARY")
                trial = psql(name, source[:-len("COMMIT;")] + "ROLLBACK;\n", check=False)
                print(trial.stdout + trial.stderr, flush=True)
                if trial.returncode or trial.stderr.count("M2L2_CASES ") != 7 or trial.stderr.count("M2L2_CANDIDATE ") != 7 or "M2L2_PASS 7/7 candidate-only" not in trial.stderr or psql(name, snapshot).stdout != before:
                    raise RuntimeError("M2L2_ROLLBACK_OR_CASES_FAILED")
                print("M2L2_OUTER_ROLLBACK_PASS exact baseline", flush=True)
            if "_lf_nucleo_m4c_b2b_auth_candidatas_v1.sql" in path.name:
                snapshot = """SELECT jsonb_build_object(
                    'legacy',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.reglas r),
                    'core',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_reglas r),
                    'versions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones r),
                    'facts',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_hechos r),
                    'vocab',(SELECT jsonb_agg(to_jsonb(r) ORDER BY familia,hecho) FROM lf_ops.nucleo_familia_vocabulario r),
                    'tests',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version,n) FROM lf_ops.nucleo_regla_pruebas r),
                    'eval',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_evaluaciones r),
                    'deprec',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones r),
                    'ekb',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM public.lf_error_knowledge r));"""
                before = psql(name, snapshot).stdout
                source = path.read_text().rstrip()
                if not source.endswith("\nCOMMIT;") or source.count("\nCOMMIT;") != 1:
                    raise RuntimeError("M4C_TRANSACTION_BOUNDARY")
                trial = psql(name, source[:-len("COMMIT;")] + "ROLLBACK;\n", check=False)
                print(trial.stdout + trial.stderr, flush=True)
                if trial.returncode or trial.stderr.count("M4C_CASES ") != 8 or trial.stderr.count("M4C_CANDIDATE ") != 8 or "M4C_PASS 8/8 candidate-only" not in trial.stderr or psql(name, snapshot).stdout != before:
                    raise RuntimeError("M4C_ROLLBACK_OR_CASES_FAILED")
                print("M4C_OUTER_ROLLBACK_PASS exact baseline", flush=True)
            if "_lf_nucleo_piloto_cinco_juicios_publicacion_v1.sql" in path.name:
                snapshot = """SELECT jsonb_build_object(
                    'legacy',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.reglas r),
                    'core',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_reglas r),
                    'versions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones r),
                    'judges',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_juicios r),
                    'evaluations',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_evaluaciones r),
                    'deprec',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones r),
                    'ekb',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM public.lf_error_knowledge r));"""
                before = psql(name, snapshot).stdout
                source = path.read_text().rstrip()
                if not source.endswith("\nCOMMIT;") or source.count("\nCOMMIT;") != 1:
                    raise RuntimeError("PILOT_TRANSACTION_BOUNDARY")
                trial = psql(name, source[:-len("COMMIT;")] + "ROLLBACK;\n", check=False)
                print(trial.stdout + trial.stderr, flush=True)
                if trial.returncode or trial.stderr.count("PILOT_RESULT ") != 5 or "PILOT_PASS 5/5 judged" not in trial.stderr or psql(name, snapshot).stdout != before:
                    raise RuntimeError("PILOT_ROLLBACK_OR_RESULTS_FAILED")
                print("PILOT_OUTER_ROLLBACK_PASS exact baseline", flush=True)
            if "_lf_nucleo_tanda1_diez_juicios_publicacion_v1.sql" in path.name:
                snapshot = """SELECT jsonb_build_object(
                    'legacy',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.reglas r),
                    'core',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM lf_ops.nucleo_reglas r),
                    'versions',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_regla_versiones r),
                    'judges',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_juicios r),
                    'evaluations',(SELECT jsonb_agg(to_jsonb(r) ORDER BY id) FROM lf_ops.nucleo_evaluaciones r),
                    'deprec',(SELECT jsonb_agg(to_jsonb(r) ORDER BY regla,version) FROM lf_ops.nucleo_deprecaciones r),
                    'ekb',(SELECT jsonb_agg(to_jsonb(r) ORDER BY codigo) FROM public.lf_error_knowledge r));"""
                before = psql(name, snapshot).stdout
                source = path.read_text().rstrip()
                if not source.endswith("\nCOMMIT;") or source.count("\nCOMMIT;") != 1:
                    raise RuntimeError("TANDA1_TRANSACTION_BOUNDARY")
                trial = psql(name, source[:-len("COMMIT;")] + "ROLLBACK;\n", check=False)
                print(trial.stdout + trial.stderr, flush=True)
                if trial.returncode or trial.stderr.count("TANDA1_RESULT ") != 10 or "TANDA1_PASS 10/10 judged" not in trial.stderr or psql(name, snapshot).stdout != before:
                    raise RuntimeError("TANDA1_ROLLBACK_OR_RESULTS_FAILED")
                print("TANDA1_OUTER_ROLLBACK_PASS exact baseline", flush=True)
            replay = psql(name, path.read_text())
            if "_lf_nucleo_tanda1_diez_juicios_publicacion_v1.sql" in path.name:
                print(replay.stdout + replay.stderr, flush=True)
                if replay.stderr.count("TANDA1_RESULT ") != 10 or "TANDA1_PASS 10/10 judged" not in replay.stderr:
                    raise RuntimeError("TANDA1_REPLAY_FAILED")

            if "_lf_nucleo_piloto_cinco_juicios_publicacion_v1.sql" in path.name:
                print(replay.stdout + replay.stderr, flush=True)
                if replay.stderr.count("PILOT_RESULT ") != 5 or "PILOT_PASS 5/5 judged" not in replay.stderr:
                    raise RuntimeError("PILOT_REPLAY_FAILED")

            if "_lf_nucleo_m4c_b2b_auth_candidatas_v1.sql" in path.name:
                print(replay.stdout + replay.stderr, flush=True)
                if replay.stderr.count("M4C_CASES ") != 8 or replay.stderr.count("M4C_CANDIDATE ") != 8 or "M4C_PASS 8/8 candidate-only" not in replay.stderr:
                    raise RuntimeError("M4C_REPLAY_FAILED")

            if "_lf_nucleo_m2_lote2_siete_grupos_candidatas_v1.sql" in path.name:
                print(replay.stdout + replay.stderr, flush=True)
                if replay.stderr.count("M2L2_CASES ") != 7 or replay.stderr.count("M2L2_CANDIDATE ") != 7 or "M2L2_PASS 7/7 candidate-only" not in replay.stderr:
                    raise RuntimeError("M2L2_REPLAY_FAILED")

            if "_lf_nucleo_m4b_otp_session_rate_candidatas_v1.sql" in path.name:
                print(replay.stdout + replay.stderr, flush=True)
                if replay.stderr.count("M4B_CASES ") != 8 or replay.stderr.count("M4B_CANDIDATE ") != 8 or "M4B_PASS 8/8 candidate-only" not in replay.stderr:
                    raise RuntimeError("M4B_REPLAY_FAILED")

            if "_lf_nucleo_m4_security_candidatas_v1.sql" in path.name:
                print(replay.stdout + replay.stderr, flush=True)
                if (replay.stderr.count("M4_CASES ") != 8
                        or replay.stderr.count("M4_CANDIDATE ") != 8
                        or "M4_PASS 8/8 candidate-only" not in replay.stderr):
                    raise RuntimeError("M4_REPLAY_FAILED")
            if "_lf_nucleo_m3_financial_candidatas_v1.sql" in path.name:
                print(replay.stdout + replay.stderr, flush=True)
                if (replay.stderr.count("M3_CASES ") != 5
                        or replay.stderr.count("M3_CANDIDATE ") != 5
                        or "M3_PASS 5/5 candidate-only" not in replay.stderr):
                    raise RuntimeError("M3_REPLAY_FAILED")
            if "_lf_nucleo_m2_offers_candidatas_v1.sql" in path.name:
                print(replay.stdout + replay.stderr, flush=True)
                if (replay.stderr.count("M2_CASES ") != 6
                        or replay.stderr.count("M2_CANDIDATE ") != 6
                        or "M2_PASS 6/6 candidate-only" not in replay.stderr):
                    raise RuntimeError("M2_REPLAY_NOT_EVIDENCED")
            if "_lf_nucleo_m1_5_revisiones_v2.sql" in path.name:
                print(replay.stdout + replay.stderr, flush=True)
                if (replay.stderr.count("M1_FIVE_CASES ") != 5
                        or replay.stderr.count("M1_FIVE_V2_RESULT ") != 5
                        or "M1_FIVE_V2_PASS 5/5" not in replay.stderr):
                    raise RuntimeError("M1_FIVE_REPLAY_FAILED")
            if "_lf_nucleo_m1_c03_revision_v2.sql" in path.name:
                print(replay.stdout + replay.stderr, flush=True)
                if ("M1_C03_TESTS_PASS 7/7" not in replay.stderr
                        or "M1_C03_STALE_REPLAY_REJECTED" not in replay.stderr
                        or "M1_C03_V2_PASS" not in replay.stderr):
                    raise RuntimeError("M1_C03_REPLAY_MISSING_PASS")
            if "_lf_nucleo_m1_juicios_v1.sql" in path.name:
                print(replay.stdout + replay.stderr, flush=True)
                if replay.stderr.count("M1_JUDGE_RESULT ") != 6 or replay.stderr.count("M1_JUDGE_PASS ") != 1:
                    raise RuntimeError("M1_JUDGE_REPLAY_FAILED")
            if "_lf_nucleo_m1_candidatas_v1.sql" in path.name:
                print(replay.stdout + replay.stderr, flush=True)
                if "M1_PASS 6/6" not in replay.stderr:
                    raise RuntimeError("M1_REPLAY_FAILED")
            if "_lf_nucleo_piloto_publicacion_2_v1.sql" in path.name:
                print(replay.stdout + replay.stderr, flush=True)
                if replay.stderr.count("PILOT_PASS ") != 10 or replay.stderr.count("PILOT_PUBLISHED ") != 2:
                    raise RuntimeError("PILOT_REPLAY_EVIDENCE_MISSING")

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
        if any("_lf_nucleo_f4_tipos_constantes_v1.sql" in n for n in replayed_names):
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
        if any("_lf_nucleo_dpig03_contrato_lectura_v1.sql" in n for n in replayed_names):
            dpig03_test = HERE / "dpig03_lectura_pg17.sql"
            if not dpig03_test.is_file():
                raise RuntimeError("DPIG03_TEST_MISSING")
            dpig03_sql = dpig03_test.read_text()
            if any("_lf_nucleo_piloto_publicacion_2_v1.sql" in n for n in replayed_names):
                # The published checkout rules now resolve on screen 59; preserve
                # legacy-only oracle on real node 43 outside CLIENT_PAYMENTS.
                # Original exact screen-59 suite already ran before pilot.
                dpig03_sql = re.sub(r"(?<![0-9])59(?![0-9])", "43", dpig03_sql)
            dpig03 = psql(name, dpig03_sql, check=False)
            print(dpig03.stdout + dpig03.stderr, flush=True)
            if (dpig03.returncode or dpig03.stderr.count("DPIG03_TEST_PASS ") != 14
                    or "DPIG03_ROLLBACK_PASS 14/14" not in dpig03.stderr):
                raise RuntimeError("DPIG03_TEST_OR_ROLLBACK_FAILED")
        f4_conformance.run(name, ROOT, args.base, args.head, psql)
        if any("_lf_nucleo_deprecacion_gobernada_v1.sql" in n for n in replayed_names):
            dep_fixture = (HERE / "deprecacion_pg17.sql").read_text()
            for schema in ("lf_ops", "saly"):
                dep = psql(name, "BEGIN;\n" + dep_fixture.replace("@SCHEMA@", schema) + "\nROLLBACK;", check=False)
                print(dep.stdout + dep.stderr, flush=True)
                if dep.returncode or dep.stderr.count("DEP_PASS " + schema + " ") != 10:
                    raise RuntimeError("DEP_TEST_FAILED " + schema)
                for table in ("nucleo_reglas", "nucleo_deprecaciones"):
                    field = "codigo" if table == "nucleo_reglas" else "regla"
                    residue = psql(name, f"SELECT count(*) FROM {schema}.{table} WHERE {field}='ZZT-DEPRECACION';").stdout.strip()
                    if residue != "0":
                        raise RuntimeError("DEP_ROLLBACK_FAILED " + schema + "." + table)
                print("DEP_ROLLBACK_PASS " + schema + " 10/10", flush=True)
        if any(n.startswith("sandbox/lf_contract_gate_test/nucleo_ci/procesos_saly/") for n in relevant):
            # Candidato Procesos SALY: PG17 aislado, base saly_test_*, TCP 127.0.0.1 dentro del contenedor.
            psql(name, "CREATE DATABASE saly_test_procesos;")
            run_cmd(["docker", "cp", str(HERE / "procesos_saly"), name + ":/tmp/procesos_saly"])
            for sql_name, marks in (("pruebas_evolucion_v2.sql", ("QA_453: PASS", "Rollback: PASS")),
                                    ("pruebas_adicionales.sql", ("PROCESOS_EXTRA_PASS", "EXTRA_ROLLBACK_PASS"))):
                res = run_cmd(["docker", "exec", "-w", "/tmp/procesos_saly", name, "psql", "-X", "-h", "127.0.0.1",
                               "-U", "postgres", "-d", "saly_test_procesos", "-v", "ON_ERROR_STOP=1", "-f", sql_name], check=False)
                print(res.stdout + res.stderr, flush=True)
                if res.returncode or any(m not in res.stderr for m in marks):
                    raise RuntimeError("PROCESOS_SALY_TEST_FAILED " + sql_name)
            if psql(name, "SELECT to_regclass('saly.procesos') IS NULL;").stdout.strip() != "t":
                raise RuntimeError("PROCESOS_SALY_ROLLBACK_RESIDUE")
            psql(name, "CREATE DATABASE saly_test_conc;")
            conc = run_cmd(["docker", "exec", "-w", "/tmp/procesos_saly", name, "bash", "concurrencia_pg17.sh"], check=False)
            print(conc.stdout + conc.stderr, flush=True)
            if conc.returncode or "PROCESOS_CONC_PASS" not in conc.stdout:
                raise RuntimeError("PROCESOS_SALY_CONCURRENCY_FAILED")
            print("PROCESOS_SALY_PG17_PASS", flush=True)
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
