#!/usr/bin/env python3
"""Pruebas de la capa 2b sobre un repo minimo temporal (deterministas, sin depender del repo real)."""
import os
import subprocess
import sys
import shutil
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from repo_search_nivel2_v1 import search, tokens  # noqa: E402


class Repo2b(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.d = tempfile.mkdtemp(prefix="lf2b_")
        files = {
            "docs/analysis/ANALYSIS_PROCEDURE_V1.md": "Procedimiento A1 a A9. El analisis termina con el paquete de implementacion hacia programacion.",
            "docs/router/LF_ROUTER_FLOW_V1.md": "Flujo del router: etapa 1, nivel 1 y nivel 2.",
            "profiles/product_director/SKILL.md": "Perfil del director de producto.",
            "notes/receta.md": "Receta de lomo saltado para el almuerzo.",
            "data/blob.bin": "lomo saltado",
        }
        for rel, txt in files.items():
            p = os.path.join(cls.d, rel)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(txt)
        os.makedirs(os.path.join(cls.d, "ignored"), exist_ok=True)
        with open(os.path.join(cls.d, "ignored", "secret.md"), "w", encoding="utf-8") as fh:
            fh.write("con que termina el analisis de programacion")
        subprocess.run(["git", "-C", cls.d, "init", "-q"], check=True)
        subprocess.run(["git", "-C", cls.d, "add", "docs", "profiles", "notes", "data"], check=True)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.d, ignore_errors=True)

    def refs(self, text, limit=5):
        return [c["ref"] for c in search(self.d, text, limit)["candidatos"]]

    def test_finds_by_path_words(self):
        self.assertEqual(self.refs("flujo del router")[0], "repo://docs/router/LF_ROUTER_FLOW_V1.md")

    def test_finds_by_content_with_user_words(self):
        self.assertIn("repo://docs/analysis/ANALYSIS_PROCEDURE_V1.md", self.refs("con que termina el analisis de programacion"))

    def test_accents_and_case(self):
        self.assertIn("repo://docs/analysis/ANALYSIS_PROCEDURE_V1.md", self.refs("Con qué termina el ANÁLISIS de programación"))

    def test_negative_returns_nothing(self):
        r = search(self.d, "quiero tomar un cafe con mi equipo")
        self.assertEqual((r["resultado"], r["candidatos"]), ("NO_ENCONTRADO_EN_REPO", []))

    def test_untracked_and_non_text_are_not_read(self):
        self.assertEqual(self.refs("lomo saltado almuerzo"), ["repo://notes/receta.md"])
        self.assertNotIn("repo://ignored/secret.md", self.refs("termina analisis programacion"))

    def test_empty_text(self):
        self.assertEqual(search(self.d, "")["resultado"], "NO_ENCONTRADO_EN_REPO")

    def test_contract_flags(self):
        r = search(self.d, "flujo del router")
        self.assertIs(r["downstream_execution_allowed"], False)
        self.assertIs(r["consentimiento_requerido_antes_de_usar"], True)

    def test_limit_is_respected(self):
        self.assertLessEqual(len(search(self.d, "analisis programacion router flujo", 1)["candidatos"]), 1)

    def test_no_synonym_expansion(self):
        self.assertNotIn("repo://docs/router/LF_ROUTER_FLOW_V1.md", self.refs("workflow routing"))
        self.assertEqual(tokens("Análisis de programación"), tokens("analisis programacion"))


if __name__ == "__main__":
    unittest.main(verbosity=1)
