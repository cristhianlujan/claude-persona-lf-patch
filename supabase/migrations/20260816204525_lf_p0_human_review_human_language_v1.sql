-- Human Review human-language presentation contract v1.
-- Presentation-only: does not mutate OCR/reader evidence, classifications, confidence, regions, or adjudication state.
CREATE OR REPLACE FUNCTION private.fn_lf_p0_human_review_human_language_v1(p_html text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, public, private, extensions
AS $$
DECLARE
  v_script text;
BEGIN
  IF p_html IS NULL OR btrim(p_html) = '' THEN
    RAISE EXCEPTION 'BROWSER_REVIEW_HTML_REQUIRED';
  END IF;
  IF position('id="p0-human-language-v1"' in p_html) > 0 THEN
    RETURN p_html;
  END IF;
  IF position('</body>' in p_html) = 0 THEN
    RAISE EXCEPTION 'BROWSER_REVIEW_BODY_END_MISSING';
  END IF;

  v_script := $human_language$
<script id="p0-human-language-v1" data-contract="p0-human-review-human-language/v1">
(()=>{
  const TYPE_LABELS=Object.freeze({
    ICON_OR_GLYPH:"Icono o símbolo visual",TEXT:"Texto visible",CONTROL:"Control de interfaz",
    CONTAINER:"Contenedor visual",DECORATION:"Elemento decorativo",IMAGE:"Imagen",
    SHAPE:"Forma visual",DIVIDER:"Separador",BUTTON:"Botón",INPUT:"Campo de entrada",
    SELECT:"Selector",CHECKBOX:"Casilla de selección",RADIO:"Opción de selección",LINK:"Enlace"
  });
  const ROLE_LABELS=Object.freeze({
    VISIBLE_COPY:"Contenido visible",visible_copy:"Contenido visible",material_icon:"Icono visual",
    control_visual_affordance:"Elemento visual asociado a un control",
    text_overlap_visual_fragment:"Fragmento visual solapado con texto",
    button:"Botón",input:"Campo de entrada",select:"Selector",label:"Etiqueta visible",
    heading:"Encabezado",body_copy:"Texto informativo",navigation:"Navegación"
  });
  const UNCERTAINTY_LABELS=Object.freeze({
    ICON_FUNCTION_NOT_OBSERVABLE:"no se pudo determinar la función del icono",
    TEXT_OVERLAP_NO_INDEPENDENT_ICON_FUNCTION:"el elemento se solapa con texto y no se trata como un icono funcional independiente",
    OCR_DISAGREEMENT:"las lecturas de texto no coinciden",
    LOW_CONFIDENCE:"la confianza del sistema es baja",
    NOT_OBSERVABLE:"la evidencia visual no permite observar el dato"
  });
  const known=(map,v)=>v!=null&&Object.prototype.hasOwnProperty.call(map,String(v));
  const typeLabel=e=>known(TYPE_LABELS,e?.element_type)?TYPE_LABELS[String(e.element_type)]:"Elemento visual";
  const roleLabel=e=>known(ROLE_LABELS,e?.semantic_role)?ROLE_LABELS[String(e.semantic_role)]:known(ROLE_LABELS,e?.subcomponent_role)?ROLE_LABELS[String(e.subcomponent_role)]:"Interpretación visual del sistema";
  const statusLabel=e=>e?._review?.classification==='CONFIRMED'||e?.classification==='CONFIRMED'?"Confirmado":e?._review?.classification==='INFERRED'||e?.classification==='INFERRED'?"Inferido":e?._review?.classification==='NOT_OBSERVABLE'||e?.classification==='NOT_OBSERVABLE'?"No observable":"Estado no especificado";
  const confidenceInfo=e=>{let c=Number(e?.confidence);if(!Number.isFinite(c))return {percent:null,level:"no disponible",summary:"Confianza no disponible"};if(c<=1)c*=100;c=Math.max(0,Math.min(100,c));const level=c>=85?"alta":c>=65?"media":"baja";return {percent:c,level,summary:`${c.toFixed(c>=99?0:1)}% · confianza ${level}`};};
  const isInternalCode=v=>typeof v==='string'&&v.includes('_')&&/^[A-Z0-9_]+$/.test(v);
  const displayText=e=>{const raw=e?._display_text??e?.visible_text??e?.ocr_consensus_text??e?.text??e?.label??"";if(known(ROLE_LABELS,raw))return ROLE_LABELS[String(raw)];if(known(TYPE_LABELS,raw))return TYPE_LABELS[String(raw)];if(isInternalCode(raw))return "Descripción técnica disponible en el detalle avanzado";return String(raw||typeLabel(e));};
  const detectedSummary=e=>{const t=typeLabel(e);if(e?.element_type==='ICON_OR_GLYPH')return "Se detectó un icono o símbolo visual.";if(e?.element_type==='TEXT')return "Se detectó texto visible.";if(e?.element_type==='CONTROL'||['BUTTON','INPUT','SELECT','CHECKBOX','RADIO','LINK'].includes(String(e?.element_type||'')))return `Se detectó un ${t.toLowerCase()}.`;return `Se detectó: ${t.toLowerCase()}.`;};
  const interpretationSummary=e=>{const cls=e?._review?.classification||e?.classification||"";let base=known(ROLE_LABELS,e?.semantic_role)?`El sistema lo interpreta como ${roleLabel(e).toLowerCase()}.`:"El sistema no proporciona una interpretación semántica suficientemente clara.";if(e?.element_type==='ICON_OR_GLYPH'&&!['material_icon','control_visual_affordance'].includes(String(e?.semantic_role||'')))base+=" No identifica con certeza qué representa el icono.";if(cls==='INFERRED')base+=" Esta interpretación es inferida: no está confirmada directamente por la evidencia.";else if(cls==='NOT_OBSERVABLE')base+=" La evidencia no permite determinarla con suficiente certeza.";else if(cls==='CONFIRMED')base+=" La interpretación está marcada como confirmada por la evidencia disponible.";return base;};
  const uncertaintySummary=e=>{const items=e?._explicit_uncertainties||[];if(!items.length)return "";const labels=[...new Set(items.map(x=>UNCERTAINTY_LABELS[String(x?.code||'')]||"existe una incertidumbre técnica registrada"))];return `Motivo de atención: ${labels.join('; ')}.`;};
  const reviewInstruction=e=>{const cls=e?._review?.classification||e?.classification||"";const c=confidenceInfo(e);if(e?._review?.problem)return "Revisa el problema material señalado antes de decidir.";if(e?._review?.omission)return "Comprueba si falta un elemento visible en la representación del sistema.";if(cls==='NOT_OBSERVABLE')return "Comprueba si este dato realmente puede determinarse con la evidencia visible; si no, solicita contexto o una nueva captura.";if(cls==='INFERRED'||c.level==='baja'||(e?._explicit_uncertainties||[]).length)return "Comprueba visualmente qué representa el elemento y si la interpretación del sistema corresponde. Si no coincide, corrígela.";return "Verifica que la lectura y su relación con la fuente sean correctas.";};
  const present=e=>{const c=confidenceInfo(e);return {typeLabel:typeLabel(e),roleLabel:roleLabel(e),statusLabel:statusLabel(e),confidenceSummary:c.summary,display:displayText(e),detected:detectedSummary(e),interpretation:interpretationSummary(e),uncertainty:uncertaintySummary(e),reviewInstruction:reviewInstruction(e)};};
  const escHuman=v=>String(v??"").replace(/[&<>"']/g,ch=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[ch]));

  function patchCanonicalV42(){
    if(typeof E==='undefined'||!Array.isArray(E)||typeof renderDetail!=='function'||typeof renderRows!=='function')return false;
    const originalDetail=renderDetail;
    renderDetail=function(){
      originalDetail();
      const e=E[selected];if(!e)return;const p=present(e);
      const setText=(sel,value)=>{const n=document.querySelector(sel);if(n)n.textContent=value;};
      setText('#selected-semantic',`Tipo: ${p.typeLabel}`);
      setText('#selected-text',p.display);
      setText('#selected-confidence',p.confidenceSummary);
      setText('#selected-role',p.interpretation);
      const group=document.querySelector('#selected-group');if(group)group.textContent=`${p.roleLabel}${e.parent_id?` · relacionado con ${e.parent_id}`:''}`;
      const note=document.querySelector('#review-note');if(note)note.textContent=[p.reviewInstruction,p.uncertainty].filter(Boolean).join(' ');
      const sys=document.querySelector('#system-reading');if(sys)sys.innerHTML=`<strong>${escHuman(p.detected)}</strong><br>${escHuman(p.interpretation)}<br><span class="evidence-meta">${escHuman(p.confidenceSummary)}</span>`;
      setText('#system-meta',`Qué revisar: ${p.reviewInstruction}`);
      const sem=document.querySelector('#tab-semantic');if(sem&&typeof kv==='function')sem.innerHTML=kv('Tipo',p.typeLabel)+kv('Rol',p.roleLabel)+kv('Clasificación',p.statusLabel)+kv('Confianza',p.confidenceSummary)+kv('Texto / descripción',p.display);
    };
    const originalRows=renderRows;
    renderRows=function(){
      originalRows();
      document.querySelectorAll('#element-list tbody tr[data-index]').forEach(row=>{const i=Number(row.dataset.index);const e=E[i];if(!e)return;const p=present(e);const cells=row.querySelectorAll('td');if(cells[1])cells[1].textContent=p.typeLabel;if(cells[2])cells[2].textContent=p.display;if(cells[4])cells[4].textContent=p.confidenceSummary;if(cells[5]&&((e._review?.classification==='INFERRED')||confidenceInfo(e).level==='baja'||(e._explicit_uncertainties||[]).length))cells[5].innerHTML='<span class="attention-dot"></span>Revisar interpretación';});
    };
    renderRows();
    return true;
  }

  function patchConvergenceShell(){
    if(typeof els==='undefined'||!Array.isArray(els)||typeof select!=='function')return false;
    select=function(e){
      const p=present(e);const target=document.getElementById('detail-panel');if(!target)return;target.replaceChildren();
      [['Elemento',e.element_id||'—'],['Qué detectó',p.detected],['Interpretación',p.interpretation],['Estado',p.statusLabel],['Confianza',p.confidenceSummary],['Qué revisar',p.reviewInstruction],['Atención',p.uncertainty||'Sin incertidumbres explícitas']].forEach(([k,v])=>{const line=document.createElement('div');const strong=document.createElement('strong');strong.textContent=k+': ';line.append(strong,document.createTextNode(v));line.style.margin='7px 0';target.appendChild(line);});
    };
    document.querySelectorAll('#element-list .item').forEach((row,i)=>{const e=els[i];if(!e)return;const p=present(e);row.textContent=`${e.element_id||''} · ${p.typeLabel} · ${p.display} · ${p.statusLabel} · ${p.confidenceSummary}`;});
    return true;
  }

  const applied=patchCanonicalV42()||patchConvergenceShell();
  document.documentElement.dataset.humanLanguageContract="p0-human-review-human-language/v1";
  window.__P0_HUMAN_LANGUAGE_V1__=Object.freeze({contract:"p0-human-review-human-language/v1",applied,present});
})();
</script>
$human_language$;
  RETURN replace(p_html, '</body>', v_script || '</body>');
END;
$$;

CREATE OR REPLACE FUNCTION private.fn_lf_p0_enforce_human_language_browser_review_v1()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, private, extensions
AS $$
DECLARE
  v_html text;
  v_upgraded text;
BEGIN
  IF NEW.object_role <> 'BROWSER_REVIEW' THEN
    RETURN NEW;
  END IF;
  IF NEW.mime_type <> 'text/html' THEN
    RAISE EXCEPTION 'BROWSER_REVIEW_MIME_INVALID';
  END IF;
  v_html := convert_from(NEW.content, 'UTF8');
  v_upgraded := private.fn_lf_p0_human_review_human_language_v1(v_html);
  IF v_upgraded <> v_html THEN
    NEW.content := convert_to(v_upgraded, 'UTF8');
    NEW.content_bytes := octet_length(NEW.content);
    NEW.content_sha256 := encode(extensions.digest(NEW.content, 'sha256'), 'hex');
    NEW.metadata := coalesce(NEW.metadata, '{}'::jsonb) || jsonb_build_object(
      'human_language_contract','p0-human-review-human-language/v1',
      'human_language_presentation_only',true,
      'raw_technical_codes_preserved',true
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lf_p0_human_language_browser_review_v1 ON private.lf_p0_review_evidence_objects_v1;
CREATE TRIGGER trg_lf_p0_human_language_browser_review_v1
BEFORE INSERT ON private.lf_p0_review_evidence_objects_v1
FOR EACH ROW
WHEN (NEW.object_role = 'BROWSER_REVIEW')
EXECUTE FUNCTION private.fn_lf_p0_enforce_human_language_browser_review_v1();

REVOKE ALL ON FUNCTION private.fn_lf_p0_human_review_human_language_v1(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_lf_p0_enforce_human_language_browser_review_v1() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_lf_p0_human_review_human_language_v1(text) TO service_role;

COMMENT ON FUNCTION private.fn_lf_p0_human_review_human_language_v1(text) IS
'Presentation-only Human Review contract. Converts internal visual taxonomy/status/confidence into reviewer-facing Spanish, keeps raw codes in advanced technical evidence, and is idempotently injected into every persisted BROWSER_REVIEW.';

-- Migration-level regression: contract marker, mappings, idempotency and design preservation.
DO $$
DECLARE
  v_input text := '<!doctype html><html lang="es" data-review-shell-version="4.2"><body><div id="element-list"></div><div id="detail-panel"></div></body></html>';
  v_output text;
BEGIN
  v_output := private.fn_lf_p0_human_review_human_language_v1(v_input);
  IF position('id="p0-human-language-v1"' in v_output) = 0 THEN RAISE EXCEPTION 'HUMAN_LANGUAGE_CONTRACT_MARKER_MISSING'; END IF;
  IF position('ICON_OR_GLYPH:"Icono o símbolo visual"' in v_output) = 0 THEN RAISE EXCEPTION 'HUMAN_LANGUAGE_ICON_MAPPING_MISSING'; END IF;
  IF position('VISIBLE_COPY:"Contenido visible"' in v_output) = 0 THEN RAISE EXCEPTION 'HUMAN_LANGUAGE_VISIBLE_COPY_MAPPING_MISSING'; END IF;
  IF position('c>=85?"alta":c>=65?"media":"baja"' in v_output) = 0 THEN RAISE EXCEPTION 'HUMAN_LANGUAGE_CONFIDENCE_CONTEXT_MISSING'; END IF;
  IF position('Esta interpretación es inferida: no está confirmada directamente por la evidencia.' in v_output) = 0 THEN RAISE EXCEPTION 'HUMAN_LANGUAGE_INFERRED_EXPLANATION_MISSING'; END IF;
  IF position('Comprueba visualmente qué representa el elemento' in v_output) = 0 THEN RAISE EXCEPTION 'HUMAN_LANGUAGE_REVIEW_INSTRUCTION_MISSING'; END IF;
  IF private.fn_lf_p0_human_review_human_language_v1(v_output) <> v_output THEN RAISE EXCEPTION 'HUMAN_LANGUAGE_NOT_IDEMPOTENT'; END IF;
  IF position('data-review-shell-version="4.2"' in v_output) = 0 THEN RAISE EXCEPTION 'HUMAN_LANGUAGE_V42_DESIGN_MARKER_LOST'; END IF;
END;
$$;