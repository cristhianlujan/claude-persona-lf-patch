# G2B — fixture atómico de vigencia (candidato separado de consumidores)

**Autoridad:** IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7; Router ACT-0001 → ACTUALIZACION_DB_LF → LF Migration Merge Train. EKB previo: IG-M107-FROZEN-CONTEXT-FINAL-COMMIT-FENCE-019, IG-M107-CONTEXT-G2A-REPLAY-READBACK-011, IG-M107-ATOMIC-MANIFEST-REPEAT-005.

**Propósito único:** materializar y probar el mecanismo mínimo de cerco final dentro de una transacción real, sin conectar Curator/Validator ni modificar reglas, contratos de producto, pantallas, 21 triggers o CP3.

## Objetos nuevos y aislados

- `programacion.input_g2b_source_fixture_v1`: tabla solo de prueba sin llaves foráneas ni bindings a LF; RLS activo, sin permisos a PUBLIC, anon, authenticated o service_role. Sin registros después del test.
- `programacion.fn_input_g2b_fixture_epoch_bump_v1()`: trigger exclusivo para ese fixture. Incrementa la época cuando cambia la fuente o contrato; protege la identidad del fixture.
- `programacion.fn_input_g2b_fixture_commit_gate_v1(uuid,bigint,integer,text,bigint,text)`: revisa identidad, contrato, época y SHA **tras bloquear la misma fila con FOR UPDATE**. Solo si coincide, escribe `ACCEPTED` en esa misma transacción. Ningún grant público; su respuesta NO es un veredicto de Input Governance.

El bloque se retiene hasta COMMIT/ROLLBACK del llamador. Un chequeo aislado sin el cierre dentro de esa transacción no es protección suficiente: esta función realiza **ambas operaciones juntas**.

## Pruebas de esta migración

1. Positivo de instantánea intacta.
2. Negativo por cambio real de fuente: época 1 → 2; token anterior rechazado.
3. Negativo por identidad cruzada.
4. Negativo por contrato diferente.
5. Cambio real de contrato provoca incremento de época.
6. Positivo de fuente nueva revalidada.

Todas las inserciones y cambios de fixture de la prueba están en una subtransacción con rollback intencional. Se exigen 0 filas residuales, ACL, comprobación de 21 triggers canónicos, source fingerprints y EKB separado.

## Límites de la evidencia

**NO G2B PASS.** Estas seis pruebas son material SQL real pero una sola sesión; faltan al menos dos sesiones PostgreSQL distintas, COMMIT concurrente del writer, bloqueo intercalado tras la primera lectura y verificación negativa de carrera TOCTOU. También falta demostrar cobertura de *todos* los writers reales (reglas, relaciones, contratos, políticas, fuentes y versiones) y benchmarking del Validator.

G2B verdadero exige Operation admitida, sin pasar credenciales por el agente: T1 freeze en sesión A → cambio/commit aislado en sesión B → T2 stale fail-close en sesión A, además de prueba de writer bloqueado entre comprobación final y COMMIT. Solo entonces analizar G3. Esta migración **no** habilita cache/consumidores, no amplía presupuesto de 150000ms y no concluye CP3.

Rollback funcional de test: subtransacción automática (cero residuo). Reversión de objetos persistidos: una migración separada por Train; nunca borrado manual.
