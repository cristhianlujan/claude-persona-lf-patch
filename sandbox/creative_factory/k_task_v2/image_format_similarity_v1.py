"""Image-format technical QA — measures the received image BYTES, not worker metadata."""
from __future__ import annotations
from io import BytesIO
import hashlib
from PIL import Image, UnidentifiedImageError

DEVICE_RATIOS = {"IPHONE16PRO": 1206 / 2622}


def format_similarity_from_image(
    image_bytes: bytes | None,
    device: str,
    tolerance: float = 0.03,
) -> dict:
    if device not in DEVICE_RATIOS:
        raise ValueError("DEVICE_REFERENCE_UNDECLARED")
    if not 0 <= tolerance < 1:
        raise ValueError("FORMAT_TOLERANCE_INVALID")
    evidence = {
        "schema_version": "SALY_IMAGE_FORMAT_SIMILARITY_V1",
        "device": device,
        "reference_width": 1206,
        "reference_height": 2622,
        "reference_ratio": DEVICE_RATIOS[device],
        "tolerance_relative": tolerance,
        "source": "RECEIVED_IMAGE_BYTES_PIL_VERIFY",
    }
    if not image_bytes:
        return {"result": "NO_EVALUADO",
                "reason": "IMAGE_BYTES_OR_MEASURE_UNAVAILABLE", "evidence": evidence}
    evidence["image_sha256"] = hashlib.sha256(image_bytes).hexdigest()
    try:
        with Image.open(BytesIO(image_bytes)) as decoded:
            decoded.verify()
        with Image.open(BytesIO(image_bytes)) as decoded:
            width, height = decoded.size
            file_format = decoded.format
            decoded.load()
    except (UnidentifiedImageError, OSError, ValueError, SyntaxError) as exc:
        return {"result": "NO_EVALUADO",
                "reason": "IMAGE_DECODE_INVALID",
                "evidence": {**evidence, "decode_error_type": type(exc).__name__}}
    if width <= 0 or height <= 0:
        return {"result": "NO_EVALUADO", "reason": "IMAGE_DIMENSIONS_UNAVAILABLE",
                "evidence": evidence}
    ratio = width / height
    deviation = abs(ratio / DEVICE_RATIOS[device] - 1)
    evidence.update({
        "decoded_image_format": file_format,
        "measured_width": width,
        "measured_height": height,
        "measured_ratio": ratio,
        "relative_deviation": deviation,
        "measurement_kind": "VERIFIED_IMAGE_BYTES_NOT_EXECUTOR_FIELDS",
    })
    return {"result": "SIMILAR" if deviation <= tolerance else "NO_SIMILAR",
            "evidence": evidence}
