import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest import mock


RUNNER = Path(__file__).resolve().parents[1] / "stresser+benchmarker/scripts/benchmark.py"
SPEC = importlib.util.spec_from_file_location("benchmark_runner", RUNNER)
benchmark = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(benchmark)


class BenchmarkRunnerTest(unittest.TestCase):
    def test_all_prometheus_queries_render_without_interpreting_promql_braces(self):
        for template in benchmark.PROM_QUERIES.values():
            query = benchmark.render_prometheus_query(template, "dis-cpp")
            self.assertNotIn("{container}", query)
            self.assertIn("dis-cpp", query)

    def test_regex_characters_are_escaped_for_both_promql_and_re2(self):
        query = benchmark.render_prometheus_query(benchmark.PROM_QUERIES["memory_usage_bytes"], "dis.cpp")
        self.assertIn(r"dis\\.cpp", query)

    def test_critical_prometheus_failures_do_not_create_a_false_success(self):
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(benchmark, "prometheus_query_range", side_effect=RuntimeError("bad query")):
                with self.assertRaisesRegex(RuntimeError, "critical Prometheus metric queries failed"):
                    benchmark.collect_metrics(Path(directory), "dis-cpp", 1, 2, "http://prometheus")


if __name__ == "__main__":
    unittest.main()
