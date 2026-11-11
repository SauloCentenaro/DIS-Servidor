import importlib.util
import unittest
from pathlib import Path


RUNNER = Path(__file__).resolve().parents[1] / "stresser+benchmarker/scripts/benchmark.py"
SPEC = importlib.util.spec_from_file_location("benchmark_runner", RUNNER)
benchmark = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(benchmark)


class BenchmarkRunnerTest(unittest.TestCase):
    def test_all_prometheus_queries_render_without_interpreting_promql_braces(self):
        for template in benchmark.PROM_QUERIES.values():
            query = benchmark.render_prometheus_query(template, "dis-cpp")
            self.assertNotIn("{container}", query)
            self.assertIn("dis\\-cpp", query)


if __name__ == "__main__":
    unittest.main()
