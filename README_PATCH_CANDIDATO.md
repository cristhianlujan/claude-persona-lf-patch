# PATCH_ASSETS_CLAUDE_PERSONA_LF_v0.1_CANDIDATO

Estado: CANDIDATO_READ_ONLY

Este repositorio técnico se usa para aplicar y probar el patch candidato LF de assets visuales derivado de la auditoría forense sobre `takechanman1228/claude-persona`.

## Archivos del patch

- `assets/workflow.svg`
- `references/ASSET_MANIFEST_LF.md`
- `tests/test_markdown_asset_links.py`
- `docs/ARCHITECTURE.md` mínimo de prueba para validar la ruta `../assets/workflow.svg`

## Gate de prueba

```bash
python3 -m unittest tests/test_markdown_asset_links.py
```

## Estado LF

No es producción oficial. No sustituye el repo original. Sirve como evidencia técnica candidata para probar el fix visual antes de promoverlo o replicarlo en el repo fuente.
