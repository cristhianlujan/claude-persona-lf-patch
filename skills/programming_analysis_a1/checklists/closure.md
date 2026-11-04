# Evidencia y cierre A1

- [x] Fuente canónica localizada: `REQUEST_CONTEXT_V1`.
- [x] Responsable definido: habilidad A1, no perfil.
- [x] Input/output tipados y bloqueos fail-closed.
- [x] Implementación determinista sin SQL, Router ni RUN.
- [x] Pruebas deterministas previas: 35 casos ejecutados sobre un HEAD anterior (requieren repetición tras los cambios).
- [ ] Byte parity de versión publicada en GitHub, CI de commit definitivo.
- [ ] Revisión semántica independiente sobre casos representativos.
- [ ] Registro/alta gobernada de la habilidad y binding CURRENT RELEASED.
- [ ] Recepción por perfil consumidor y persistencia real del recibo.

**No declarar `SKILL_READY` ni `SKILL_INTEGRATED` antes de acreditar todos los controles aplicables.**

- [x] Frontera de producción semántica y revisión estructural incorporada como código candidato.
- [x] 33 casos de regresión semántica con stand-ins añadidos; **su ejecución en el HEAD actual aún no está acreditada**.
- [ ] Ejecutar la suite completa del HEAD exacto, no inferir PASS del workflow PASE.
- [ ] Conectar invocación de modelo y juez independientes mediante el futuro consumidor autorizado; no generar recibos sintéticos como operativos.
