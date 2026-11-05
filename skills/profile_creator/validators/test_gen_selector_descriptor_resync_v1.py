import json, subprocess, sys, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GEN = ROOT / "skills/profile_creator/validators/gen_selector_descriptor_resync.py"
DESC = {"schema_version": "LF_PROFILE_SELECTION_DESCRIPTOR_V1", "description": "Hace X con rigor.",
        "selection_evidence": [{"kind": "PURPOSE", "source_section": "Purpose", "value": "Hace X con rigor."}]}


def run(tmp, skill_text, desc):
    d = Path(tmp) / "profiles" / "demo_profile"; d.mkdir(parents=True)
    (d / "SKILL.md").write_text(skill_text, encoding="utf-8")
    dj = Path(tmp) / "d.json"; dj.write_text(json.dumps(desc), encoding="utf-8")
    out = Path(tmp) / "m.sql"
    p = subprocess.run([sys.executable, "-B", str(GEN), "--profile-code", "PERFIL-DEMO-LF", "--skill-md", str(d / "SKILL.md"),
                        "--descriptor-json", str(dj), "--source-commit", "a" * 40, "--out", str(out)], capture_output=True, text=True)
    return p, out


class T(unittest.TestCase):
    def test_literal_generates_with_git_blob_sha(self):
        with tempfile.TemporaryDirectory() as t:
            p, out = run(t, "# Demo\nHace X con rigor.\n", DESC)
            self.assertEqual(p.returncode, 0, p.stderr)
            sql = out.read_text()
            import hashlib
            data = b"# Demo\nHace X con rigor.\n"
            self.assertIn(hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest(), sql)
            self.assertIn("PRESTATE_DRIFT", sql); self.assertIn("github://cristhianlujan/claude-persona-lf-patch@" + "a" * 40, sql)

    def test_non_literal_blocks(self):
        with tempfile.TemporaryDirectory() as t:
            p, out = run(t, "# Demo\nOtro texto.\n", DESC)
            self.assertEqual(p.returncode, 3)
            self.assertIn("EVIDENCE_NOT_LITERAL_IN_SKILL", p.stdout); self.assertFalse(out.exists())

    def test_quote_escaped(self):
        d = json.loads(json.dumps(DESC)); d["description"] = d["selection_evidence"][0]["value"] = "Dice 'x' con rigor."
        with tempfile.TemporaryDirectory() as t:
            p, out = run(t, "Dice 'x' con rigor.\n", d)
            self.assertEqual(p.returncode, 0, p.stderr); self.assertIn("''x''", out.read_text())

    def test_bad_schema(self):
        with tempfile.TemporaryDirectory() as t:
            p, _ = run(t, "x", {"schema_version": "otro"})
            self.assertEqual(p.returncode, 2)


if __name__ == "__main__":
    unittest.main()
