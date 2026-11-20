# Contrato de auditoría profunda V2

## Entradas

Exigir repository, base_commit, objective, read_scope, write_scope, entrypoints,
consumer_targets, authority_refs, acceptance_criteria y evidence_destination.
La forma exacta se define en [intake V2](../schemas/audit_input_v2.schema.json):
base_commit SHA40 no nulo; read_scope/entrypoints/consumer_targets arrays no vacíos;
sample_n entero 1–100; presupuestos número no negativo o null (desconocido).
write_scope enum acotado a candidato, pruebas y PR. Ver [ejemplo](../examples/audit_input_v2.json).
Tipo/required inválido produce INPUT_SCHEMA_INVALID con ruta del campo. Ref sin
resolver produce NOT_VERIFIED con URI, hash esperado, búsqueda y consumidor
afectado; una divergencia de versión no se sustituye por la fuente más conveniente.
resolution_status declarado no es prueba de autoridad. La referencia vigente
debe resolverse por lectura independiente del permiso afirmado por el solicitante.
Distinguir autoridad declarada y verificada. El handoff autoriza este candidato,
sus pruebas y PR; no reparaciones funcionales reales, catálogo ni promociones.

## Comportamiento

Ejecutar seis fases. Conservar inventario, grafo de dependencias, tabla de
estados, mapa de campos y ledger de evidencia. Seguir cada campo origen →
transformación → transporte → consumidor → decisión. No adivinar fuente de datos
faltantes. Schema y documentación no sustituyen al consumidor real.

La auditoría combina modelo nativo y pruebas; las ayudas AST generan candidatos
acotados hasta que evidencia completa los confirme. Separar defecto de mejora
opcional. No convertir un fallo de contenido en bloqueo del transporte válido.

## Estados

CONFIRMED: defecto demostrado mediante reproducción o prueba estática completa
con consumidor y fuentes resueltas. HYPOTHESIS: indicio con incertidumbre.
NOT_VERIFIED: prueba/fuente no disponible. FIX_VERIFIED: before/after real,
negativos y readback del alcance probado. Fixture corregida no significa LF
reparado. `kind=OPTIMIZATION` identifica una mejora opcional.

## Autoridad

Esta ejecución mantiene promotion_authorized=false. Una auditoría futura deriva
la decisión de la autoridad verificada, no de flags del caller. Validez,
independencia y permiso de efecto son independientes entre sí. El pase contextual
vale donde la política lo acepte; aislamiento verificado del mismo modelo puede
acreditar independencia. No inventar contextos, llamadas, recibos ni permisos.

## Salida y cierre

Cumplir [reporte V2](../schemas/audit_report_v2.schema.json) y el
[contrato de profundidad](reporting_and_contract_depth_v2.md). Conservar V1
histórico sin atribuirle cobertura V2. Entregar al siguiente actor causa, archivos,
funciones, datos, corrección, impacto, prueba y acción autorizada. No trasladar
investigación que ya era posible. Exigir diez pares defectuoso/correcto,
negativos de frescura/identidad/sha/tenant, piloto Paso70 sin efectos, prueba de
generalización sin revelar respuestas, suite, PR y CI exact-head. Si falta algo,
registrarlo pendiente; no cerrar solo por existencia de archivos.

La evidencia actual, previa, leída y no medida lleva clase, origen, fecha, hash
de captura y confianza con razón. Los once pasos incluyen aciertos y faltantes.
El SQL separa flujo y auditoría; plan/muestra sin frecuencia no recomienda MV.
Cada salto usa RUN y hash aplicable; cada emisor PASS necesita negativo ejecutado
o pendiente explícito. Medir cohorte sin llamar falsa a una tasa de punteros.
La matriz revisa contenido por tipo y consumidor; tener un campo no prueba que
su obligación sea entendible o suficiente. No compensar crítico rojo con verdes.

La entrega a Quality cumple [payload tipado](../schemas/quality_handoff_v2.schema.json).
report_ref + report_sha256 deben resolver a los mismos bytes; base/head y cada CI
deben corresponder al candidato. Si falta causa/corrección/prueba ya disponible,
devolver HANDOFF_INSUFFICIENT_ACTIONABLE_CONTEXT con campos concretos faltantes.
No enviar el handoff automáticamente. FLUJO NO ACREDITADO permanece visible aun
con 100 % de tareas conocidas del lote.
