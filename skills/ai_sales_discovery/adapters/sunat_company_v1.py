"""Versioned projection for an unambiguous pair of SUNAT observations."""
import hashlib
import json
import re
import unicodedata
from urllib.parse import urlsplit

MONTHLY_FIELDS = (
    "RUC", "Estado", "Condicion", "Tipo", "UBIGEO", "Departamento", "Provincia",
    "Distrito", "PERIODO_PUBLICACION", "NroTrab",
    "Actividad_Economica_CIIU_revision3_Principal",
    "Actividad_Economica_CIIU_revision3_Secundaria",
    "Actividad_Economica_CIIU_revision4_Principal",
)
REDUCED_FIELDS = ("RUC", "nombre", "estado", "condicion", "ubigeo")


def require(condition, code):
    if not condition:
        raise ValueError(code)


def digest(value):
    encoded = json.dumps(value, sort_keys=True, ensure_ascii=False,
                         separators=(",", ":"), allow_nan=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def observation(row, fields, evidence):
    require(isinstance(row, dict) and all(isinstance(row.get(k), str) for k in fields),
            "SOURCE_FIELDS")
    require(isinstance(evidence, dict) and
            set(evidence) == {"url", "zip_sha256", "header_sha256", "ordinal"}, "EVIDENCE_FIELDS")
    require(type(evidence["ordinal"]) is int and evidence["ordinal"] > 0, "SOURCE_ORDINAL")
    require(all(isinstance(evidence[k], str) and re.fullmatch("[0-9a-f]{64}", evidence[k])
                for k in ("zip_sha256", "header_sha256")), "SOURCE_DIGEST")
    require(isinstance(evidence["url"], str) and urlsplit(evidence["url"]).scheme == "https"
            and urlsplit(evidence["url"]).hostname, "SOURCE_URL")
    return {"raw": {k: row[k] for k in fields}, "evidence": dict(evidence)}


def normalized_label(value):
    folded = unicodedata.normalize("NFKD", value.casefold())
    return " ".join("".join(c for c in folded if not unicodedata.combining(c)).split())


def company(monthly, reduced, monthly_evidence, reduced_evidence):
    sources = {"monthly": observation(monthly, MONTHLY_FIELDS, monthly_evidence),
               "reduced": observation(reduced, REDUCED_FIELDS, reduced_evidence)}
    ruc = monthly["RUC"].strip()
    require(re.fullmatch("[0-9]{11}", ruc) and ruc == reduced["RUC"].strip(), "JOIN_RUC")
    name = reduced["nombre"].strip()
    require(name, "MISSING_NAME")
    literal = monthly["NroTrab"].strip()
    workers = int(literal) if re.fullmatch("[0-9]{1,9}", literal) else None
    differences = {r: normalized_label(monthly[m]) != normalized_label(reduced[r])
                   for m, r in (("Estado", "estado"), ("Condicion", "condicion"), ("UBIGEO", "ubigeo"))}
    capture = {"version": "sunat.company.v1", "source": "SUNAT", "observations": sources,
               "normalized": {"ruc": ruc, "razon_social": name, "workers_integer_literal": workers},
               "derived": {"discrepancies": differences, "identity": "CANDIDATE",
                           "quality": "REVIEW" if any(differences.values()) or workers is None else "MATCHED"}}
    return {"capture": capture, "capture_sha256": digest(capture)}


def batches(records, max_rows, max_bytes):
    """Bound serialized payloads. A caller commits only after both archive CRCs pass."""
    require(all(type(n) is int and n > 0 for n in (max_rows, max_bytes)), "BATCH_LIMIT")
    rows, size = [], 2
    for record in records:
        require(isinstance(record, dict) and isinstance(record.get("capture"), dict)
                and digest(record["capture"]) == record.get("capture_sha256"), "CAPTURE_HASH")
        encoded = json.dumps(record, ensure_ascii=False, sort_keys=True,
                             separators=(",", ":")).encode("utf-8")
        require(len(encoded) + 2 <= max_bytes, "ROW_EXCEEDS_BATCH")
        if rows and (len(rows) == max_rows or size + 1 + len(encoded) > max_bytes):
            yield b"[" + b",".join(rows) + b"]"
            rows, size = [], 2
        size += int(bool(rows)) + len(encoded)
        rows.append(encoded)
    if rows:
        yield b"[" + b",".join(rows) + b"]"
