"""Real PNG bytes in memory; not executor-supplied dimensions."""
from io import BytesIO
import json
import unittest
from PIL import Image
from image_format_similarity_v1 import format_similarity_from_image


def png_bytes(size):
    b = BytesIO()
    Image.new("RGB", size, (245, 248, 246)).save(b, format="PNG")
    return b.getvalue()


class FormatSimilarityTests(unittest.TestCase):
    def check_size(self, width, height, expected):
        received = png_bytes((width, height))
        result = format_similarity_from_image(received, "IPHONE16PRO", 0.03)
        self.assertEqual(result["result"], expected)
        self.assertEqual(result["evidence"]["measured_width"], width)
        self.assertEqual(result["evidence"]["measured_height"], height)
        self.assertEqual(result["evidence"]["measurement_kind"],
                         "VERIFIED_IMAGE_BYTES_NOT_EXECUTOR_FIELDS")
        print(f"A_FORMAT_INPUT=PNG received bytes {width}x{height} "
              f"A_FORMAT_OUTPUT={json.dumps(result, sort_keys=True)}")

    def test_1206x2622(self):
        self.check_size(1206, 2622, "SIMILAR")

    def test_1290x2796(self):
        self.check_size(1290, 2796, "SIMILAR")

    def test_1206x2400(self):
        self.check_size(1206, 2400, "NO_SIMILAR")

    def test_1024x1536(self):
        self.check_size(1024, 1536, "NO_SIMILAR")

    def test_without_measure(self):
        result = format_similarity_from_image(None, "IPHONE16PRO", 0.03)
        self.assertEqual(result["result"], "NO_EVALUADO")
        print(f"A_FORMAT_INPUT=NO_IMAGE_BYTES A_FORMAT_OUTPUT={json.dumps(result, sort_keys=True)}")

    def test_corrupt_image(self):
        result = format_similarity_from_image(b"fake png bytes", "IPHONE16PRO", 0.03)
        self.assertEqual(result["result"], "NO_EVALUADO")
        print(f"A_FORMAT_INPUT=CORRUPT_BYTES A_FORMAT_OUTPUT={json.dumps(result, sort_keys=True)}")

    def test_adjustable_tolerance(self):
        b = png_bytes((1206, 2622))
        result = format_similarity_from_image(b, "IPHONE16PRO", 0.0)
        self.assertEqual(result["result"], "SIMILAR")


if __name__ == "__main__":
    unittest.main(verbosity=2)
