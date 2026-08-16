-- Human Review icon hypothesis + OCR evidence presentation contract v2.
-- Presentation-only: does not mutate OCR/reader evidence, classifications, confidence,
-- semantic fingerprint, regions, adjudication state, or promotion state.

CREATE OR REPLACE FUNCTION private.fn_lf_p0_human_review_human_language_v2(p_html text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog, public, private, extensions
AS $$
DECLARE
  v_base text;
  v_script text;
BEGIN
  IF p_html IS NULL OR btrim(p_html) = '' THEN
    RAISE EXCEPTION 'BROWSER_REVIEW_HTML_REQUIRED';
  END IF;
  IF position('id="p0-human-language-v2"' in p_html) > 0 THEN
    RETURN p_html;
  END IF;
  IF position('</body>' in p_html) = 0 THEN
    RAISE EXCEPTION 'BROWSER_REVIEW_BODY_END_MISSING';
  END IF;

  v_base := private.fn_lf_p0_human_review_human_language_v1(p_html);

  v_script := $human_language_v2$
<script id="p0-human-language-v2" data-contract="p0-human-review-human-language/v2">
(()=>{
  const norm=v=>String(v??'').replace(/\s+/g,' ').trim();
  const isIcon=e=>['ICON','ICON_OR_GLYPH'].includes(String(e?.element_type||''))||['material_icon','control_visual_affordance'].includes(String(e?.semantic_role||''));
  const allElements=()=>typeof E!=='undefined'&&Array.isArray(E)?E:(typeof els!=='undefined'&&Array.isArray(els)?els:[]);
  const reg=e=>e?.region||{};
  const hasRegion=e=>['x','y','width','height'].every(k=>Number.isFinite(Number(reg(e)[k])))&&Number(reg(e).width)>0&&Number(reg(e).height)>0;
  const center=e=>({x:Number(reg(e).x)+Number(reg(e).width)/2,y:Number(reg(e).y)+Number(reg(e).height)/2});
  const contains=(outer,inner)=>{if(!hasRegion(outer)||!hasRegion(inner))return false;const c=center(inner),r=reg(outer);return c.x>=Number(r.x)&&c.x<=Number(r.x)+Number(r.width)&&c.y>=Number(r.y)&&c.y<=Number(r.y)+Number(r.height);};
  const area=e=>hasRegion(e)?Number(reg(e).width)*Number(reg(e).height):Number.POSITIVE_INFINITY;
  const dist=(a,b)=>{if(!hasRegion(a)||!hasRegion(b))return Number.POSITIVE_INFINITY;const A=center(a),B=center(b);return Math.hypot(A.x-B.x,A.y-B.y);};
  const rawText=e=>norm(e?.visible_text||e?.ocr_consensus_text||e?.text||e?.label||'');

  const ocrVariantStats=e=>{
    const values=[];
    if(Array.isArray(e?.ocr_variants))values.push(...e.ocr_variants);
    if(e?.ocr_consensus_text)values.push(e.ocr_consensus_text);
    if(e?.visible_text)values.push(e.visible_text);
    const counts=new Map();
    values.map(norm).filter(Boolean).forEach(v=>counts.set(v,(counts.get(v)||0)+1));
    return [...counts.entries()].map(([text,count])=>({text,count})).sort((a,b)=>b.count-a.count||a.text.length-b.text.length||a.text.localeCompare(b.text));
  };

  const compactPrefix=e=>{
    const tokens=Array.isArray(e?.text_lineage?.source_tokens)?e.text_lineage.source_tokens.map(norm):[];
    const regions=Array.isArray(e?.text_lineage?.source_token_regions)?e.text_lineage.source_token_regions:[];
    if(!tokens.length||!/^\+\d{1,4}$/.test(tokens[0]))return null;
    const trailing=tokens.slice(1);
    if(!trailing.length)return {primary:tokens[0],adjacent:[],reason:'PREFIX_TOKEN'};
    const allGlyphLike=trailing.every((t,i)=>{
      const r=regions[i+1]||{};
      return t.length<=2&&Number(r.width||0)<=18&&Number(r.height||0)<=16;
    });
    return allGlyphLike?{primary:tokens[0],adjacent:trailing,reason:'PREFIX_WITH_ADJACENT_COMPACT_GLYPH'}:null;
  };

  const textEvidence=e=>{
    const stats=ocrVariantStats(e);
    const compact=compactPrefix(e);
    const consensus=norm(e?.ocr_consensus_text);
    const majority=stats[0]&&stats[0].count>=2?stats[0].text:'';
    const fallback=norm(e?.visible_text||e?._display_text||e?.text||e?.label||'');
    const primary=compact?.primary||majority||consensus||fallback||'Sin lectura textual estable';
    const variants=stats.map(x=>`${x.text}${x.count>1?` (${x.count} lecturas)`:''}`);
    const tokens=Array.isArray(e?.text_lineage?.source_tokens)?e.text_lineage.source_tokens.map(norm).filter(Boolean):[];
    return {primary,variants,tokens,compact,disagreement:stats.length>1,majorityCount:stats[0]?.count||0};
  };

  const controlFor=e=>{
    const all=allElements();
    if(e?.parent_id){const p=all.find(x=>x?.element_id===e.parent_id&&x?.element_type==='CONTROL_REGION');if(p)return p;}
    return all.filter(x=>x?.element_type==='CONTROL_REGION'&&contains(x,e)).sort((a,b)=>area(a)-area(b))[0]||null;
  };

  const labelForControl=id=>{
    if(!id)return '';
    const matches=allElements().filter(x=>x?.describes_control_id===id||x?.field_group_id===id).sort((a,b)=>{
      const pa=a?.semantic_role==='field_label'?0:a?.semantic_role==='control_label'?1:2;
      const pb=b?.semantic_role==='field_label'?0:b?.semantic_role==='control_label'?1:2;
      return pa-pb;
    });
    return rawText(matches[0]);
  };

  const nearestContext=e=>{
    const candidates=allElements().filter(x=>x!==e&&x?.element_type==='TEXT'&&rawText(x)&&hasRegion(x));
    const ranked=candidates.map(x=>({x,d:dist(e,x)})).filter(v=>v.d<=170).sort((a,b)=>a.d-b.d);
    return ranked[0]?.x?rawText(ranked[0].x):'';
  };

  const contextIdentity=text=>{
    const t=norm(text).toLowerCase();
    const rules=[
      [/correo|e-mail|email/,['Sobre / correo','correo electrónico']],
      [/celular|tel[eé]fono|m[oó]vil/,['Teléfono / celular','telefonía']],
      [/nombre|usuario|persona/,['Persona / usuario','identidad personal']],
      [/tipo de documento|n[uú]mero de documento|\bdni\b|documento/,['Documento / identificación','documento de identidad']],
      [/registro seguro/,['Escudo con verificación / registro seguro','registro seguro']],
      [/entidad regulada|regulad/,['Escudo / entidad regulada','regulación']],
      [/datos encriptados|cifrad/,['Candado / cifrado','cifrado']],
      [/informaci[oó]n est[aá] segura|datos est[aá]n protegidos|proteg|seguridad|seguro/,['Escudo o candado / seguridad','seguridad o protección']],
      [/ayuda/,['Signo de interrogación / ayuda','ayuda']],
      [/consulta segura y r[aá]pida|pocos minutos|r[aá]pida/,['Rayo / rapidez','rapidez']],
      [/sin compromiso/,['Persona / usuario','usuario']],
      [/verificar|continuar|siguiente/,['Flecha / avanzar','avance']]
    ];
    for(const [re,result] of rules)if(re.test(t))return {identity:result[0],context:result[1]};
    return null;
  };

  const declaredIconIdentity=e=>{
    const candidates=[e?.icon_identity_hypothesis,e?.icon_identity,e?.icon_name,e?.icon_candidate,e?.icon_semantics];
    for(const c of candidates){
      if(typeof c==='string'&&norm(c))return norm(c);
      if(c&&typeof c==='object'){
        const v=norm(c.label||c.name||c.identity||c.candidate||c.value||'');
        if(v)return v;
      }
    }
    return '';
  };

  const iconHypothesis=e=>{
    if(!isIcon(e))return null;
    const declared=declaredIconIdentity(e);
    if(declared)return {identity:declared,method:'DECLARED_READER',basis:'Identidad declarada por el lector visual.',context:'',identityConfidence:e?.icon_identity_confidence??null};
    const control=controlFor(e);
    const controlLabel=labelForControl(control?.element_id||'');
    const nearby=controlLabel||nearestContext(e);
    const mapped=contextIdentity(nearby);
    if(mapped)return {
      identity:mapped.identity,
      method:'CONTEXTUAL_NEIGHBORHOOD',
      basis:`Hipótesis inferida por contexto${nearby?` cercano «${nearby}»`:''}; no confirma la forma gráfica.`,
      context:mapped.context,
      identityConfidence:null
    };
    return {identity:'Identidad no determinada',method:'UNAVAILABLE',basis:'El sistema detectó un icono, pero no tiene evidencia suficiente para proponer su identidad.',context:'',identityConfidence:null};
  };

  const iconReading=e=>{
    const h=iconHypothesis(e);if(!h)return null;
    const detection=(typeof confidenceInfo==='function'?confidenceInfo(e).summary:`Confianza del elemento ${Number(e?.confidence||0)*100}%`);
    const identityScore=h.identityConfidence==null?'Sin score separado para identidad':`Confianza de identidad ${Number(h.identityConfidence)<=1?(Number(h.identityConfidence)*100).toFixed(1):Number(h.identityConfidence).toFixed(1)}%`;
    return {h,detection,identityScore};
  };

  const bestDisplay=e=>{
    if(isIcon(e)){
      const h=iconHypothesis(e);
      return h?.method==='UNAVAILABLE'?'Icono detectado · identidad no determinada':`Hipótesis: ${h?.identity||'identidad no determinada'}`;
    }
    if(e?.element_type==='TEXT')return textEvidence(e).primary;
    return typeof displayText==='function'?displayText(e):norm(e?._display_text||rawText(e)||e?.element_type||'Elemento visual');
  };

  const ocrHtml=e=>{
    const t=textEvidence(e);
    const variantText=t.variants.length?t.variants.join(' · '):'No hay variantes registradas';
    const tokenText=t.tokens.length?t.tokens.join(' · '):'No disponibles';
    const compact=t.compact?`Prefijo detectado: ${t.compact.primary}${t.compact.adjacent.length?` · glifo compacto adyacente separado para revisión: ${t.compact.adjacent.join(' ')}`:''}`:'';
    return {t,variantText,tokenText,compact};
  };

  function patchCanonicalV42(){
    if(typeof E==='undefined'||!Array.isArray(E)||typeof renderDetail!=='function'||typeof renderRows!=='function')return false;
    const previousDetail=renderDetail;
    renderDetail=function(){
      previousDetail();
      const e=E[selected];if(!e)return;
      const setText=(sel,value)=>{const n=document.querySelector(sel);if(n)n.textContent=value;};
      if(isIcon(e)){
        const r=iconReading(e);if(!r)return;
        setText('#selected-text',r.h.identity);
        setText('#selected-role',`Hipótesis del sistema: ${r.h.identity}. ${r.h.basis}`);
        setText('#selected-confidence',r.detection);
        const sys=document.querySelector('#system-reading');if(sys)sys.innerHTML=`<strong>Icono detectado.</strong><br>Hipótesis de identidad: ${escHuman(r.h.identity)}.<br><span class="evidence-meta">${escHuman(r.h.basis)} ${escHuman(r.identityScore)}. ${escHuman(r.detection)}.</span>`;
        setText('#system-meta','Qué revisar: compara la forma que ves con la hipótesis del sistema. Si no coincide, corrígela; la confianza del elemento no equivale a confianza de identidad.');
        const sem=document.querySelector('#tab-semantic');if(sem&&typeof kv==='function')sem.innerHTML=kv('Tipo','Icono o símbolo visual')+kv('Hipótesis de identidad',r.h.identity)+kv('Método',r.h.method)+kv('Base de inferencia',r.h.basis)+kv('Confianza de identidad',r.identityScore)+kv('Confianza del elemento',r.detection)+kv('Clasificación',typeof friendlyStatus==='function'?friendlyStatus(e._review?.classification):e._review?.classification||e.classification||'—');
        const note=document.querySelector('#review-note');if(note)note.textContent='La identidad del icono es una hipótesis separada de su detección. Compara la forma visible con la hipótesis y corrígela si tu lectura difiere.';
      }else if(e?.element_type==='TEXT'){
        const o=ocrHtml(e);
        setText('#selected-text',o.t.primary);
        const sys=document.querySelector('#system-reading');if(sys)sys.innerHTML=`<strong>Lectura principal: ${escHuman(o.t.primary)}</strong><br><span class="evidence-meta">${o.t.disagreement?'Existen lecturas OCR diferentes; se muestran para revisión.':'Las lecturas OCR son consistentes.'}</span>`;
        setText('#system-meta',o.compact||`Variantes OCR: ${o.variantText}`);
        const sem=document.querySelector('#tab-semantic');if(sem&&typeof kv==='function')sem.innerHTML=kv('Tipo','Texto visible')+kv('Lectura principal',o.t.primary)+kv('Clasificación',typeof friendlyStatus==='function'?friendlyStatus(e._review?.classification):e._review?.classification||e.classification||'—')+kv('Confianza',typeof confidenceInfo==='function'?confidenceInfo(e).summary:e.confidence||'—')+kv('Lecturas OCR observadas',o.variantText)+kv('Tokens detectados',o.tokenText)+(o.compact?kv('Separación de prefijo/glifo',o.compact):'');
        if(o.t.disagreement){const note=document.querySelector('#review-note');if(note)note.textContent='Las lecturas OCR no coinciden completamente. Usa la imagen y las variantes observadas para decidir cuál texto es correcto.';}
      }
    };

    const previousRows=renderRows;
    renderRows=function(){
      previousRows();
      document.querySelectorAll('#element-list tbody tr[data-index]').forEach(row=>{
        const i=Number(row.dataset.index),e=E[i];if(!e)return;
        const cells=row.querySelectorAll('td');
        if(cells[2])cells[2].textContent=bestDisplay(e);
        if(cells[5]){
          if(isIcon(e))cells[5].innerHTML='<span class="attention-dot"></span>Revisar hipótesis de icono';
          else if(e?.element_type==='TEXT'&&textEvidence(e).disagreement)cells[5].innerHTML='<span class="attention-dot"></span>Comparar lecturas OCR';
        }
      });
    };
    renderRows();
    return true;
  }

  function patchConvergenceShell(){
    if(typeof els==='undefined'||!Array.isArray(els)||typeof select!=='function')return false;
    const oldSelect=select;
    select=function(e){
      oldSelect(e);
      const target=document.getElementById('detail-panel');if(!target)return;
      if(isIcon(e)){
        const r=iconReading(e);if(!r)return;
        [['Hipótesis de identidad',r.h.identity],['Método',r.h.method],['Base',r.h.basis],['Confianza de identidad',r.identityScore],['Confianza del elemento',r.detection],['Qué revisar','Compara la forma visible con la hipótesis; si difiere, corrígela.']].forEach(([k,v])=>{const line=document.createElement('div');const strong=document.createElement('strong');strong.textContent=k+': ';line.append(strong,document.createTextNode(v));line.style.margin='7px 0';target.appendChild(line);});
      }else if(e?.element_type==='TEXT'){
        const o=ocrHtml(e);
        [['Lectura principal',o.t.primary],['Variantes OCR',o.variantText],['Tokens',o.tokenText],['Separación',o.compact||'No aplica']].forEach(([k,v])=>{const line=document.createElement('div');const strong=document.createElement('strong');strong.textContent=k+': ';line.append(strong,document.createTextNode(v));line.style.margin='7px 0';target.appendChild(line);});
      }
    };
    document.querySelectorAll('#element-list .item').forEach((row,i)=>{const e=els[i];if(e)row.textContent=`${e.element_id||''} · ${bestDisplay(e)}`;});
    return true;
  }

  const applied=patchCanonicalV42()||patchConvergenceShell();
  document.documentElement.dataset.humanLanguageContract='p0-human-review-human-language/v2';
  window.__P0_HUMAN_LANGUAGE_V2__=Object.freeze({contract:'p0-human-review-human-language/v2',applied,iconHypothesis,textEvidence,bestDisplay});
})();
</script>
$human_language_v2$;

  RETURN replace(v_base, '</body>', v_script || '</body>');
END;
$$;

CREATE OR REPLACE FUNCTION private.fn_lf_p0_enforce_human_language_browser_review_v2()
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
  v_upgraded := private.fn_lf_p0_human_review_human_language_v2(v_html);
  IF v_upgraded <> v_html THEN
    NEW.content := convert_to(v_upgraded, 'UTF8');
    NEW.content_bytes := octet_length(NEW.content);
    NEW.content_sha256 := encode(extensions.digest(NEW.content, 'sha256'), 'hex');
    NEW.metadata := coalesce(NEW.metadata, '{}'::jsonb) || jsonb_build_object(
      'human_language_contract','p0-human-review-human-language/v2',
      'human_language_presentation_only',true,
      'raw_technical_codes_preserved',true,
      'icon_identity_hypothesis_review_only',true,
      'icon_identity_hypothesis_method','DECLARED_OR_CONTEXTUAL_NEIGHBORHOOD',
      'icon_identity_confidence_separate_from_detection',true,
      'ocr_variants_visible',true,
      'compact_prefix_glyph_separation_visible',true
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lf_p0_human_language_browser_review_v1 ON private.lf_p0_review_evidence_objects_v1;
DROP TRIGGER IF EXISTS trg_lf_p0_human_language_browser_review_v2 ON private.lf_p0_review_evidence_objects_v1;
CREATE TRIGGER trg_lf_p0_human_language_browser_review_v2
BEFORE INSERT ON private.lf_p0_review_evidence_objects_v1
FOR EACH ROW
WHEN (NEW.object_role = 'BROWSER_REVIEW')
EXECUTE FUNCTION private.fn_lf_p0_enforce_human_language_browser_review_v2();

REVOKE ALL ON FUNCTION private.fn_lf_p0_human_review_human_language_v2(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.fn_lf_p0_enforce_human_language_browser_review_v2() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.fn_lf_p0_human_review_human_language_v2(text) TO service_role;

COMMENT ON FUNCTION private.fn_lf_p0_human_review_human_language_v2(text) IS
'Presentation-only Human Review v2 contract. Shows reviewer-facing icon identity hypotheses separately from detection confidence, states the inference basis, exposes OCR variants/tokens, and separates compact prefixes such as +51 from adjacent glyph-like tokens without mutating source evidence.';

DO $$
DECLARE
  v_input text := '<!doctype html><html lang="es" data-review-shell-version="4.2"><body><div id="element-list"></div><div id="detail-panel"></div></body></html>';
  v_output text;
BEGIN
  v_output := private.fn_lf_p0_human_review_human_language_v2(v_input);
  IF position('id="p0-human-language-v1"' in v_output) = 0 THEN RAISE EXCEPTION 'HUMAN_LANGUAGE_V1_LOST'; END IF;
  IF position('id="p0-human-language-v2"' in v_output) = 0 THEN RAISE EXCEPTION 'HUMAN_LANGUAGE_V2_MARKER_MISSING'; END IF;
  IF position('Hipótesis de identidad' in v_output) = 0 THEN RAISE EXCEPTION 'ICON_IDENTITY_HYPOTHESIS_UI_MISSING'; END IF;
  IF position('CONTEXTUAL_NEIGHBORHOOD' in v_output) = 0 THEN RAISE EXCEPTION 'ICON_CONTEXT_METHOD_MISSING'; END IF;
  IF position('Sobre / correo' in v_output) = 0 THEN RAISE EXCEPTION 'ICON_EMAIL_CONTEXT_MAPPING_MISSING'; END IF;
  IF position('Teléfono / celular' in v_output) = 0 THEN RAISE EXCEPTION 'ICON_PHONE_CONTEXT_MAPPING_MISSING'; END IF;
  IF position('no confirma la forma gráfica' in v_output) = 0 THEN RAISE EXCEPTION 'ICON_SHAPE_NONCONFIRMATION_MISSING'; END IF;
  IF position('Sin score separado para identidad' in v_output) = 0 THEN RAISE EXCEPTION 'ICON_IDENTITY_CONFIDENCE_SEPARATION_MISSING'; END IF;
  IF position('ocr_variants' in v_output) = 0 THEN RAISE EXCEPTION 'OCR_VARIANT_VISIBILITY_MISSING'; END IF;
  IF position('source_tokens' in v_output) = 0 THEN RAISE EXCEPTION 'OCR_TOKEN_VISIBILITY_MISSING'; END IF;
  IF position('^\+\d{1,4}$' in v_output) = 0 THEN RAISE EXCEPTION 'COMPACT_PREFIX_RULE_MISSING'; END IF;
  IF position('glifo compacto adyacente separado para revisión' in v_output) = 0 THEN RAISE EXCEPTION 'COMPACT_GLYPH_SEPARATION_EXPLANATION_MISSING'; END IF;
  IF private.fn_lf_p0_human_review_human_language_v2(v_output) <> v_output THEN RAISE EXCEPTION 'HUMAN_LANGUAGE_V2_NOT_IDEMPOTENT'; END IF;
  IF position('data-review-shell-version="4.2"' in v_output) = 0 THEN RAISE EXCEPTION 'HUMAN_LANGUAGE_V42_DESIGN_MARKER_LOST'; END IF;
END;
$$;