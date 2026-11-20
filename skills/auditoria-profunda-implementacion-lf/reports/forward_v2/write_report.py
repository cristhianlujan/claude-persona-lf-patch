"""Compone el reporte local desde fuentes leídas y resultados realmente ejecutados."""
import hashlib
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "reports/forward_v2"
RAW = "fixtures/forward_v2/raw/"
CORRECT = "fixtures/forward_v2/correct/"
run = json.loads((OUT / "reproduction.json").read_text())
execution = json.loads((OUT / "execution.json").read_text())
profiles = json.loads((ROOT / "references/contract_profiles_v2.json").read_text())
cases = {c["id"]: c for c in run["cases"]}
now = datetime.now(timezone.utc).isoformat()


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


capture = {
    "captured_at": now,
    "source_revision": None,
    "source_state": run["source_state"],
    "files": {},
}
for path in sorted((ROOT / RAW).iterdir()):
    if path.is_file():
        capture["files"][str(path.relative_to(ROOT))] = {
            "sha256": sha(path), "content": path.read_text(),
            "lines": len(path.read_text().splitlines()),
        }
for path in sorted((ROOT / CORRECT).iterdir()):
    if path.is_file():
        assert run["source_hashes"][str(path.relative_to(ROOT))]["sha256"] == sha(path)
for ref, item in capture["files"].items():
    assert run["source_hashes"][ref]["sha256"] == item["sha256"]
(OUT / "source_capture.json").write_text(json.dumps(capture, ensure_ascii=False, indent=2) + "\n")


def field(status, literal, consumer, cause, rewrite=None, refs=None, tests=None):
    return {
        "status": status, "literal": literal,
        "consumer": consumer,
        "consumer_obligation": consumer,
        "cause": cause,
        "reason": cause,
        "source_refs": refs or [],
        "semantic_checks": ["Dato, condición, resultado/error y prueba interpretados por significado", cause],
        "proposed_rewrite": rewrite,
        "test_refs": ["reports/forward_v2/reproduction.json#" + x for x in (tests or [])],
    }


def f(status, literal, consumer, cause, rewrite=None, tests=None):
    return field(status, literal, consumer, cause, rewrite, tests=tests)


def na(reason):
    return f("NOT_APPLICABLE", None, reason, reason)


def version(file):
    return f("ACCEPTABLE", capture["files"][RAW + file]["sha256"], "Identificar los bytes exactos revisados del fixture local", "Hash SHA256 calculado de la fuente; commit desconocido. No se afirma compatibilidad entre versiones ni Git HEAD.")


def tests(*ids):
    return f("ACCEPTABLE", "Evidencia ejecutada adjunta; no se atribuye al raw una suite previa.", "Oráculo positivo/negativo reproducible de esta auditoría", "Los casos enlazados se ejecutaron y conservaron resultado literal, incluidos errores esperados del baseline.", tests=list(ids))


contracts = []


def add(cid, kind, fmt, filename, cells, scope):
    profile = profiles["profiles"][kind]
    assert set(profile["fields"]) <= set(cells)
    for key, cell in cells.items():
        cell["critical"] = profile["fields"].get(key, {}).get("critical", key in ("currency_enum", "as_of_binding"))
        cell["required_by_profile"] = profile["fields"].get(key, {}).get("required", False)
        if not cell["source_refs"]:
            cell["source_refs"] = [RAW + filename, "reports/forward_v2/source_capture.json", "references/contract_profiles_v2.json#" + kind]
    if any(x["critical"] and x["status"] in ("WEAK", "MISSING", "CONTRADICTORY") for x in cells.values()):
        grade = "LOW"
    elif any(x["status"] == "NOT_EVALUATED" for x in cells.values()):
        grade = "NOT_EVALUATED"
    elif any(x["status"] in ("WEAK", "MISSING", "CONTRADICTORY") for x in cells.values()):
        grade = "MEDIUM"
    else:
        grade = "ACCEPTABLE"
    contracts.append({"id": cid, "type": kind, "format": fmt, "source_ref": RAW + filename,
                      "scope": scope, "format_appropriate": fmt in profile["accepted_formats"],
                      "format_reason": "Se acepta el formato nativo y sus referencias; la extensión .txt no impide interpretar prosa como contrato Markdown.",
                      "fields": cells, "grade": grade,
                      "semantic_reviewer": "Modelo nativo en contexto de la prueba local",
                      "review_mode": "CURRENT_CONTEXT_SPEC", "does_not_authorize_effect": True})


add("C_INPUT", "INPUT", "JSON_SCHEMA", "input.schema.json", {
    "scope": na("Schema de entrada; no necesita repetir el objetivo general del sistema."),
    "input": f("MISSING", '"required":["portfolio_key","execution_id"]', "pipeline.run exige también currency, source_revision y as_of", "El schema admite payload sin tres argumentos obligatorios; el único entrypoint descubierto no puede consumirlo.", '"required":["portfolio_key","execution_id","currency","source_revision","as_of"]', ["RAW_SCHEMA_MINIMAL", "RAW_MINIMAL_TO_RUN", "CORRECT_SCHEMA_MISSING_AS_OF"]),
    "types": f("WEAK", '"portfolio_key":{"type":"string"},"execution_id":{"type":"string"}', "assess consume moneda PEN/USD y compara dos tokens", "Tipos de IDs concretos, moneda sin enum; dominio/nulos de revisión no definidos. No se impone string por preferencia.", 'currency: {"type":"string","enum":["PEN","USD"]}; documentar tokens opacos sin adivinar su tipo.'),
    "preconditions": f("MISSING", None, "run debe recibir cinco argumentos; assess compara source_revision con as_of", "No hay enlace al receptor ni condición de igualdad. JSON Schema estándar no expresa esa igualdad mediante required.", 'description: "Entrada de pipeline.run. La igualdad source_revision == as_of se comprueba en consumer.assess."'),
    "behavior": na("Las ramas de decisión pertenecen al consumidor; no se exige duplicarlas físicamente en JSON Schema."),
    "output": na("Este artefacto valida entrada, no especifica la salida READY."),
    "errors": f("MISSING", None, "El caller necesita distinguir rechazo de schema, TypeError y ValueError de assess", "No existe mapeo ni consumidor de validación de schema en los tres Python leídos.", 'description: "Validar required/enum antes de run; conservar CURRENCY_UNSUPPORTED y SOURCE_REVISION_STALE del consumidor. La integración del loader queda pendiente."'),
    "authority": na("Schema puro sin acciones externas; no es prueba de autoridad."),
    "version_hash": f("WEAK", None, "Fijar interpretación del schema para otro validador", "Sin $schema ni $id; esta auditoría eligió explícitamente Draft 2020-12 para ejecutar las pruebas.", '"$schema":"https://json-schema.org/draft/2020-12/schema", "$id":"urn:forward-v2:run-input:proposed-1"'),
    "tests": tests("RAW_SCHEMA_MINIMAL", "RAW_SCHEMA_UNSUPPORTED", "CORRECT_SCHEMA_NOMINAL", "CORRECT_SCHEMA_UNSUPPORTED"),
    "consumer": f("MISSING", None, "pipeline.run y consumer.assess son los consumidores descubiertos", "Ningún Python carga input.schema.json. La correspondencia se audita por firma; no se inventa integración runtime.", 'title: "Entrada de pipeline.run del fixture sintético"; añadir referencia al loader cuando exista.'),
    "examples": f("MISSING", None, "Otro ejecutor necesita un payload de cinco campos que pueda reproducir", "No hay ejemplo en el schema original.", json.dumps({"portfolio_key":"portfolio-A","execution_id":"run-A","currency":"PEN","source_revision":"revision-1","as_of":"revision-1"}, ensure_ascii=False)),
    "freshness": f("NOT_EVALUATED", None, "Definir quién suministra as_of y qué revisión es vigente", "No hay fuente confiable, presupuesto de frescura ni dominio del token en los seis archivos. La igualdad no prueba actualidad.", "Decisión pendiente: identificar fuente de as_of y política de nulos/tipos antes de acreditar frescura externa.", ["CORRECT_NULL_REVISION_BOUNDARY", "CORRECT_WRONG_AS_OF_BOUNDARY"]),
    "currency_enum": f("MISSING", None, 'assess: message["currency"] in ("PEN", "USD")', "Obligación adicional descubierta en consumidor; no declarada por el schema.", '"currency":{"type":"string","enum":["PEN","USD"]}', ["RAW_SCHEMA_UNSUPPORTED", "CORRECT_SCHEMA_UNSUPPORTED"]),
}, "Contrato de entrada contrastado con la firma de run; integración de un loader no demostrada.")

add("C_PRODUCER", "TRANSPORT", "PYTHON", "producer.py", {
    "scope": na("Transformación local de argumentos a mensaje; sin otro efecto."),
    "input": f("ACCEPTABLE", "def prepare(portfolio_key, execution_id, *, currency, source_revision):", "run entrega cuatro valores a prepare", "La firma exige todos los valores y run los pasa por nombre correctamente."),
    "types": f("WEAK", "currency, source_revision", "Preservar valor y tipo hasta assess", "No hay anotaciones ni contrato referenciado del mensaje; el tipo de los tokens sigue sin decisión.", "Conservar literalmente los cuatro valores; enlazar al schema del mensaje cuando se defina su dominio."),
    "preconditions": na("prepare no es el juez de moneda/frescura; no se exige duplicar sus controles."),
    "behavior": f("MISSING", 'return {"portfolio_key": portfolio_key, "execution_id": execution_id}', "assess necesita currency y source_revision", "Los dos parámetros existen pero nunca se copian al mensaje.", 'return {"portfolio_key":portfolio_key,"execution_id":execution_id,"currency":currency,"source_revision":source_revision}', ["RAW_PREPARE_LOSS", "CORRECT_PREPARE_READBACK"]),
    "output": f("MISSING", '{"portfolio_key": portfolio_key, "execution_id": execution_id}', "El mensaje debe llevar las claves leídas por assess", "Pérdida material demostrada mediante readback y dos KeyError sucesivos.", 'Añadir "currency": currency y "source_revision": source_revision al dict devuelto.', ["RAW_AFTER_BINDING_ONLY", "RAW_AFTER_CURRENCY_ONLY", "CORRECT_PREPARE_READBACK"]),
    "errors": f("ACCEPTABLE", "def prepare(portfolio_key, execution_id, *, currency, source_revision):", "Faltas de argumentos se rechazan por la firma Python", "La función no atrapa ni convierte fallas en READY; el defecto es de transporte, no falta de try/except."),
    "authority": na("Solo construye un dict local; no autoriza acciones."),
    "version_hash": version("producer.py"),
    "tests": tests("RAW_PREPARE_LOSS", "RAW_AFTER_BINDING_ONLY", "RAW_AFTER_CURRENCY_ONLY", "CORRECT_PREPARE_READBACK"),
    "consumer": f("CONTRADICTORY", 'return {"portfolio_key": portfolio_key, "execution_id": execution_id}', 'consumer.assess lee message["currency"] y message["source_revision"]', "El payload disponible no satisface al consumidor real, aunque la llamada a prepare sí es compatible.", "Transportar ambas claves; no reconstruirlas en assess ni inventar defaults."),
    "examples": na("La función ejecutable y los cuatro casos enlazados proporcionan ejemplo; no se exige otro bloque narrativo para TRANSPORT."),
    "freshness": f("MISSING", "source_revision", "Comparación de revisión en assess", "La revisión ya recibida se pierde; esta omisión sí está demostrada y es distinta de validar su fuente.", 'Incluir "source_revision": source_revision; mantener as_of en run para entregarlo a assess.'),
}, "Primer salto que pierde currency/source_revision; no se exige enviar as_of a prepare porque no lo consume.")

add("C_PIPELINE", "TRANSPORT", "PYTHON", "pipeline.py", {
    "scope": na("Orquestación local sin pasos LF ni DB."),
    "input": f("ACCEPTABLE", "def run(portfolio_key, execution_id, *, currency, source_revision, as_of):", "El caller debe dar cinco argumentos", "Todos están explícitos, sin defaults. as_of está disponible antes de llamar al consumidor."),
    "types": f("WEAK", "currency, source_revision, as_of", "Mantener tipos/valores sin reinterpretación", "Sin enlace al contrato de entrada y tokens de tipo no resuelto.", "Enlazar schema de entrada; no convertir los tokens durante transporte."),
    "preconditions": na("Las guardas de moneda/revisión se delegan a assess; no se pide duplicación."),
    "behavior": f("CONTRADICTORY", "return assess(message)", "assess(message, *, as_of) exige el argumento keyword-only", "El argumento recibido no se entrega. La firma Python falla antes de ejecutar las guardas del consumidor.", "return assess(message, as_of=as_of)", ["RAW_RUN_VALID", "CORRECT_RUN_PEN"]),
    "output": f("CONTRADICTORY", "return assess(message)", "Entrada nominal debe poder producir READY local", "Todo recorrido nominal de run termina en TypeError; no puede propagar el retorno de assess.", "Pasar as_of y preservar currency/source_revision en producer; corregir solo una causa no basta.", ["RAW_RUN_VALID", "RAW_AFTER_BINDING_ONLY", "CORRECT_RUN_PEN"]),
    "errors": f("WEAK", "return assess(message)", "Un negativo debe llegar al rechazo semántico de assess", "TypeError de binding enmascara tanto los campos perdidos como los errores de negocio declarados.", "Corregir la llamada; mantener excepciones de assess sin convertirlas en READY.", ["CORRECT_UNSUPPORTED", "CORRECT_STALE"]),
    "authority": na("No hay escritura ni promoción; retorno local no acredita permiso."),
    "version_hash": version("pipeline.py"),
    "tests": tests("RAW_RUN_VALID", "RAW_AFTER_BINDING_ONLY", "CORRECT_RUN_PEN", "CORRECT_UNSUPPORTED", "CORRECT_STALE"),
    "consumer": f("CONTRADICTORY", "assess(message)", "consumer.py:1 requiere as_of keyword-only", "Firma y llamada incompatibles: primer fallo real probado.", "assess(message, as_of=as_of)"),
    "examples": na("TRANSPORT permite revisión de código y casos ejecutados sin plantilla narrativa adicional."),
    "freshness": f("MISSING", "as_of", "assess necesita el valor esperado para comparar la revisión", "El dato existe en run pero falta en la llamada siguiente.", "Entregar as_of por keyword y probar source_revision distinta."),
    "as_of_binding": f("CONTRADICTORY", "return assess(message)", "def assess(message, *, as_of)", "Obligación descubierta en firma del receptor, ausente del mensaje/callsite.", "return assess(message, as_of=as_of)"),
}, "Binding del argumento obligatorio; TypeError primero, pérdidas de payload después.")

add("C_CONSUMER", "EVAL", "PYTHON", "consumer.py", {
    "scope": na("Evaluador puro del fixture, no juez de promoción."),
    "input": f("ACCEPTABLE", 'def assess(message, *, as_of):', "Recibir mensaje y token esperado", 'Lecturas directas identifican currency/source_revision/execution_id; ausencia se traduce en KeyError, sin default silencioso.'),
    "types": f("NOT_EVALUATED", 'message["source_revision"] != as_of', "Definir dominio y nulos de tokens si READY pretende significar revisión vigente", "No hay especificación del tipo/procedencia que permita afirmar que None u otro token igual es inválido.", "Resolver política antes de añadir validación de tipos/nulos; no cambiar consumer en la corrección mínima.", ["CORRECT_NULL_REVISION_BOUNDARY"]),
    "preconditions": f("ACCEPTABLE", 'message["currency"]; message["source_revision"]; message["execution_id"]', "Claves necesarias presentes para retornar READY", "Python define rechazo de claves ausentes y del keyword as_of. No se exige una plantilla de precondiciones separada."),
    "behavior": f("ACCEPTABLE", 'if message["currency"] not in ("PEN", "USD"):', "Moneda primero, revisión después", "Ambos rechazos coinciden literalmente con error_contract; prioridad probada.", tests=["RAW_ERROR_PRECEDENCE", "CORRECT_ERROR_PRECEDENCE"]),
    "output": f("ACCEPTABLE", 'return {"decision": "READY", "execution_id": message["execution_id"]}', "READY local con mismo execution_id del mensaje", "Retorno preciso; no hay APPLIED ni efectos externos. Otro ID se copia, no se autentica.", tests=["RAW_DIRECT_CONSUMER_PEN", "CORRECT_EXECUTION_ID"]),
    "errors": f("ACCEPTABLE", 'raise ValueError("CURRENCY_UNSUPPORTED"); raise ValueError("SOURCE_REVISION_STALE")', "Rechazo antes del retorno READY", "Códigos y condiciones ejecutados para moneda inválida y revisión distinta; KeyError de faltantes también observado.", tests=["RAW_UNSUPPORTED", "RAW_STALE", "CORRECT_MISSING_CURRENCY"]),
    "authority": na("Ninguna autoridad real se infiere de esta función pura."),
    "version_hash": version("consumer.py"),
    "tests": tests("RAW_DIRECT_CONSUMER_PEN", "RAW_DIRECT_CONSUMER_USD", "RAW_UNSUPPORTED", "RAW_STALE", "CORRECT_MISSING_EXECUTION_ID"),
    "consumer": f("ACCEPTABLE", "pipeline.py: return assess(message)", "run es el caller descubierto; el retorno se entrega directamente", "Consumidor resuelto por import explícito; el binding roto se registra en C_PIPELINE, sin culpar a la guarda correcta."),
    "examples": na("EVAL no exige ejemplos adicionales cuando el código y las pruebas enlazadas determinan los oráculos."),
    "freshness": f("NOT_EVALUATED", 'message["source_revision"] != as_of', "Contrastar igualdad local con fuente autorizada si se reclama actualidad", "Dos valores iguales ajenos pasan. Fuente, período y presupuesto no existen en el fixture.", "No llamar a esta igualdad prueba de actualidad; documentar fuente de as_of antes de ampliar el efecto.", ["CORRECT_WRONG_AS_OF_BOUNDARY"]),
}, "Guardas y retorno local; política externa de tipos/procedencia sin evaluar.")

handoff = (ROOT / RAW / "handoff.txt").read_text()
add("C_HANDOFF", "HANDOFF", "MD_HANDOFF", "handoff.txt", {
    "scope": f("WEAK", "casos relevantes", "Mantenedor necesita archivos, funciones y alcance de cambio", "No identifica implementación ni operación concreta.", "Revisar solo fixtures/forward_v2: producer.prepare y pipeline.run; sin efectos LF."),
    "input": f("WEAK", "Entregar los datos necesarios", "Identificar campos, fuente y destino", "No enumera currency/source_revision/as_of ni su origen.", "run recibe currency/source_revision/as_of; prepare devuelve los dos primeros y run entrega as_of a assess."),
    "types": na("El handoff puede referenciar contratos de tipos; no necesita duplicar un JSON Schema."),
    "preconditions": f("WEAK", "validar todo lo necesario", "Saber cuándo detener adopción del candidato", "No hay guard ni criterio de bloqueo.", "Detener adopción si falla el positivo nominal o si EUR/revisión distinta no se rechazan."),
    "behavior": f("WEAK", "La solución deberá ser robusta, suficiente y completa", "Otro ejecutor debe poder aplicar un cambio exacto", "Los adjetivos no determinan la instrucción ni una condición verificable.", 'prepare: añadir "currency":currency y "source_revision":source_revision; run: assess(message, as_of=as_of).'),
    "output": f("WEAK", "informar los resultados y las recomendaciones oportunas", "Entregar causa/código/prueba/readback al receptor", "Salida sin artefacto, resultado esperado ni binding al candidato.", "Entregar reporte JSON/Markdown, diff de correct, comando y resultado literal del before/after."),
    "errors": f("WEAK", "Gestionar correctamente los errores", "Códigos y siguiente acción concretos", "No diferencia TypeError de binding, KeyError de payload o ValueError de las guardas.", "TypeError as_of: corregir callsite; KeyError currency/source_revision: reparar prepare; EUR/mismatch deben conservar sus ValueError."),
    "authority": f("MISSING", None, "Distinguir prueba local autorizada de cambios LF/envío externo", "No acota efecto ni actor; no puede conceder permisos por adjetivos.", "Solo candidato local y sus pruebas en rutas autorizadas. Sin producción, envío, Git, promoción ni cambios LF."),
    "version_hash": f("MISSING", None, "Vincular diagnóstico y cambio a fuentes concretas", "El handoff no identifica archivos ni revisiones/hash del código afectado.", "Resolver hashes de raw/correct desde reports/forward_v2/reproduction.json; source_revision=null, FIXTURE_COMMIT_NOT_RESOLVED."),
    "tests": f("WEAK", "una evaluación apropiada", "Positivo/negativo con entrada y resultado esperado", "Ningún oráculo ni comando permite demostrar suficiencia.", "python -B reports/forward_v2/reproduce.py; PEN/USD→READY, EUR→CURRENCY_UNSUPPORTED, mismatch→SOURCE_REVISION_STALE."),
    "consumer": f("WEAK", "enviar al equipo correspondiente", "Identificar receptor y acción siguiente", "No existe receptor concreto ni mecanismo de entrega. No se inventa un equipo real.", "Receptor: mantenedor del fixture fixtures/forward_v2; revisar propuesta local. No enviar automáticamente."),
    "examples": f("MISSING", None, "Mostrar al menos una llamada/negativo reproducible", "No hay ejemplo operativo en las cinco líneas originales.", "run('portfolio-A','run-A',currency='PEN',source_revision='revision-1',as_of='revision-1') → READY."),
    "freshness": na("Este handoff no es un snapshot ni define política de vigencia; debe remitir al pendiente ya descrito."),
}, "Accionabilidad de una entrega: causa, archivos, cambio, prueba, alcance y receptor.")

error_text = (ROOT / RAW / "error_contract.txt").read_text()
add("C_ERRORS", "SPEC", "MD_SPEC", "error_contract.txt", {
    "scope": f("ACCEPTABLE", "El receptor assess rechaza el mensaje antes de emitir READY.", "Definir dos rechazos del receptor identificado", "El cometido del artefacto está delimitado por sus dos condiciones y el receptor; no pretende ser contrato completo de promoción."),
    "input": f("ACCEPTABLE", "currency fuera de PEN/USD; source_revision distinta de as_of", "Identificar datos de las dos guardas", "Los tres nombres resuelven a las lecturas y al argumento de consumer.assess; execution_id no interviene en estos dos rechazos."),
    "types": f("ACCEPTABLE", "currency fuera de PEN/USD; source_revision distinta de as_of", "Conjunto admitido de moneda y predicado de comparación", "PEN/USD fija valores concretos; distinta fija desigualdad de tokens. El parcial no afirma un tipo más estricto ni procedencia externa."),
    "preconditions": na("El contrato parcial no afirma exhaustividad de todas las excepciones Python; claves/as_of obligatorios se resuelven en la firma y lecturas del receptor."),
    "behavior": f("ACCEPTABLE", error_text.strip(), "Cada condición debe conducir al rechazo nombrado", "Las tres cláusulas coinciden con consumer.py:2-6. Prioridad de moneda observada; no se usa longitud como nota."),
    "output": f("ACCEPTABLE", 'ValueError("CURRENCY_UNSUPPORTED"); ValueError("SOURCE_REVISION_STALE"); antes de emitir READY', "Resultado/error entendible y comprobable", "Tipo/código y exclusión de READY están determinados para ambas condiciones; los dos negativos los reproducen."),
    "errors": f("ACCEPTABLE", error_text.splitlines()[0] + "\n" + error_text.splitlines()[1], "No adivinar los dos códigos de rechazo", "Condición y código exactos, sin frases abiertas. No se extiende esta aceptación al pipeline roto.", tests=["RAW_UNSUPPORTED", "RAW_STALE"]),
    "authority": na("Reglas de rechazo de función pura: no es una política de permiso ni un dictamen independiente."),
    "version_hash": version("error_contract.txt"),
    "tests": tests("RAW_UNSUPPORTED", "RAW_STALE", "RAW_ERROR_PRECEDENCE"),
    "consumer": f("ACCEPTABLE", "El receptor assess", "Resolver función y rutas de error", "Nombre resuelto a consumer.py por pipeline.py:2; revisión contextual de la función completa."),
    "examples": f("ACCEPTABLE", 'ValueError("CURRENCY_UNSUPPORTED"); ValueError("SOURCE_REVISION_STALE")', "Contraejemplos concretos que cubran los dos predicados", "EUR y revision-0/as_of revision-1 de la evidencia actual instancian ambas cláusulas sin completar por adivinanza.", tests=["RAW_UNSUPPORTED", "RAW_STALE"]),
    "freshness": na("El predicado declara desigualdad con as_of; comprobar vigencia externa requiere otro contrato y no se acredita aquí."),
}, "Solo las tres cláusulas de rechazo. ACCEPTABLE no afirma completitud de la implementación, tipo del token, autoridad, independencia ni E2E.")


def finding(fid, title, status, code, file, start, end, func, cause, expected, fix, before, after, kind="DEFECT", confidence="HIGH"):
    return {
        "id": fid, "title": title, "status": status, "kind": kind, "code": code,
        "location": {"file": RAW + file, "function": func, "lines": [start, end],
                     "commit": "FIXTURE_COMMIT_NOT_RESOLVED", "source_revision": None,
                     "sha256": capture["files"][RAW + file]["sha256"]},
        "literal": "\n".join(capture["files"][RAW + file]["content"].splitlines()[start-1:end]),
        "consumer": "pipeline.run / consumer.assess" if file != "handoff.txt" else "Mantenedor del fixture; equipo real no identificado",
        "cause": cause, "expected": expected, "correction_exact": fix,
        "before_cases": before, "after_cases": after,
        "test_evidence": [cases[x] for x in before + after],
        "impact": title, "scope": "FIXTURE_ONLY",
        "fix_scope": "FIXTURE" if status == "FIX_VERIFIED" else "PROPOSAL_ONLY",
        "readback": {"performed": True, "source": "reports/forward_v2/source_capture.json", "runtime": "reports/forward_v2/reproduction.json" if before else None},
        "confidence": confidence,
        "confidence_reason": "Fuente y consumidor leídos; salida actual preservada." if confidence == "HIGH" else "Observación local comprobada; falta política o integración para afirmar defecto material.",
        "rollback": "Descartar correct; raw permanece como baseline. Sin cambio funcional LF.",
        "does_not_authorize_effect": True,
    }


findings = [
    finding("F01", "Schema admite entrada incompleta para el entrypoint descubierto", "FIX_VERIFIED", "SPEC_REQUIRED_FIELD_OMITTED", "input.schema.json", 1, 1, "schema", "Solo declara dos de los cinco argumentos obligatorios de run; no refleja enum de moneda.", "Required de cinco campos y currency PEN/USD; sin afirmar que exista loader integrado.", (ROOT / CORRECT / "input.schema.json").read_text(), ["RAW_SCHEMA_MINIMAL", "RAW_MINIMAL_TO_RUN", "RAW_SCHEMA_UNSUPPORTED"], ["CORRECT_SCHEMA_NOMINAL", "CORRECT_SCHEMA_MISSING_CURRENCY", "CORRECT_SCHEMA_MISSING_SOURCE_REVISION", "CORRECT_SCHEMA_MISSING_AS_OF", "CORRECT_SCHEMA_UNSUPPORTED"]),
    finding("F02", "prepare descarta currency y source_revision", "FIX_VERIFIED", "STEP_CONTEXT_INSUFFICIENT", "producer.py", 1, 2, "prepare", "El dict de retorno se reduce a dos IDs aunque recibe ambos datos necesarios para assess.", "Conservar literalmente currency/source_revision junto con portfolio_key/execution_id.", (ROOT / CORRECT / "producer.py").read_text(), ["RAW_PREPARE_LOSS", "RAW_AFTER_BINDING_ONLY", "RAW_AFTER_CURRENCY_ONLY"], ["CORRECT_PREPARE_READBACK", "CORRECT_RUN_PEN", "CORRECT_UNSUPPORTED", "CORRECT_STALE"]),
    finding("F03", "run omite as_of y falla antes de evaluar el mensaje", "FIX_VERIFIED", "CALL_BINDING_INCOMPATIBLE", "pipeline.py", 5, 7, "run", "as_of está en la firma del caller pero no en la llamada assess; TypeError enmascara el defecto del mensaje.", "Pasar as_of por keyword y corregir la pérdida upstream; una sola reparación no restituye el flujo local.", (ROOT / CORRECT / "pipeline.py").read_text(), ["RAW_RUN_VALID", "RAW_AFTER_BINDING_ONLY"], ["CORRECT_RUN_PEN", "CORRECT_RUN_USD", "CORRECT_ERROR_PRECEDENCE"]),
    finding("F04", "Handoff no determina receptor, causa, cambio ni oráculo", "CONFIRMED", "OUTPUT_NOT_ACTIONABLE", "handoff.txt", 1, 5, "handoff", "Adjetivos y referencias abiertas reemplazan campos operativos aunque código/consumidor están disponibles para investigarlos.", "Identificar causa, archivos/funciones, código exacto, positivo/negativo, alcance, receptor y rollback.", (ROOT / CORRECT / "handoff.txt").read_text(), [], [], confidence="HIGH"),
    finding("F05", "Tipo y origen confiable de los tokens no están definidos", "NOT_VERIFIED", "TOKEN_DOMAIN_AND_PROVENANCE_UNSPECIFIED", "consumer.py", 4, 6, "assess", "La comparación solo verifica igualdad con un argumento del caller. No hay política sobre nulos/tipos ni fuente autorizada.", "Resolver tipo, nulos y origen de as_of antes de interpretar READY como actualidad externa. No se declara inválido un dato sin contrato.", "Propuesta contractual pendiente, sin cambio de consumer: identificar quién obtiene as_of y el dominio/nulos admitidos de ambos tokens.", ["CORRECT_NULL_REVISION_BOUNDARY", "CORRECT_WRONG_AS_OF_BOUNDARY"], [], kind="GOVERNANCE_GAP", confidence="MEDIUM"),
    finding("F06", "Compatibilidad de claves extra depende de un loader no descubierto", "HYPOTHESIS", "SCHEMA_CALLER_BINDING_UNRESOLVED", "input.schema.json", 1, 1, "schema/caller", "additionalProperties=true permite extra; run(**payload) no lo admite. Ningún loader enlaza ambos artefactos en el fixture.", "Si el schema se usa como entrada directa, decidir proyección de argumentos o additionalProperties=false. La integración real está sin verificar.", "Pendiente de contrato de compatibilidad: proyectar explícitamente los cinco parámetros conocidos antes de run, o rechazar extras en schema si se autoriza ese cambio.", ["CORRECT_SCHEMA_EXTRA_BOUNDARY", "CORRECT_RUN_EXTRA_BOUNDARY"], [], confidence="MEDIUM"),
]

assert execution["exit_code"] == 0
assert run["summary"]["assertions_failed"] == 0
assert all(x["format_appropriate"] for x in contracts)

report = {
    "schema_version": "LF_FORWARD_V2_LOCAL_USE_TEST_1",
    "report_status": "LOCAL_FIXTURE_REVIEW_COMPLETE_WITH_LIMITS",
    "audit_context": {
        "objective": "Prueba de uso desde contexto limpio del paquete: descubrir omisiones y evaluar contenido sin respuestas previas.",
        "started_at": run["captured_at"], "collected_at": now,
        "source_revision": None, "source_state": run["source_state"],
        "read_scope": [RAW + p.name for p in sorted((ROOT / RAW).iterdir()) if p.is_file()],
        "write_scope": ["reports/forward_v2/", CORRECT],
        "promotion_authorized": False, "independence_proven": False,
        "authority_verified": False, "new_lf_e2e_executed": False,
        "scope_authority": "Instrucción del solicitante para esta prueba local; no autoridad LF gobernada.",
        "full_lf_v2_report_conformance": "NOT_CLAIMED",
        "conformance_reason": "Formato propio autorizado: no commit SHA40, PR/CI/readback gobernado ni pasos LF ejecutados; no se suplanta schemas/audit_report_v2.schema.json.",
    },
    "completion": {
        "lot_coverage_percent": 100,
        "known_raw_files_read": 6, "known_raw_files_total": 6,
        "known_python_functions_read": 3, "known_python_functions_total": 3,
        "contract_quality": {c["id"]: c["grade"] for c in contracts},
        "flow_verdict": "FLOW_NOT_ACCREDITED",
        "flow_reasons": ["Prueba sintética local; no ejecución LF", "Raw sigue defectuoso; correct solo candidato aislado", "Currentness, autoridad e independencia reales no verificados"],
        "known_pending": ["Dominio/nulos/fuente de tokens", "Loader de schema y política de extras", "EKB vigente sin consulta por alcance sin DB", "Revisión por receptor real del handoff no realizada"],
    },
    "discovery": {
        "method": ["rg --files", "rg -n sobre firmas/imports/keys/READY/errores", "Lectura integral de los seis archivos", "AST de las tres funciones sin ejecutar descubrimientos desconocidos"],
        "functions": run["ast_inventory"],
        "imports": [{"source": RAW + "pipeline.py:1", "target": RAW + "producer.py:prepare"}, {"source": RAW + "pipeline.py:2", "target": RAW + "consumer.py:assess"}],
        "new_consumer_obligations_not_in_schema": ["currency presente y PEN/USD", "source_revision presente", "as_of argumento keyword-only", "execution_id presente para salida", "source_revision == as_of antes de READY"],
        "source_lineage": "Argumentos sintéticos del harness → run → prepare → message → assess → retorno/exception local",
        "no_live_caller_found": True, "schema_loader_found": False,
        "not_read": ["reports/pilot*", "reports/perfil*", "scripts/build_report*", "scripts/contract_reviews*", "evals/test_*", "Otros resultados previos y fuentes fuera del paquete"],
        "contracts_read": ["SKILL.md", "contracts/main_contract.md", "contracts/reporting_and_contract_depth_v2.md", "contracts/missing_input_policy.md", "references/contract_profiles_v2.json", "checklists/preflight_checklist.md", "references/scope.md", "references/inspection_rules.md", "references/defect_taxonomy.json", "schemas/audit_report_v2.schema.json"],
    },
    "hops": [
        {"sender":"caller sintético", "receiver":"run", "available":["portfolio_key","execution_id","currency","source_revision","as_of"], "sent":["portfolio_key","execution_id","currency","source_revision","as_of"], "lost":[], "evidence":["RAW_RUN_VALID"], "limit":"No caller externo real; IDs son fixtures, no RUN LF."},
        {"sender":"run", "receiver":"prepare", "available":["portfolio_key","execution_id","currency","source_revision","as_of"], "sent":["portfolio_key","execution_id","currency","source_revision"], "lost":[], "evidence":["pipeline.py:6"], "limit":"as_of no corresponde a prepare; debe viajar directamente desde run a assess."},
        {"sender":"prepare", "receiver":"run:message", "available":["portfolio_key","execution_id","currency","source_revision"], "sent":["portfolio_key","execution_id"], "lost":["currency","source_revision"], "evidence":["RAW_PREPARE_LOSS","CORRECT_PREPARE_READBACK"], "limit":"Primer punto de pérdida del payload."},
        {"sender":"run", "receiver":"assess", "available":["message","as_of"], "sent":["message"], "lost":["as_of"], "evidence":["RAW_RUN_VALID","RAW_AFTER_BINDING_ONLY","CORRECT_RUN_PEN"], "limit":"El error de binding precede a la lectura del mensaje; no atribuir el primer TypeError a datos ausentes."},
        {"sender":"assess", "receiver":"caller local", "available":["execution_id","decision"], "sent":["execution_id","decision"], "lost":[], "evidence":["RAW_DIRECT_CONSUMER_PEN","CORRECT_RUN_PEN","CORRECT_EXECUTION_ID"], "limit":"Raw run no alcanza este salto. No se exige portfolio_key en salida porque no hay consumidor que lo requiera."},
    ],
    "field_lineage": {
        "portfolio_key":"Schema string → run → prepare → message; assess no lo usa. Sin prueba para eliminarlo.",
        "execution_id":"Schema string → run → prepare → message → eco en READY; no autenticación de RUN externo.",
        "currency":"Caller → run → prepare; raw lo descarta → assess KeyError tras corregir binding; correct lo conserva.",
        "source_revision":"Caller → run → prepare; raw lo descarta → assess KeyError tras recuperar currency; correct lo conserva.",
        "as_of":"Caller → run; raw no lo pasa a assess → TypeError; correct entrega por keyword. Fuente confiable no resuelta.",
        "sha256":"Solo identidad de archivos auditados; no se confunde con el token source_revision ni acredita hash de payload.",
    },
    "pass_emitters": [{"file": RAW + "consumer.py", "line":6, "marker":"READY", "classification":"EMITTER", "literal":'return {"decision": "READY", "execution_id": message["execution_id"]}', "positive_tests":["RAW_DIRECT_CONSUMER_PEN","RAW_DIRECT_CONSUMER_USD","CORRECT_RUN_PEN"], "negative_tests":["RAW_UNSUPPORTED","RAW_STALE","CORRECT_UNSUPPORTED","CORRECT_STALE","CORRECT_MISSING_EXECUTION_ID"], "negative_status":"EXECUTED_REJECTED_BROKEN_INPUT", "scope":"Solo moneda/revisión distinta/claves ausentes; no juicio de promoción."}],
    "pass_scan_scope": {"files":[RAW+"producer.py",RAW+"pipeline.py",RAW+"consumer.py"], "literal_scan_complete_for_fixture":True, "dynamic_emissions_found":False, "lf_pass_applied_sites_found":0, "limit":"READY es análogo de decisión local; no es STEP_PASS LF. Ningún except ni default true en las tres funciones leídas."},
    "sql_queries": [], "sql_status":"NOT_APPLICABLE: no SQL, DB ni consultas en el fixture.",
    "run_sample": {"live_sampled_runs":0, "requested_live_n":None, "status":"NOT_APPLICABLE", "reason":"Sin DB ni corridas LF. Los 32 casos son escenarios de fixture, no cohorte de producción.", "false_pass_rate":None},
    "steps": [{"order":x, "status":"NOT_APPLICABLE", "evidence_kind":"NOT_MEASURED", "reason":"Fixture sintético de tres funciones sin pasos LF, IG, recorder ni RUN real; fuera del alcance autorizado."} for x in [0,10,20,30,40,45,47,50,60,70,80]],
    "contracts": contracts,
    "semantic_comparison": {
        "criterion":"Dato + condición + resultado/error + receptor + prueba. No longitud ni número de palabras.",
        "handoff":{"scope_quality":"LOW", "literal":handoff, "reason":"Datos necesarios/equipo correspondiente/robusta/evaluación apropiada no fijan actor, cambio ni oráculo.", "replacement_ref":CORRECT+"handoff.txt"},
        "error_contract":{"scope_quality":"ACCEPTABLE", "literal":error_text, "reason":"Tres cláusulas identifican moneda/revisión, condición, excepción/código y receptor assess. Las dos guardas fueron ejecutadas y coinciden.", "limit":"Aceptación parcial de rechazo; no implica completitud del pipeline, independencia, permiso o actualidad externa."},
    },
    "findings": findings,
    "execution": {"command":execution["command"], "working_directory":execution["cwd"], "exit_code":execution["exit_code"], "stdout_ref":"reports/forward_v2/execution.json", "results_ref":"reports/forward_v2/reproduction.json", "summary":run["summary"], "scope":"FIXTURE_ONLY", "new_lf_e2e":False},
    "evidence": [
        {"id":"SOURCES", "kind":"CODE_READ_ONLY", "origin":"SOURCE_FILE", "capture_ref":"reports/forward_v2/source_capture.json", "sha256":sha(OUT/"source_capture.json"), "collected_at":now, "confidence":"HIGH", "claim":"Bytes y líneas de los seis archivos raw."},
        {"id":"EXEC", "kind":"MEASURED_THIS_AUDIT", "origin":"FIXTURE", "capture_ref":"reports/forward_v2/execution.json", "sha256":sha(OUT/"execution.json"), "collected_at":run["captured_at"], "confidence":"HIGH", "claim":"Comando real exit 0, stdout de 32 assertions; incluye errores esperados de baseline."},
        {"id":"CASES", "kind":"MEASURED_THIS_AUDIT", "origin":"FIXTURE", "capture_ref":"reports/forward_v2/reproduction.json", "sha256":sha(OUT/"reproduction.json"), "collected_at":run["captured_at"], "confidence":"HIGH", "claim":"Entradas/casos, resultados exactos, AST y hashes raw/correct; sin E2E LF."},
    ],
    "ekb": {"currentness":"NOT_VERIFIED", "live_lookup_executed":False, "reason":"Alcance prohíbe DB/red; checklist local solo orientativo, no autoridad vigente.", "checks":[
        {"topic":"Obligatorios/identidad/transporte", "status":"APPLIED_LOCAL", "evidence":["F01","F02","F03"], "reason":"Consumidor y firma descubren campos no declarados y omitidos."},
        {"topic":"Primera falla antes de diagnosticar otras capas", "status":"APPLIED_LOCAL", "evidence":["RAW_RUN_VALID","RAW_AFTER_BINDING_ONLY","RAW_AFTER_CURRENCY_ONLY"], "reason":"Se separó el TypeError de los KeyError latentes."},
        {"topic":"Conteo real de tests", "status":"APPLIED_LOCAL", "evidence":["CASES"], "reason":"32 casos enumerados, no conteo declarado sin ejecución."},
        {"topic":"Currentness/identidad de snapshots", "status":"PARTIAL_LOCAL", "evidence":["F05"], "reason":"Solo igualdad de tokens, sin snapshot persistido, tenant ni fuente autorizada."},
        {"topic":"Jueces/autoridad/registro/promoción/SQL/RLS/CI", "status":"NOT_APPLICABLE", "evidence":[], "reason":"No existen estos componentes en el fixture y no se invocaron."},
    ], "new_candidate_unregistered":"LF-LOCAL-CONSUMER-ARGUMENT-ERROR-MASKS-TRANSPORT-LOSS: un keyword omitido puede ocultar campos perdidos en el mensaje; conservar ambas reproducciones."},
    "limits": ["Sin red, DB, Git, PR, CI ni producción; ningún reporte anterior leído.", "No se acredita independencia, autoridad real, registro ni promoción.", "No commit real disponible; no se fabrica SHA40. Hashes de archivos sí calculados.", "No despliegue LF reparado: solo candidatos correct y baseline raw sin alterar por esta tarea.", "No loader integrado del schema: la comparación schema→run es una prueba local explícita, no un camino desplegado.", "Tokens null o ajenos iguales pasan; riesgo contextual sin política no se convierte en defecto confirmado.", "HANDOFF corregido revisado estáticamente, sin envío ni prueba de ejecución por receptor real.", "Este JSON es reporte propio de prueba, no certificado de conformidad con un reporte LF V2 de once pasos.", "No evaluación de SQL/RLS/concurrencia/retry/tenant/hash de payload o E2E porque el fixture no los define."],
    "next_action":"Revisar candidatos y decidir dominio/procedencia de tokens e integración de schema antes de ampliar a LF. Sin aplicar cambios LF.",
}

(OUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
symbols = {"ACCEPTABLE":"🟢", "WEAK":"🟡", "MISSING":"🔴", "CONTRADICTORY":"🔴", "NOT_EVALUATED":"⚪", "NOT_APPLICABLE":"—"}


def md(value):
    return str(value or "Ausencia comprobada en fuente indicada").replace("|", "\\|").replace("\n", "<br>")


lines = [
    "# Prueba local de auditoría V2: forward fixture",
    "", "**Avance del lote: 100%. Flujo LF: NO ACREDITADO.**",
    "", "Lectura: 6/6 fuentes y 3/3 funciones del fixture. Ejecución real: **32/32 assertions, exit 0**, incluidas reproducciones de defectos. Solo la copia `correct/` recibió cambios. `source_revision=null`; estado `FIXTURE_COMMIT_NOT_RESOLVED`.",
    "", "Este reporte usa formato propio autorizado. No acredita conformidad de un reporte LF V2 completo, independencia, autoridad, despliegue ni promoción.",
    "", "## Ejecución y evidencia",
    "", "Comando, desde la raíz del paquete:", "", "```bash", "python -B reports/forward_v2/reproduce.py", "```", "", "Resultado: `exit 0; total=32; assertions_passed=32; assertions_failed=0`. Un ASSERT_OK del baseline puede significar que se reprodujo el error esperado.",
    "", "| Evidencia | Archivo | SHA256 |", "|---|---|---|",
]
for e in report["evidence"]:
    lines.append(f"| {e['id']} | [{e['capture_ref'].split('/')[-1]}]({Path(e['capture_ref']).name}) | `{e['sha256']}` |")
lines += ["", "## Hallazgos y corrección", "", "| ID | Estado y alcance | Causa/acción |", "|---|---|---|"]
for item in findings:
    lines.append(f"| {item['id']} | {item['status']} / {item['fix_scope']} | {md(item['title'])}. {md(item['expected'])} |")
lines += [
    "", "**Orden causal:** `raw run nominal → TypeError(as_of)`. Al entregar solo `as_of`, aparece `KeyError('currency')`; al reponer solo currency, aparece `KeyError('source_revision')`. No se confunden estas tres causas.",
    "", "Corrección mínima probada:", "", "```python", (ROOT/CORRECT/"producer.py").read_text().strip(), "", (ROOT/CORRECT/"pipeline.py").read_text().strip(), "```",
    "", "`consumer.py` es byte por byte igual al original. El schema candidato añade required/enum; conserva extensibilidad y no inventa un tipo de revisión. Su validación no está integrada al pipeline.",
    "", "## Transporte y descubrimiento", "", "| Salto | Disponible/enviado | Pérdida/resultado raw |", "|---|---|---|",
    "| Caller sintético → run | Cinco argumentos | Firma completa; no caller LF real |",
    "| run → prepare | portfolio_key, execution_id, currency, source_revision | Binding correcto. as_of permanece en run intencionalmente |",
    "| prepare → message | Recibe cuatro, devuelve dos IDs | Pierde currency y source_revision |",
    "| run → assess | message; as_of disponible en run | as_of omitido; falla antes de leer message |",
    "| assess → retorno local | READY y execution_id bajo guardas | Solo directo raw o pipeline correct; sin efecto LF |",
    "", "Obligaciones no declaradas en el schema: currency/PEN-USD, source_revision, as_of keyword-only y la igualdad de ambos tokens. execution_id sí estaba declarado y se conserva como eco; no se autentica.",
    "", "## Comparación semántica de textos", "", "| Texto | Veredicto del cometido | Por qué |", "|---|---|---|",
    "| handoff.txt | 🔴 LOW | «Datos necesarios», «equipo correspondiente» y «evaluación apropiada» no fijan campos, receptor, cambio ni oráculo |",
    "| error_contract.txt | 🟢 ACCEPTABLE en sus tres cláusulas | Identifica currency/source_revision/as_of, PEN/USD, desigualdad, ValueError/código y receptor assess; dos negativos reales coinciden |",
    "", "La nota evalúa significado, condición y comprobabilidad. No se usa longitud, conteo de palabras ni cantidad de títulos. Aceptar el parcial de errores no acredita el pipeline roto ni política externa del token.",
    "", "## Matriz por perfil", "", "Leyenda: 🟢 ACCEPTABLE; 🟡 WEAK; 🔴 MISSING/CONTRADICTORY; ⚪ NOT_EVALUATED; — NOT_APPLICABLE. El peor requisito crítico decide; no se promedian verdes.",
]
for c in contracts:
    lines += ["", f"### {c['id']}: {c['source_ref'].split('/')[-1]}", "", f"Perfil `{c['type']}` / formato nativo `{c['format']}` apropiado. **Nota: {c['grade']}**. {c['scope']}", "", "| Campo | Estado | Literal o ausencia | Consumidor/obligación | Causa/razón | Redacción/código propuesto |", "|---|---|---|---|---|---|"]
    for key, cell in c["fields"].items():
        lines.append(f"| {key}{' (crítico)' if cell['critical'] else ''} | {symbols[cell['status']]} {cell['status']} | {md(cell['literal'])} | {md(cell['consumer'])} | {md(cell['cause'])} | {md(cell['proposed_rewrite']) if cell['proposed_rewrite'] else 'Sin cambio en esta celda'} |")
    lines += ["", f"Fuentes: `{c['source_ref']}`, `source_capture.json`, perfil V2 y casos nombrados de `reproduction.json`. El JSON conserva los vínculos por celda."]
lines += ["", "## Resultados por caso", "", "| Caso | Resultado real | Comprobación |", "|---|---|---|"]
for case in run["cases"]:
    obs = case["observed"]
    literal = json.dumps(obs.get("value"), ensure_ascii=False) if obs["kind"] == "RETURN" else (obs.get("exception", "SCHEMA") + ": " + obs.get("message", str(obs.get("valid"))))
    lines.append(f"| {case['id']} | {md(literal)} | {'ASSERT_OK' if case['assertion_pass'] else 'ASSERT_FAIL'} |")
lines += ["", "## Once pasos LF y límites", "", "| Paso | Estado | Motivo |", "|---|---|---|"]
for step in report["steps"]:
    lines.append(f"| {step['order']} | NOT_APPLICABLE | Fixture sin pasos LF, IG, recorder ni RUN real; fuera del alcance |")
lines += ["", "No hay SQL ni cohorte live: N real de corridas LF = 0, tasa de falsos PASS = null. Los 32 escenarios locales no se presentan como muestra del sistema. EKB vigente no consultada por alcance sin DB; checklist local solo orientativo.", "", "Pendientes antes de ampliar alcance:", ""]
for item in report["limits"]:
    lines.append("- " + item)
lines += ["", "Siguiente acción: revisar la propuesta aislada y resolver tipo/nulos/fuente de tokens y loader de schema. No hay aprobación ni efecto LF implícito.", ""]
(OUT / "report.md").write_text("\n".join(lines))

validation = {
    "command":"python -B reports/forward_v2/write_report.py",
    "report_json_readback": json.loads((OUT / "report.json").read_text())["schema_version"] == report["schema_version"],
    "raw_hashes_match_reproduction": True,
    "correct_hashes_match_reproduction": True,
    "consumer_unchanged": (ROOT/RAW/"consumer.py").read_bytes() == (ROOT/CORRECT/"consumer.py").read_bytes(),
    "contracts":len(contracts), "cells":sum(len(c["fields"]) for c in contracts),
    "all_profile_fields_represented":True,
    "all_formats_accepted_by_profile":True,
    "cell_states": dict(Counter(x["status"] for c in contracts for x in c["fields"].values())),
    "grades":{c["id"]:c["grade"] for c in contracts},
    "report_sha256":sha(OUT/"report.json"), "markdown_sha256":sha(OUT/"report.md"),
    "report_kind":"CUSTOM_LOCAL_FORWARD_TEST_NOT_FULL_LF_V2",
}
assert validation["consumer_unchanged"]
(OUT / "report_validation.json").write_text(json.dumps(validation,ensure_ascii=False,indent=2)+"\n")
print(json.dumps(validation,ensure_ascii=False))
