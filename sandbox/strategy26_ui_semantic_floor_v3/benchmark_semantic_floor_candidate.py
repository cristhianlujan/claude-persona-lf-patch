from __future__ import annotations

import json
import sys
from copy import deepcopy
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(HERE))

from semantic_floor_candidate import candidate_semantic_codes  # noqa: E402
from services.profile_runtime_api.profile_runtime_api.repository import RepositoryBindings  # noqa: E402
from services.profile_runtime_api.profile_runtime_api.validation import OutputGates  # noqa: E402


def base_en() -> dict[str, object]:
    return {
        "decision_subject": "horizontal table overflow cue",
        "selected_visual_type": "subtle horizontal scroll affordance at table edge",
        "base_color_or_surface": "existing neutral surface token",
        "size_or_coverage": "table viewport edge only",
        "density_limits": "one cue per overflowing table viewport",
        "depth_style": "no added elevation",
        "visual_weight": "secondary to table content and row actions",
        "position_behavior": "anchored to horizontal overflow edge",
        "relationship_to_main_element": "supports table navigation without replacing table semantics",
        "implementation_format": "CSS overflow cue and existing component token",
        "hard_exclusions": ["no new business rules", "no hidden row actions"],
        "short_generator_prompt": "implement a subtle horizontal scroll affordance",
        "status": "SANDBOX_READY",
    }


def mutate(**changes: object) -> dict[str, object]:
    p = deepcopy(base_en())
    p.update(changes)
    return p


def positive_cases() -> list[tuple[str, dict[str, object]]]:
    return [
        ("GOOD_OVERFLOW_EN", base_en()),
        (
            "GOOD_PAYMENT_EN",
            mutate(
                decision_subject="selected payment method state",
                selected_visual_type="2px accent outline with trailing check icon on selected payment card",
                base_color_or_surface="existing white card surface with accent token",
                size_or_coverage="selected payment card boundary and trailing icon area only",
                density_limits="one outline and one check icon per selected payment card",
                depth_style="no added shadow or elevation",
                visual_weight="secondary to payment amount and primary continue CTA",
                relationship_to_main_element="supports selected card state without competing with the primary CTA",
                implementation_format="CSS border token plus existing check icon component on payment card",
            ),
        ),
        (
            "GOOD_INLINE_ERROR_EN",
            mutate(
                decision_subject="invalid field feedback",
                selected_visual_type="inline error text with existing error icon beneath invalid field",
                base_color_or_surface="existing error surface token on white form background",
                size_or_coverage="invalid field container and inline feedback area only",
                density_limits="one error message and one error icon per invalid field",
                depth_style="flat with no added shadow",
                visual_weight="secondary to field label but higher contrast than helper content",
                relationship_to_main_element="attached below invalid field without replacing field label",
                implementation_format="existing form error component plus CSS error token on field container",
            ),
        ),
        (
            "GOOD_STICKY_HEADER_EN",
            mutate(
                decision_subject="long settings page orientation",
                selected_visual_type="sticky section header with compact divider",
                base_color_or_surface="existing neutral header surface token",
                size_or_coverage="section header width only within settings container",
                density_limits="one sticky header per visible settings section",
                depth_style="single low elevation shadow below sticky header",
                visual_weight="secondary to page title and primary save action",
                relationship_to_main_element="anchored above section content without covering form controls",
                implementation_format="CSS sticky rule plus divider token on section header component",
            ),
        ),
        (
            "GOOD_MOBILE_TAB_EN",
            mutate(
                decision_subject="active mobile navigation tab",
                selected_visual_type="bottom indicator line beneath active tab label",
                base_color_or_surface="existing accent color token on transparent tab background",
                size_or_coverage="active tab label width only",
                density_limits="one indicator line per active tab",
                depth_style="flat with no shadow",
                visual_weight="secondary to tab label and subordinate to primary screen CTA",
                relationship_to_main_element="aligned below active tab label without shifting navigation content",
                implementation_format="CSS pseudo-element on tab component using existing accent token",
            ),
        ),
        (
            "GOOD_TOOLTIP_EN",
            mutate(
                decision_subject="technical term explanation",
                selected_visual_type="info icon with anchored tooltip beside field label",
                base_color_or_surface="existing dark tooltip surface token",
                size_or_coverage="field label and adjacent icon area only",
                density_limits="one info icon and one tooltip per technical field label",
                depth_style="single tooltip shadow layer above form content",
                visual_weight="tertiary to field label and secondary helper content",
                relationship_to_main_element="attached next to field label without replacing helper text",
                implementation_format="existing tooltip component and icon token attached to field label",
            ),
        ),
        (
            "GOOD_PAYMENT_ES",
            mutate(
                decision_subject="estado del método de pago seleccionado",
                selected_visual_type="borde de acento de 2px con ícono de check en la tarjeta seleccionada",
                base_color_or_surface="superficie blanca existente con token de color de acento",
                size_or_coverage="solo el borde de la tarjeta seleccionada y el área del ícono",
                density_limits="un borde y un ícono por tarjeta de pago seleccionada",
                depth_style="sin sombra ni elevación adicional",
                visual_weight="secundario frente al monto y al CTA primario",
                relationship_to_main_element="apoya el estado de la tarjeta sin competir con el CTA primario",
                implementation_format="token CSS de borde más componente de ícono existente en la tarjeta",
            ),
        ),
        (
            "GOOD_ERROR_ES",
            mutate(
                decision_subject="retroalimentación de campo inválido",
                selected_visual_type="texto de error inline con ícono existente debajo del campo inválido",
                base_color_or_surface="token de superficie de error existente sobre fondo blanco",
                size_or_coverage="solo el contenedor del campo y el área del mensaje inline",
                density_limits="un mensaje y un ícono por campo inválido",
                depth_style="plano y sin sombra adicional",
                visual_weight="secundario a la etiqueta del campo pero con mayor contraste que la ayuda",
                relationship_to_main_element="adjunto debajo del campo sin reemplazar la etiqueta principal",
                implementation_format="componente de error existente más token CSS en el contenedor del campo",
            ),
        ),
    ]


def negative_cases() -> list[tuple[str, dict[str, object]]]:
    observed_enum = {
        "decision_subject": "UI decision",
        "selected_visual_type": "horizontal overflow",
        "base_color_or_surface": "wide operational table",
        "size_or_coverage": "horizontal overflow",
        "density_limits": "no more than one treatment per affected component",
        "depth_style": "subtle",
        "visual_weight": "discovery without hiding row actions",
        "relationship_to_main_element": "without adding business rules",
        "implementation_format": "JSON object",
        "hard_exclusions": ["no hidden actions", "no extra primary call to action"],
        "status": "SANDBOX_READY",
    }
    observed_fewshot = {
        "decision_subject": "horizontal overflow in operational table",
        "selected_visual_type": "1px accent border on the table header",
        "base_color_or_surface": "existing white table surface",
        "size_or_coverage": "1px accent border on the table header",
        "density_limits": "1px accent border on the table header",
        "depth_style": "no added elevation; preserve the existing table shadow token",
        "visual_weight": "secondary to the table data and primary actions",
        "relationship_to_main_element": "displays horizontal scroll bar without hiding row actions",
        "implementation_format": "CSS border token on the table header",
        "hard_exclusions": ["no new business rules", "no extra primary actions"],
        "status": "SANDBOX_READY",
    }
    return [
        ("BAD_ENUM_OBSERVED", observed_enum),
        ("BAD_FEWSHOT_OBSERVED", observed_fewshot),
        ("BAD_NUMERIC_DENSITY", mutate(density_limits="100")),
        ("BAD_GENERIC_DEPTH_WEIGHT", mutate(depth_style="Elevation", visual_weight="Secondary")),
        ("BAD_NON_SURFACE", mutate(base_color_or_surface="wide operational table")),
        ("BAD_RELATION_NO_UI_TARGET", mutate(relationship_to_main_element="without adding business rules")),
        ("BAD_IMPLEMENTATION_JSON", mutate(implementation_format="JSON object")),
        (
            "BAD_DUPLICATE_FIELDS",
            mutate(
                size_or_coverage="subtle horizontal scroll affordance at table edge",
                density_limits="subtle horizontal scroll affordance at table edge",
            ),
        ),
        (
            "BAD_SELECTED_RESTATES_SUBJECT",
            mutate(
                decision_subject="horizontal overflow in operational table",
                selected_visual_type="horizontal overflow",
            ),
        ),
        ("BAD_COVERAGE_NO_SCOPE", mutate(size_or_coverage="horizontal overflow")),
        ("BAD_DENSITY_NO_BOUND", mutate(density_limits="subtle decoration")),
        ("BAD_IMPLEMENTATION_NO_TARGET", mutate(implementation_format="CSS styling")),
        (
            "BAD_SPANISH_GENERIC",
            mutate(
                decision_subject="decisión ui",
                selected_visual_type="desbordamiento horizontal",
                base_color_or_surface="tabla operativa ancha",
                size_or_coverage="desbordamiento horizontal",
                density_limits="decoración sutil",
                depth_style="sutil",
                visual_weight="descubrimiento visual",
                relationship_to_main_element="sin agregar reglas de negocio",
                implementation_format="objeto JSON",
            ),
        ),
    ]


def main() -> int:
    repo = RepositoryBindings(ROOT, max_prompt_chars=120_000)
    gates = OutputGates(repo)
    binding = repo.runtime_schema("ui_architect", "UI_FOCUSED_DECISION")

    def v2_status(payload: dict[str, object]) -> str:
        gate, parsed = gates.contract(
            profile_slug="ui_architect", raw_output=json.dumps(payload), schema=binding
        )
        if gate["status"] != "PASS":
            return "CONTRACT_FAIL"
        return gates.semantic_utility(
            profile_slug="ui_architect", payload=parsed, contract_gate=gate
        )["status"]

    cases = [(n, p, "PASS") for n, p in positive_cases()] + [
        (n, p, "FAIL") for n, p in negative_cases()
    ]
    print("case|expected|v2|candidate|codes")
    correct = 0
    v2_false_pass = 0
    positive_rejections = 0
    for name, payload, expected in cases:
        v2 = v2_status(payload)
        codes = candidate_semantic_codes(payload)
        candidate = "FAIL" if codes else "PASS"
        correct += int(candidate == expected)
        v2_false_pass += int(expected == "FAIL" and v2 == "PASS")
        positive_rejections += int(expected == "PASS" and candidate != "PASS")
        print(f"{name}|{expected}|{v2}|{candidate}|{','.join(codes)}")

    positives = len(positive_cases())
    negatives = len(negative_cases())
    print(f"CANDIDATE_CORRECT={correct}/{len(cases)}")
    print(f"POSITIVE_HOLDOUT_PASS={positives-positive_rejections}/{positives}")
    print(f"NEGATIVE_REJECTION={sum(1 for _,p in negative_cases() if candidate_semantic_codes(p))}/{negatives}")
    print(f"V2_FALSE_PASS_ON_NEGATIVES={v2_false_pass}/{negatives}")
    return 0 if correct == len(cases) else 1


if __name__ == "__main__":
    raise SystemExit(main())
