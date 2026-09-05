from __future__ import annotations

import re
from typing import Any


def norm(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    return " ".join(value.lower().strip().split())


def tokens(value: str) -> list[str]:
    return re.findall(r"[a-záéíóúüñ0-9#%+_-]+", value.lower())


def has_any(value: str, markers: tuple[str, ...]) -> bool:
    return any(marker in value for marker in markers)


GENERIC_SUBJECTS = {
    "ui decision",
    "visual decision",
    "design decision",
    "interface decision",
    "ui treatment",
    "decisión ui",
    "decision ui",
    "decisión visual",
    "decision visual",
    "decisión de diseño",
    "decision de diseño",
    "tratamiento ui",
}

TREATMENT_MARKERS = (
    "affordance", "indicator", "cue", "icon", "outline", "border", "gradient",
    "fade", "shadow", "sticky", "divider", "badge", "highlight", "label",
    "tooltip", "scrollbar", "scroll bar", "handle", "rail", "tab", "chip",
    "card", "button", "link", "spacing", "layout", "alignment", "animation",
    "transition", "indicador", "señal", "icono", "ícono", "contorno", "borde",
    "gradiente", "sombra", "fijo", "divisor", "etiqueta", "resaltado", "barra",
    "desplazamiento", "tarjeta", "botón", "boton", "enlace", "espaciado",
    "alineación", "alineacion", "animación", "animacion", "transición", "transicion",
)

SURFACE_MARKERS = (
    "#", "rgb", "hsl", "var(", "token", "surface", "background", "transparent",
    "white", "black", "neutral", "gray", "grey", "card", "panel", "canvas",
    "existing", "color", "superficie", "fondo", "transparente", "blanco", "negro",
    "neutro", "gris", "tarjeta", "existente",
)

COVERAGE_MARKERS = (
    "only", "edge", "viewport", "region", "area", "component", "screen", "card",
    "table", "row", "column", "header", "footer", "panel", "section", "container",
    "boundary", "width", "height", "full", "%", "px", "solo", "borde", "región",
    "region", "área", "area", "componente", "pantalla", "tarjeta", "tabla", "fila",
    "columna", "encabezado", "pie", "sección", "seccion", "contenedor", "límite",
    "limite", "ancho", "alto", "completo",
)

DENSITY_MARKERS = (
    "one", "single", "two", "three", " per ", "max", "maximum", "only", "no more",
    "at most", "limit", "count", "layer", "line", "element", "cue", "viewport",
    "item", "%", "px", "uno", "una", "dos", "tres", " por ", "máximo", "maximo",
    "solo", "sola", "no más", "no mas", "como máximo", "como maximo", "límite",
    "limite", "cantidad", "capa", "línea", "linea", "elemento", "señal", "indicador",
)

DEPTH_MARKERS = (
    "elevation", "shadow", "flat", "depth", "layer", "raised", "inset", "border",
    "z-", "no added", "none", "elevación", "elevacion", "sombra", "plano",
    "profundidad", "capa", "elevado", "borde", "sin elevación", "sin elevacion",
    "sin sombra",
)

WEIGHT_MARKERS = (
    "primary", "secondary", "tertiary", "hierarchy", "prominence", "opacity",
    "contrast", "relative", "subordinate", "dominant", "less than", "more than", "%",
    "primario", "secundario", "terciario", "jerarquía", "jerarquia", "prominencia",
    "opacidad", "contraste", "relativo", "subordinado", "dominante", "menos que",
    "más que", "mas que",
)

RELATION_MARKERS = (
    "support", "without", "relative", "adjacent", "inside", "within", "before", "after",
    "below", "above", "next to", "around", "aligned", "anchored", "attached", "preserve",
    "competing", "replacing", "does not", "soporta", "apoya", "sin", "relativo",
    "adyacente", "dentro", "antes", "después", "despues", "debajo", "encima", "junto",
    "alrededor", "alineado", "anclado", "adjunto", "preserva", "compite", "reemplaza",
    "no ",
)

UI_TARGET_MARKERS = (
    "table", "content", "action", "cta", "control", "card", "component", "element",
    "navigation", "header", "row", "button", "field", "primary", "main", "selector",
    "tab", "panel", "tabla", "contenido", "acción", "accion", "tarjeta", "componente",
    "elemento", "navegación", "navegacion", "encabezado", "fila", "botón", "boton",
    "campo", "primario", "principal",
)

IMPLEMENTATION_MARKERS = (
    "css", "svg", "token", "component", "asset", "layout", "html", "javascript",
    "typescript", "tailwind", "class", "pseudo-element", "style", "gradient", "border",
    "shadow", "icon", "componente", "recurso", "clase", "pseudo-elemento", "estilo",
    "gradiente", "borde", "sombra", "icono", "ícono",
)

IMPLEMENTATION_TARGET_MARKERS = (
    "card", "table", "component", "token", "icon", "viewport", "header", "row", "field",
    "button", "tab", "panel", "container", "selector", "cue", "edge", "rule", "tarjeta",
    "tabla", "componente", "icono", "ícono", "encabezado", "fila", "campo", "botón",
    "boton", "contenedor", "señal", "borde", "regla",
)


def candidate_semantic_codes(payload: dict[str, Any]) -> list[str]:
    """Return deterministic candidate blockers for Focused UI Decision.

    Sandbox-only. It is deliberately bilingual and field-semantic. It does not modify
    the canonical schema, profile, runtime prompt, or production validator.
    """
    errors: list[str] = []
    keys = (
        "decision_subject", "selected_visual_type", "base_color_or_surface",
        "size_or_coverage", "density_limits", "depth_style", "visual_weight",
        "relationship_to_main_element", "implementation_format",
    )
    values = {key: norm(payload.get(key)) for key in keys}

    subject = values["decision_subject"]
    selected = values["selected_visual_type"]
    if subject in GENERIC_SUBJECTS:
        errors.append("UI_FOCUSED_DECISION_SUBJECT_NON_CONCRETE")
    if selected and subject and (selected == subject or selected in subject):
        errors.append("UI_FOCUSED_SELECTED_TREATMENT_RESTATES_SUBJECT")
    if selected and len(tokens(selected)) < 3 and not has_any(selected, TREATMENT_MARKERS):
        errors.append("UI_FOCUSED_SELECTED_TREATMENT_NON_CONCRETE")

    surface = values["base_color_or_surface"]
    if surface and not has_any(surface, SURFACE_MARKERS):
        errors.append("UI_FOCUSED_BASE_SURFACE_NON_CONCRETE")

    coverage = values["size_or_coverage"]
    if coverage and not has_any(coverage, COVERAGE_MARKERS):
        errors.append("UI_FOCUSED_SIZE_OR_COVERAGE_SCOPE_MISSING")

    density = values["density_limits"]
    if density:
        if re.fullmatch(r"\d+(?:\.\d+)?", density):
            errors.append("UI_FOCUSED_DENSITY_LIMITS_NUMERIC_ONLY")
        elif not has_any(f" {density} ", DENSITY_MARKERS):
            errors.append("UI_FOCUSED_DENSITY_LIMITS_NON_CONCRETE_V3")

    depth = values["depth_style"]
    if depth and (
        not has_any(depth, DEPTH_MARKERS)
        or (len(tokens(depth)) < 2 and depth not in {"flat", "none", "plano"})
    ):
        errors.append("UI_FOCUSED_DEPTH_STYLE_NON_CONCRETE")

    weight = values["visual_weight"]
    if weight and (not has_any(weight, WEIGHT_MARKERS) or len(tokens(weight)) < 2):
        errors.append("UI_FOCUSED_VISUAL_WEIGHT_NON_CONCRETE")

    relationship = values["relationship_to_main_element"]
    if relationship and not (
        has_any(relationship, RELATION_MARKERS) and has_any(relationship, UI_TARGET_MARKERS)
    ):
        errors.append("UI_FOCUSED_RELATIONSHIP_NON_CONCRETE")

    implementation = values["implementation_format"]
    if implementation and not (
        has_any(implementation, IMPLEMENTATION_MARKERS)
        and has_any(implementation, IMPLEMENTATION_TARGET_MARKERS)
        and len(tokens(implementation)) >= 3
    ):
        errors.append("UI_FOCUSED_IMPLEMENTATION_FORMAT_NON_CONCRETE_V3")

    semantic_fields = (
        "selected_visual_type", "size_or_coverage", "density_limits", "depth_style",
        "visual_weight", "relationship_to_main_element", "implementation_format",
    )
    seen: dict[str, str] = {}
    for key in semantic_fields:
        value = values[key]
        if not value:
            continue
        if value in seen:
            errors.append("UI_FOCUSED_CROSS_FIELD_DUPLICATION")
            break
        seen[value] = key

    return sorted(set(errors))
