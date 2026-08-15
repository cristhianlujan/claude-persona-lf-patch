#!/usr/bin/env python3
"""Image-level guard against OCR decisions from visibly truncated text crops.

Apply this only after isolating the target text ROI (not to a whole bordered
control). A crop is eligible for OCR routing only when foreground ink has a
clear margin to every crop edge. This prevents an artificially clipped glyph
or suffix from being misdiagnosed as an OCR-engine failure.
"""
from __future__ import annotations

from typing import Any

import cv2
import numpy as np


def text_crop_has_clear_margin(
    image: Any,
    *,
    margin_px: int = 3,
    dark_threshold: int = 220,
    min_foreground_pixels: int = 8,
) -> bool:
    if image is None or margin_px < 1:
        return False
    arr = np.asarray(image)
    if arr.ndim == 3:
        gray = cv2.cvtColor(arr, cv2.COLOR_BGR2GRAY)
    elif arr.ndim == 2:
        gray = arr
    else:
        return False
    height, width = gray.shape[:2]
    if width <= margin_px * 2 or height <= margin_px * 2:
        return False
    ys, xs = np.where(gray < dark_threshold)
    if xs.size < min_foreground_pixels:
        return False
    return bool(
        int(xs.min()) >= margin_px
        and int(ys.min()) >= margin_px
        and int(xs.max()) < width - margin_px
        and int(ys.max()) < height - margin_px
    )


def require_complete_text_crop(image: Any, **kwargs: Any) -> None:
    if not text_crop_has_clear_margin(image, **kwargs):
        raise ValueError("INCOMPLETE_OR_EDGE_CLIPPED_TEXT_CROP")
