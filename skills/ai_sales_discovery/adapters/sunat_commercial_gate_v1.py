"""Fail-closed SALY SUNAT commercial admission; no writes or network requests.

Business policy supplies min_workers (approved initial value: 50).
Raw joined company data is unchanged, and the historical manifest is NOT modified.
A new commercial manifest must be built/approved from the filtered batches
before any governed writer receives their exact bytes.
"""

def commercially_admissible(record, *, min_workers):
    if type(min_workers) is not int or min_workers < 1:
        raise ValueError("SUNAT_COMMERCIAL_POLICY_REQUIRED")
    if not isinstance(record, dict) or not isinstance(record.get("capture"), dict):
        return False
    c = record["capture"]
    if c.get("version") != "sunat.company.v1" or c.get("source") != "SUNAT":
        return False
    try:
        n = c["normalized"]["workers_integer_literal"]
        m = c["observations"]["monthly"]["raw"]
        d = c["observations"]["reduced"]["raw"]
        if type(n) is not int or n < min_workers:
            return False
        # No assumptions that both official snapshots agree: all four facts must pass.
        return all(
            isinstance(value, str) and value.strip().upper() == expected
            for value, expected in (
                (m["Estado"], "ACTIVO"),
                (d["estado"], "ACTIVO"),
                (m["Condicion"], "HABIDO"),
                (d["condicion"], "HABIDO"),
            )
        )
    except (KeyError, TypeError):
        return False
