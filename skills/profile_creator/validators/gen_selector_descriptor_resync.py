#!/usr/bin/env python3
"""Genera la migracion de resync del descriptor del selector de un perfil.

Uso (cierre del actualizador, si el catalogo queda STALE_SOURCE_CHANGED):
  gen_selector_descriptor_resync.py --profile-code PERFIL-X --skill-md profiles/<slug>/SKILL.md \
     --descriptor-json descriptor.json --source-commit <40hex en main que contiene ese SKILL.md> \
     --out supabase/migrations/<14digitos>_lf_selector_descriptor_resync_<slug>_v1.sql

Verifica de forma determinista que cada texto de evidencia del descriptor sea literal en el SKILL.md
(si no, sale con codigo 3 y lista los textos que faltan: hay que reescribir el descriptor desde el
SKILL.md actual). Calcula el blob sha del SKILL.md (formato git). No toca base de datos: solo escribe
el archivo de migracion, que entra por PR + ready-to-merge (Merge Train).
"""
import argparse, hashlib, json, re, sys
from pathlib import Path


def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def evidence_texts(desc: dict):
    out = [("description", desc.get("description"))]
    for i, ev in enumerate(desc.get("selection_evidence") or []):
        v = ev.get("value")
        if isinstance(v, list):
            for j, item in enumerate(v):
                out.append((f"selection_evidence[{i}].value[{j}]", item))
        else:
            out.append((f"selection_evidence[{i}].value", v))
    return out


def verify(desc: dict, skill_text: str):
    missing = []
    for where, text in evidence_texts(desc):
        if not isinstance(text, str) or not text or text not in skill_text:
            missing.append(where)
    return missing


def sql_quote(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def render(profile_code, desc, source_ref, blob_sha, tag):
    dj = json.dumps(desc, ensure_ascii=False, sort_keys=False)
    return f"""-- lf_selector_descriptor_resync ({profile_code})
-- Generada por gen_selector_descriptor_resync.py: cada texto de evidencia del descriptor es literal en el
-- SKILL.md de {source_ref} (blob {blob_sha}). Sin cambios de runtime, SKILL ni contrato.
DO $resync$
DECLARE
  n integer;
  v jsonb;
BEGIN
  SELECT count(*) INTO n FROM public.lf_profile_selection_registry_v1 WHERE profile_code={sql_quote(profile_code)} AND descriptor_status='STALE_SOURCE_CHANGED';
  IF n <> 1 THEN RAISE EXCEPTION 'SELECTOR_RESYNC_PRESTATE_DRIFT:{profile_code}:%', n; END IF;
  SELECT count(*) INTO n FROM public.lf_activos WHERE codigo_activo={sql_quote(profile_code)} AND tipo_activo='PERFIL' AND archived_at IS NULL AND raw_payload->>'skill_sha'={sql_quote(blob_sha)} AND metadata->>'entrypoint_sha'={sql_quote(blob_sha)};
  IF n <> 1 THEN RAISE EXCEPTION 'SELECTOR_RESYNC_SOURCE_SHA_MISMATCH:{profile_code}:%', n; END IF;
  v := public.lf_profile_selector_descriptor_sync_v1(
    {sql_quote(profile_code)},
    {sql_quote(dj)}::jsonb,
    'GITHUB_SKILL',
    {sql_quote(source_ref)},
    {sql_quote(blob_sha)},
    {sql_quote(tag)});
  IF v->>'outcome' <> 'SYNCED' THEN RAISE EXCEPTION 'SELECTOR_RESYNC_FAILED:%', v; END IF;

  v := public.lf_profile_selector_catalog_v1();
  IF coalesce((v->>'all_canonical_descriptors_complete')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'SELECTOR_RESYNC_CATALOG_STILL_INCOMPLETE:%', left(v::text,500);
  END IF;
END
$resync$;
"""


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile-code", required=True)
    ap.add_argument("--skill-md", required=True)
    ap.add_argument("--descriptor-json", required=True)
    ap.add_argument("--source-commit", required=True)
    ap.add_argument("--repo", default="cristhianlujan/claude-persona-lf-patch")
    ap.add_argument("--tag", default="SELECTOR-DESCRIPTOR-RESYNC")
    ap.add_argument("--out", required=True)
    a = ap.parse_args(argv)
    if not re.fullmatch(r"PERFIL-[A-Z0-9][A-Z0-9-]{2,100}", a.profile_code):
        print("PROFILE_CODE_INVALID", file=sys.stderr); return 2
    if not re.fullmatch(r"[0-9a-f]{40}", a.source_commit):
        print("SOURCE_COMMIT_INVALID", file=sys.stderr); return 2
    skill = Path(a.skill_md)
    data = skill.read_bytes()
    desc = json.loads(Path(a.descriptor_json).read_text(encoding="utf-8"))
    if desc.get("schema_version") != "LF_PROFILE_SELECTION_DESCRIPTOR_V1":
        print("DESCRIPTOR_SCHEMA_INVALID", file=sys.stderr); return 2
    missing = verify(desc, data.decode("utf-8"))
    if missing:
        print(json.dumps({"status": "EVIDENCE_NOT_LITERAL_IN_SKILL", "missing": missing,
                          "how": "reescribir el descriptor con textos copiados del SKILL.md actual"}, ensure_ascii=False))
        return 3
    blob = git_blob_sha(data)
    m = re.search(r"profiles/([A-Za-z0-9_.-]+)/SKILL\.md$", str(skill).replace("\\", "/"))
    if not m:
        print("SKILL_PATH_NOT_UNDER_PROFILES", file=sys.stderr); return 2
    ref = f"github://{a.repo}@{a.source_commit}/profiles/{m.group(1)}/SKILL.md"
    Path(a.out).write_text(render(a.profile_code, desc, ref, blob, a.tag), encoding="utf-8")
    print(json.dumps({"status": "GENERATED", "out": a.out, "blob_sha": blob, "source_ref": ref}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
