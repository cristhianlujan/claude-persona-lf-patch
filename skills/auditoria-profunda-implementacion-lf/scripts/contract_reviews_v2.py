"""Native-authored contextual reviews for this pilot, not an automatic prose judge.

Unknown cells stay gray. The serializer never infers semantic quality from size,
keywords, field counts or the presence of a heading.
"""
import json
from pathlib import Path
from audit_v2 import contract_grade

PACK = Path(__file__).resolve().parents[1]
ROOT = PACK.parents[1]
REL = PACK.relative_to(ROOT).as_posix()


def quote(path, needle, after=0):
    lines = (ROOT / path).read_text().splitlines()
    starts = [i for i, line in enumerate(lines) if needle in line]
    if not starts: raise ValueError("REVIEW_QUOTE_NOT_FOUND:" + path + ":" + needle)
    i = starts[0]
    return "\n".join(lines[i:i + after + 1])


def reviews():
    profiles = json.loads((PACK / "references/contract_profiles_v2.json").read_text())["profiles"]
    rows = []
    def row(ident, name, kind, fmt, source):
        fields = {}
        for field, rule in profiles[kind]["fields"].items():
            fields[field] = {"status": "NOT_EVALUATED" if rule["required"] else "NOT_APPLICABLE",
                "literal": None,
                "reason": "No se completó el cotejo de esta obligación con su consumidor; no se presume aceptación." if rule["required"] else
                          "El perfil " + kind + " no exige este frente para el cometido local revisado; no se introduce una obligación de otro tipo.",
                "consumer_expectation": rule["meaning"], "source_refs": [source], "semantic_checks": [], "proposed_rewrite": None}
        result = {"id": ident, "name": name, "type": kind, "format": fmt, "source_ref": source,
            "fields": fields, "grade": "NOT_EVALUATED", "semantic_reviewer": "Native audit, same author/context; no independent governance attestation",
            "review_mode": "CURRENT_CONTEXT_SPEC", "does_not_authorize_effect": True}
        rows.append(result)
        return result
    def setcell(r, field, state, path, needle, reason, expected, rewrite=None, after=0, extra=None):
        r["fields"][field] = {"status": state, "literal": quote(path, needle, after) if needle else None,
            "reason": reason, "consumer_expectation": expected, "source_refs": [path] + (extra or []),
            "semantic_checks": ["Obligación aplicable al cometido del consumidor", "Cotejo del literal y su efecto esperado"] if state == "ACCEPTABLE" else [],
            "proposed_rewrite": rewrite}
    main = REL + "/reports/v2_inputs/contract_sources/main_contract_v1.txt"
    r = row("C01", "Entrada del auditor V1", "INPUT", "MD_INPUT_CONTRACT", main)
    setcell(r, "input", "ACCEPTABLE", main, "Exigir repository", "Identifica campos de entrada por nombre; es utilizable como inventario de parámetros.", "El modelo nativo debe conocer objetivo, fuentes, consumidores y alcance antes de leer.", after=2)
    setcell(r, "types", "WEAK", main, "Exigir repository", "La lista de nombres no fija tipo, nulos, cardinalidad ni diferencia entre un ref declarado y uno resuelto. Un ejecutor debe inferirlos.", "Un consumidor debe rechazar base_commit no SHA, consumer_targets vacío y alcance de escritura inválido.", "Definir base_commit como SHA40 no nulo; read_scope/consumer_targets como arrays no vacíos de referencias resueltas; documentar validación y error por campo.", after=2)
    setcell(r, "preconditions", "WEAK", main, "Distinguir autoridad", "La intención es clara, pero no identifica cómo se demuestra currentness de cada fuente ni qué se hace si divergen las versiones.", "El intake debe separar fuente vigente, desconocida y stale antes de producir conclusiones.", "Si commit/ref no resuelve o el hash cambia, registrar el campo y bloquear solo la afirmación afectada; continuar lectura independiente con NOT_VERIFIED.")
    missing = REL + "/contracts/missing_input_policy.md"
    setcell(r, "errors", "ACCEPTABLE", missing, "Commit, consumidor", "Indica faltantes materiales y retorno exacto, sin bloquear otras superficies.", "El receptor recibe missing_fields y búsqueda concreta, no un comentario genérico.", after=3)
    setcell(r, "examples", "WEAK", main, "Exigir diez pares", "Exige casos por capacidad, pero no describe ejemplos de intake que diferencien tipos inválidos de fuentes aún no resueltas.", "El consumidor del intake necesita buenos/malos y resultado de cada campo.", "Añadir input válido completo; base_commit=null; consumer_targets=[]; write_scope fuera del mandato y salida esperada por cada caso.", after=2)

    output = REL + "/reports/v2_inputs/contract_sources/output_v1.schema.json"
    r = row("C02", "Reporte V1", "OUTPUT", "JSON_SCHEMA", output)
    setcell(r, "types", "ACCEPTABLE", output, '"additionalProperties": false', "La forma es cerrada y los campos tienen tipos/enums; eso sí es validación estructural.", "El parser rechaza propiedades no declaradas y tipos incompatibles.")
    setcell(r, "output", "WEAK", output, '"schema_version"', "Su forma no separa cobertura del lote, ledger de once pasos y acreditación del E2E; el lector debe reconstruir esa diferencia desde prosa.", "Un consumidor debe poder leer FLOW_NOT_ACCREDITED aunque el lote esté terminado.", "Usar audit_report_v2: completion.lot_coverage_percent y completion.flow_verdict independientes, más steps/hops/sql_queries/contracts/provenance.", after=3)
    setcell(r, "tests", "WEAK", output, '"phases"', "Completar seis fases no prueba once pasos ni un E2E nuevo. Faltaba negativo que impida deducirlo del porcentaje.", "Un reporte con lote=100 y new_e2e_executed=false nunca debe acreditar el flujo.", "Añadir regresión que rechace FLOW_ACCREDITED sin nueva corrida, recibos resueltos y enlaces de cada salto.", after=4)
    setcell(r, "version_hash", "ACCEPTABLE", output, '"base_commit"', "Exige SHA40 del commit y SHA256 por ubicación; las fuentes pueden fijarse por versión.", "Los literales del hallazgo deben corresponder al commit y hash declarados.", after=3)

    spec = "profiles/product_director_lf/schemas/lf_step70_same_llm_reviewer_output_v1.schema.json"
    r = row("C03", "Salida de revisión Step70", "OUTPUT", "JSON_SCHEMA", spec)
    setcell(r, "output", "ACCEPTABLE", spec, '"required"', "El envelope identifica candidato, alcance, ejecución y cuerpo de decisión.", "EVAL recibe un objeto identificable con fuentes y veredicto.", after=8)
    setcell(r, "types", "WEAK", spec, '"minProperties": 12', "La cota de doce propiedades no enumera nombres ni forma de cada check. Otro productor puede enviar doce claves arbitrarias y pasar la forma.", "EVAL exige set(EXPECTED) y objetos con result/reason/source_refs; la SPEC debe expresar la misma obligación.", "Definir decision_checks.required con los 12 IDs; additionalProperties=false y schema por check con result/razón/refs/contexto aplicable.")
    setcell(r, "version_hash", "ACCEPTABLE", spec, '"$id"', "Tiene identificador de schema y patrones explícitos para los hashes.", "El consumidor distingue esta revisión de la del productor y enlaza candidato/alcance.")
    setcell(r, "tests", "WEAK", spec, '"minLength": 4', "El contrato exige mínimo 4 para referencias; EVAL acepta ['x'] en la reproducción actual. La prueba de paridad no estaba cubriendo ambas capas.", "El mismo RAW debe ser rechazado por SPEC y EVAL cuando rompe el mismo campo.", "Ejecutar paridad schema/EVAL con refs [], [''], ['x'] y referencia válida; conservar diagnóstico exacto de ambas capas.")

    receipt = "scripts/lf_step70_separate_call_receipt_v1.py"
    r = row("C04", "Normalización y transporte Step70", "TRANSPORT", "PYTHON", receipt)
    setcell(r, "input", "MISSING", receipt, None, "No recibe el execution_id esperado del padre, aunque assess_separate_call_receipt sí permite compararlo.", "El consumidor debe recibir origen de autoridad del RUN, no comparar un recibo consigo mismo.", "normalize_when_unverified(review, *, execution_id); pasar el parámetro desde complete_native_profile_semantic_and_report hasta assess_separate_call_receipt.")
    setcell(r, "output", "CONTRADICTORY", receipt, 'safe["verdict"]="PASS_REVIEWED_CURRENT_CONTEXT"', "La ruta material EVAL_FAILURE puede terminar en PASS contextual, borrando el recibo que contradice el dictamen externo.", "Degradar procedencia no autoriza cambiar un EVAL material FAIL a PASS.", "Separar errores de evidencia/procedencia y errores materiales; conservar el fallo y retornar REVIEW_INVALID sin persistir PASS.")
    setcell(r, "errors", "WEAK", receipt, "except ValueError as exc", "El catch agrupa errores de contrato, RUN, hashes y EVAL bajo el mismo diagnóstico de independencia.", "El siguiente paso necesita el código causal real para corregir o rechazar contenido.", "Propagar STEP70_RUN_ID_DRIFT y STEP70_SEPARATE_EVALUATOR_NOT_PASS; permitir fallback solo para procedencia no acreditada con revisión material válida.", after=4)

    evaluator = "scripts/lf_step70_same_llm_eval_v1.py"
    r = row("C05", "EVAL Step70", "EVAL", "PYTHON", evaluator)
    setcell(r, "input", "ACCEPTABLE", evaluator, "def evaluate(raw", "Firma explícita con RAW, RUN y hashes esperados.", "El caller puede entregar identidades y datos por separado para compararlos.")
    setcell(r, "types", "CONTRADICTORY", evaluator, "chk(isinstance(refs,list)", "Exige string no vacío, pero la SPEC exige longitud mínima 4; se reprodujo EVAL PASS y schema FAIL para el mismo RAW.", "Aplicar la misma restricción que el schema del juez, sin inventar reglas nuevas.", "Validar source_refs con el schema congelado o len(ref)>=4; añadir regresión de equivalencia.", after=1, extra=[spec])
    setcell(r, "behavior", "ACCEPTABLE", evaluator, "if not ok:errors.append(code)", "Acumula errores causales y deriva PASS solo cuando no existen errores; es comprobable, aunque hay una obligación de tipo omitida.", "El consumidor recibe errores concretos y un estado derivado, no un PASS por default.")
    setcell(r, "output", "ACCEPTABLE", evaluator, '"eval_status":"PASS" if not errors else "FAIL"', "Define de forma determinista el estado de evaluación.", "El consumidor distingue evaluación ejecutada de una llamada independiente o recibo emitido.", after=6)
    setcell(r, "errors", "ACCEPTABLE", evaluator, '"errors":errors', "Retorna lista de errores y no fabrica atestación de modelo.", "Un negativo conserva su código y no otorga autoridad.", after=4)

    judge = REL + "/reports/v2_inputs/contract_sources/context_spec_judge_v1.txt"
    r = row("C06", "Juez contextual del auditor", "JUDGE", "MD_JUDGE_CONTRACT", judge)
    setcell(r, "scope", "ACCEPTABLE", judge, "Revisar solo objetivo", "Define claramente el cometido y prohíbe heredar gates de otro actor.", "El juez evalúa el contexto aplicable, no exige modelo/proveedor distinto por preferencia.", after=2)
    setcell(r, "behavior", "ACCEPTABLE", judge, "| Válida | Contextual", "La matriz diferencia política contextual suficiente de política que sí exige independencia.", "No vetar automáticamente un pase autorizado por contexto.", after=4)
    setcell(r, "authority", "ACCEPTABLE", judge, "no concede autoridad", "Distingue juicio offline de permiso real y de ejecución de efectos.", "El consumidor verifica la política vigente y no acepta una autoafirmación como autorización.", after=2)
    setcell(r, "output", "ACCEPTABLE", judge, "Emitir evaluation_valid", "Pide resultados separados de validez, procedencia y permiso.", "Un PASS de contenido no se convierte en independencia inventada.", after=1)
    setcell(r, "errors", "WEAK", judge, "Receipt ilegible", "Distingue la causa, pero no define un payload de error propio del juez ni el código y receptor de devolución.", "El siguiente paso debe saber si reparar contrato, contexto, autoridad o evidencia.", "Definir judge_result {evaluation_valid,independence_status,promotion_authorized,blocking_codes,missing_evidence,next_action,source_refs} y ejemplos de retorno.", after=2)

    sql = REL + "/reports/v2_inputs/live_functions.sql"
    r = row("C07", "Selector de skills: contrato SQL", "SQL", "SQL", sql)
    setcell(r, "input", "ACCEPTABLE", sql, "lf_profile_skill_selection_prepare_context_v1(p_profile_code", "La firma identifica perfil, canal, decisión y contexto como argumentos separados.", "El consumidor debe aportar identidad y contexto de la fase correspondiente.")
    setcell(r, "behavior", "ACCEPTABLE", sql, "'reason','INPUT_REQUIRED_NOT_AVAILABLE'", "Excluye candidatos cuyo campo requerido no está disponible, con código causal.", "No seleccionar IG si falta scope; la continuación opcional no equivale a invocación IG.", after=3)
    setcell(r, "authority", "ACCEPTABLE", sql, "d.descriptor_status='CURRENT'", "Consulta registro/política actuales y restringe canales y efecto READ_ONLY antes de seleccionar.", "No aceptar descriptor stale ni operación/efecto ajeno al paso.", after=1)
    setcell(r, "freshness", "NOT_EVALUATED", sql, None, "No se midió frecuencia por intervalo ni refresh; las muestras de planes no bastan para recomendar MV/caché.", "Evaluar consistencia/frescura y frecuencia × costo antes de precalcular.")
    setcell(r, "tests", "WEAK", sql, "'selection_mode','OPTIONAL_FAIL_OPEN'", "La fuente describe el modo, pero no agota negativos de todas las emisiones y ramas con esta auditoría.", "Un input_required roto debe excluir el candidato; un descriptor stale debe rechazarse sin forzar IG obligatorio.", "Añadir negativos por rama y resolver hashes/recibos antes de acreditar un E2E; mantener separados selector y ejecución.")

    snapshot = REL + "/scripts/assess_contracts.py"
    r = row("C08", "Snapshot local de ejemplo", "SNAPSHOT", "PYTHON", snapshot)
    setcell(r, "input", "ACCEPTABLE", snapshot, "def snapshot(payload", "Exige identidad de run/tenant/objeto, revisión y autoridad por argumentos explícitos.", "Un consumidor autorizado debe aportar el mismo contexto esperado en cada lectura.")
    setcell(r, "types", "ACCEPTABLE", snapshot, "SNAPSHOT_REQUIRED_IDENTITY_MISSING", "Rechaza identidad vacía y hash de autoridad inválido; el payload debe ser serializable como JSON.", "No fabricar un snapshot sin identidad ni una autoridad desconocida.")
    setcell(r, "behavior", "ACCEPTABLE", snapshot, 'value["sha256"] != digest(body)', "Recalcula el hash en cada lectura y compara la identidad y revisión esperadas.", "No reusar datos alterados o de otro contexto.", after=8)
    setcell(r, "output", "ACCEPTABLE", snapshot, 'return {"body": copy, "sha256": digest(copy)}', "Devuelve cuerpo copiado y hash; no comparte la referencia mutable del caller.", "Dos consumidores obtienen copias equivalentes sin mutar el snapshot original.")
    setcell(r, "errors", "ACCEPTABLE", snapshot, 'raise ValueError("SNAPSHOT_HASH_MISMATCH")', "El código distingue hash de identidad/currentness.", "El caller rechaza y reconstruye desde fuente autorizada si varía el contexto.", after=6)
    setcell(r, "authority", "ACCEPTABLE", snapshot, '"source_revision": source_revision, "authority_sha256": authority_sha256', "La autoridad es parte del cuerpo firmado por hash, dentro de un helper offline que no concede permiso.", "El runtime futuro debe resolver autoridad vigente; este ejemplo no la autoacredita.")
    setcell(r, "version_hash", "ACCEPTABLE", snapshot, '"source_revision": source_revision, "authority_sha256": authority_sha256', "Enlaza versión de fuente y autoridad en el digest del cuerpo.", "Una revisión distinta debe invalidar lectura.")
    setcell(r, "freshness", "ACCEPTABLE", snapshot, "expected = {", "Requiere source_revision esperado en cada lectura; en el cometido local no necesita TTL inventado.", "La revisión esperada se resuelve por el caller autorizado; no se extrapola este ejemplo a un cache de producción.", after=5)
    tests = REL + "/evals/test_acceptance.py"
    setcell(r, "tests", "ACCEPTABLE", tests, "def test_A05", "El fixture comprueba cinco lecturas frente a una, igualdad, aislamiento de copia, identidad/revisión y tamper.", "Los consumidores conservan valores y rechazan reuso fuera del contexto.", after=5)
    setcell(r, "consumer", "ACCEPTABLE", snapshot, "def read_snapshot(value", "El consumidor exige otra vez todas las identidades y devuelve copia JSON.", "Reuso acotado a mismo run/tenant/objeto/revisión/autoridad.")

    handoff = REL + "/reports/v2_inputs/contract_sources/to_quality_pack_v1.json"
    r = row("C09", "Handoff candidato V1", "HANDOFF", "JSON_HANDOFF", handoff)
    setcell(r, "output", "WEAK", handoff, '"required_payload"', "Lista nombres de elementos, pero no tipa su contenido ni enlaza un schema concreto para construir un paquete ejecutable.", "El receptor necesita causa, fuentes y propuesta verificable, no otra lista de tareas.", "Enlazar payload_schema=audit_report_v2.schema.json; exigir evidencia, pendientes tipados y next_action sin convertir el descriptor en despacho automático.", after=8)
    setcell(r, "consumer", "ACCEPTABLE", handoff, '"target":', "Identifica al receptor y deja despacho automático deshabilitado.", "Una referencia a Quality no prueba que Quality se ejecutó.")
    setcell(r, "authority", "ACCEPTABLE", handoff, '"promotion_authorized": false', "El descriptor no concede promoción ni dispara el perfil.", "La operación futura consume su autoridad vigente por separado.", after=2)

    v2 = REL + "/contracts/reporting_and_contract_depth_v2.md"
    r = row("C10", "Contrato de reporte V2", "SPEC", "MD_SPEC", v2)
    mapping = {
        "scope": ("Mantener separados: cobertura", 3, "Separa calidad del lote, contrato y acreditación; no hereda un PASS entre planos.", "El lector decide qué se probó y qué sigue abierto."),
        "input": ("Recibir objetivo", 2, "Exige fuentes, consumidores y requisitos de E2E; un presupuesto desconocido no se inventa.", "El auditor recibe contexto suficiente para delimitar y medir."),
        "types": ("Tipos de evidencia:", 10, "Los tipos distinguen medición actual, histórica, lectura y ausencia, además del origen.", "El consumidor no mezcla un SELECT actual de un RUN antiguo con E2E nuevo."),
        "behavior": ("Emitir siempre las once filas", 6, "Define todas las fases, contenido de cada fila y qué no se deduce de un estado persistido.", "Una fase omitida queda visible y no produce flujo acreditado."),
        "output": ("Reportes nuevos cumplen", 4, "Enlaza schema y validador V2; conserva V1 como historia y entrega matriz accesible.", "El parser y renderer reciben un formato concreto sin transformar grises en verdes."),
        "errors": ("conservar error/estado", 2, "La medición fallida queda sin números y con causa; no se declara PASS del query.", "El reporte muestra NOT_MEASURED y permite continuar otras superficies."),
        "authority": ("ANALYZE ejecuta la consulta", 6, "Distingue SELECT revisado de escritor/efectos externos y mantiene el alcance autorizado.", "ROLLBACK no se usa como supuesto permiso para ejecutar código con efectos."),
        "version_hash": ("Recibir objetivo", 2, "Exige fuente/versiones y alcance antes de afirmar completitud; el schema V2 fija source_revision SHA40.", "Las observaciones deben enlazar la fuente exacta, no el estado actual por inferencia."),
        "tests": ("Definir y ejecutar un negativo", 4, "Cada emisor debe tener un contraejemplo; si no se ejecuta se reduce cobertura.", "Un PASS que acepta entrada rota queda como defecto y no como prueba verde."),
        "consumer": ("emisor/receptor, campos", 5, "Pide trazabilidad de parámetros y semántica del hash por salto; no exige un candidato antes de crearlo.", "El siguiente paso puede resolver origen y contrato sin reinvestigar a ciegas."),
        "examples": ("| INPUT |", 9, "Incluye ejemplos débiles y operativos diferenciados para diez tipos, con fallos y resultados concretos.", "Otro auditor puede reconocer vaguedad de contenido sin puntuar longitud.")}
    for key, (needle, count, reason, expected) in mapping.items():
        setcell(r, key, "ACCEPTABLE", v2, needle, reason, expected, after=count,
                extra=[REL + "/schemas/audit_report_v2.schema.json"])

    intake = REL + "/schemas/audit_input_v2.schema.json"
    main2 = REL + "/contracts/main_contract.md"
    tests2 = REL + "/evals/test_reporting_v2.py"
    r = row("C11", "Entrada del auditor V2", "INPUT", "JSON_SCHEMA", intake)
    for field, path, needle, count, reason, expected in [
        ("input",intake,'"repository":',8,"Los campos de intake están nombrados, tipados y obligatorios; write_scope es enum acotado.","El ejecutor recibe objetivo, commit, consumidores y límites sin inferir nombres."),
        ("types",intake,'"base_commit":',4,"El commit exige SHA40 y los arrays de superficie/consumidor no pueden ser vacíos; null se admite solo para presupuestos desconocidos.","Rechazar commit nulo, consumidor vacío y escritura fuera de alcance."),
        ("preconditions",main2,"resolution_status declarado",3,"Ordena resolver referencia/autoridad por lectura y no confiar en flags del solicitante.","Una URI declarada no se toma como permiso ni fuente vigente."),
        ("errors",main2,"Tipo/required inválido",4,"El error estructural tiene código y ruta; la falta de ref identifica búsqueda y consumidor afectado.","Continuar lectura independiente sin afirmar lo no verificado."),
        ("version_hash",intake,'"pattern": "^[a-f0-9]{40}$"',0,"La versión base es explícita; refs contienen hash esperado y revisión resuelta.","Anclar observaciones a una revisión y detectar desvíos de fuente."),
        ("tests",tests2,"def test_typed_intake_rejects",10,"Se ejecutaron positivo y negativos de tipos, cardinalidad y alcance; no se deduce autoridad del schema.","El mismo consumidor estructural debe rechazar el intake roto."),
        ("consumer",main2,"La forma exacta se define",8,"Indica qué usa el intake y cómo trata faltantes; enlaza ejemplo y schema.","Un auditor nativo conoce los campos sin trasladar investigación de formato."),
        ("examples",REL + "/examples/audit_input_v2.json",'"schema_version":',8,"El ejemplo aplica tipos y presupuestos null sin inventar latencias; el negativo vive en test_reporting_v2.","Distinguir forma válida de permiso externo aún por resolver.")]:
        setcell(r,field,"ACCEPTABLE",path,needle,reason,expected,after=count)

    handoff2 = REL + "/handoffs/to_quality_pack.handoff.json"
    hschema = REL + "/schemas/quality_handoff_v2.schema.json"
    r = row("C12", "Handoff candidato V2", "HANDOFF", "JSON_HANDOFF", handoff2)
    for field, path, needle, count, reason, expected in [
        ("scope",handoff2,'"status":',0,"Sigue siendo candidato no registrado, con despacho automático falso.","No ejecutar Quality ni efectos por leer el descriptor."),
        ("input",hschema,'"report_ref":',10,"Exige reporte, hash, base y HEAD; payload_schema define los restantes tipos.","El receptor construye un paquete parseable y verifica los bytes del reporte."),
        ("output",handoff2,'"payload_schema":',1,"La lista ahora enlaza un schema concreto con required, arrays, enums y hashes.","No confundir nombres de campos con payload suficientemente tipado."),
        ("errors",main2,"devolver HANDOFF_INSUFFICIENT",2,"Establece código, causa y campos faltantes del handoff.","El emisor recibe una acción de reparación concreta."),
        ("authority",hschema,'"promotion_authorized":',5,"Promoción y despacho son const false en este candidato.","Un handoff de auditoría no autoriza aplicar reparaciones LF."),
        ("version_hash",hschema,'"report_sha256":',4,"Hash del reporte, base/head y head_sha por CI son campos tipados.","Comprobar que CI y evidencia correspondan a los mismos bytes/HEAD."),
        ("consumer",handoff2,'"target":',0,"Quality es receptor explícito y next_gate es revisión del owner sin merge.","Enviar contexto solo por una operación autorizada posterior.")]:
        setcell(r,field,"ACCEPTABLE",path,needle,reason,expected,after=count)
    setcell(r,"tests","WEAK",main2,"report_ref + report_sha256",
        "El contrato exige binding de bytes/CI, pero esta actualización no ejecuta el consumidor Quality con un handoff real.",
        "Validar hash/HEAD divergentes y readback de Quality antes de acreditar ese transporte.",
        "En una prueba gobernada futura, rechazar report_sha256 incorrecto y CI de otro HEAD; verificar recepción exacta por Quality sin aplicar efectos.", after=2)
    setcell(r,"examples","WEAK",handoff2,'"payload_schema":',
        "Hay schema y descriptor, pero no un payload real ejecutado por Quality en este lote.",
        "El receptor debe distinguir ejemplo, envío y readback real.",
        "Guardar el payload con HEAD/CI finales, resultado de validación y recibo del consumidor al ejecutar la operación autorizada.", after=1)

    judge2 = REL + "/judges/context_spec_judge.md"
    jschema = REL + "/schemas/judge_result_v2.schema.json"
    r = row("C13", "Juez contextual V2", "JUDGE", "MD_JUDGE_CONTRACT", judge2)
    for field,path,needle,count,reason,expected in [
        ("scope",judge2,"Revisar solo objetivo",3,"Limita la evaluación al contexto/SPEC/EVAL aplicables, sin gates heredados de otro actor.","El juez conoce el cometido exacto."),
        ("input",judge2,"Resolver la política vigente",4,"Requiere política, función, efecto y readback actuales; no reutiliza permisos históricos.","Recibir criterio y autoridad del efecto exacto antes de autorizar."),
        ("types",jschema,'"independence_status":',7,"Estado de independencia y efecto son enums distintos; true exige autoridad y evaluación válida.","No convertir validez contextual en independencia inventada."),
        ("behavior",judge2,"| Válida | Contextual",4,"La tabla decide según validez, política e independencia aplicable.","No vetar pase contextual admitido ni simular permiso ausente."),
        ("output",judge2,"Usar [salida tipada]",7,"Salida enlazada con schema y acciones literales; errores causales separados de procedencia.","Flags, texto y siguiente acción deben coincidir."),
        ("errors",judge2,"producen evaluation_valid=false",3,"Fallo material y autoridad no resuelta tienen salidas y acciones concretas.","No normalizar EVAL inválido a PASS."),
        ("authority",judge2,"incluidas",0,"La autoridad se resuelve por efecto vigente, no por proveedor/modelo preferido.","Una ruta AUTO válida conserva sus propios criterios."),
        ("version_hash",jschema,'"policy_revision":',8,"La autoridad tipa revisión SHA40, hash SHA256 y readback actual.","No aceptar una política distinta por similitud del nombre."),
        ("tests",tests2,"def test_judge_contextual_pass",19,"Positivo contextual sin independencia inventada y negativos sin autoridad/atestación se ejecutan en fixtures.","Comprobar coherencia de salida; fixture no equivale a autoridad real."),
        ("consumer",judge2,"El schema no autentica",1,"Explica el límite del consumidor estructural y exige resolución nativa de autoridad real.","No usar validación de forma como permiso externo."),
        ("examples",judge2,"Si el contrato vigente acepta",5,"Da combinación concreta de evaluation_valid/NOT_PROVEN/promotion_authorized y efecto.","Un juez futuro debe emitir el permiso literal correcto o identificar la cláusula faltante.")]:
        if field == "authority": needle = "funciones, versiones y readback"; count = 2
        setcell(r,field,"ACCEPTABLE",path,needle,reason,expected,after=count)
    for r in rows:
        grade = contract_grade(r, profiles)
        if grade["errors"]: raise ValueError(r["id"] + ":" + str(grade["errors"]))
        r["grade"] = grade["grade"]
    return rows
