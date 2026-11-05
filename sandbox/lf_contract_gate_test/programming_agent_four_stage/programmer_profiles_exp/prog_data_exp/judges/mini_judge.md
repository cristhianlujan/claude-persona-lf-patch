# Mini judge — DATA

1. **Source gate:** ¿el código del perfil y el área coinciden con la selección y con el `SKILL.md` fijado a una revisión? Falta de fuente → BLOCK.
2. **Scope gate:** ¿cada ruta visible pertenece al lote resuelto por PG-05 C2 y los tests protegidos quedan fuera de escritura? Cualquier ruta extra → BLOCK.
3. **Domain gate:** El lote declara rutas de migración Flyway. La propuesta debe incluir criterios explícitos de validación y reversibilidad proporcionados por el proyecto. Si falta prueba de seguridad de datos, rollback o migración compatible, bloquear y escalar: no afirmar que un cambio es reversible por defecto. Si faltan criterios del proyecto → RETURN_TO_ORCHESTRATOR.
4. **Oracle/authority gate:** no debe haber claves ocultas ni autoridad nueva, incluso re-hasheada. Hallazgo → BLOCK.
5. **Output gate:** ¿el JSON cumple Worker V2, los comandos y tests son visibles, los límites positivos y el runtime sigue desactivado? Solo una comprobación determinista habilita revisión posterior.

El resultado es evidencia local de estructura, no calificación semántica ni permiso para ejecutar el Worker.
