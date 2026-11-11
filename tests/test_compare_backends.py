import json
import tempfile
import unittest
from pathlib import Path

from scripts.compare_backends import build_payload, compare, load_payload, parse_vector


class CompareBackendsTest(unittest.TestCase):
    def test_frontend_style_lines_are_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "vector.csv"
            path.write_text("1\n2.5\n-3\n", encoding="utf-8")
            self.assertEqual(parse_vector(path), ["1", "2.5", "-3"])

    def test_semicolon_table_is_only_flattened(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "data.csv"
            path.write_text("1;2\n3;4\n", encoding="utf-8")
            self.assertEqual(parse_vector(path), ["1", "2", "3", "4"])
            with self.assertRaisesRegex(ValueError, "27904.*4"):
                build_payload(path, 2, False, 1)

    def test_comparison_ignores_timing_but_rejects_pixels(self):
        base = {"user": 1, "iteracoes": 2, "imageVector": [0] * 900, "durationSeconds": 1}
        other = {**base, "durationSeconds": 999}
        self.assertTrue(compare(base, other, 2)["equivalent"])
        other["imageVector"] = [1] + [0] * 899
        self.assertFalse(compare(base, other, 2)["equivalent"])

    def test_payload_dimension_is_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "payload.json"
            path.write_text(json.dumps({"model": False, "ganho": False, "user": 1, "vector": ["1"]}), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "27904"):
                load_payload(path)


if __name__ == "__main__":
    unittest.main()
