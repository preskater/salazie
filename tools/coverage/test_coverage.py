#!/usr/bin/env python3
"""Self-test of the instrumenter. Run: python3 tools/coverage/test_coverage.py"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from coverage import _ranges, instrument_source  # noqa: E402


def lines_of(source: str) -> list:
	return instrument_source(source, 3)[1]


class InstrumentTest(unittest.TestCase):
	def test_only_function_bodies_are_counted(self) -> None:
		source = "extends Node\n\nvar a := 1\n\nfunc f() -> void:\n\ta = 2\n\tprint(a)\n\nvar b := 2\n"
		rewritten, lines = instrument_source(source, 3)
		self.assertEqual(lines, [6, 7])
		self.assertIn("\tSalazieCov.hit(3, 6)\n\ta = 2", rewritten)

	def test_hit_keeps_the_statement_indentation(self) -> None:
		source = "func f() -> void:\n\tif true:\n\t\tpass\n"
		rewritten, _ = instrument_source(source, 0)
		self.assertIn("\t\tSalazieCov.hit(0, 3)\n\t\tpass", rewritten)

	def test_else_and_elif_headers_are_skipped(self) -> None:
		source = "func f(x: int) -> int:\n\tif x > 0:\n\t\treturn 1\n\telif x < 0:\n\t\treturn -1\n\telse:\n\t\treturn 0\n"
		self.assertEqual(lines_of(source), [2, 3, 5, 7])

	def test_match_patterns_are_skipped_but_branches_counted(self) -> None:
		source = (
			"func f(x: int) -> int:\n\tmatch x:\n\t\t1:\n\t\t\treturn 10\n"
			"\t\t_:\n\t\t\tmatch x:\n\t\t\t\t2:\n\t\t\t\t\treturn 20\n\treturn 0\n")
		self.assertEqual(lines_of(source), [2, 4, 6, 8, 9])

	def test_multi_line_statements_count_once(self) -> None:
		source = "func f() -> void:\n\tfoo(\n\t\t1,\n\t\t2)\n\tvar a := 1 + \\\n\t\t2\n\tbar()\n"
		self.assertEqual(lines_of(source), [2, 5, 7])

	def test_brackets_in_strings_and_comments_are_ignored(self) -> None:
		source = "func f() -> void:\n\tvar s := \"(((\"  # ((\n\tbar()\n"
		self.assertEqual(lines_of(source), [2, 3])

	def test_multi_line_signature_starts_the_body_after_it(self) -> None:
		source = "func f(\n\t\ta: int,\n\t\tb: int) -> int:\n\treturn a + b\n"
		self.assertEqual(lines_of(source), [4])

	def test_a_declaration_after_a_function_ends_it(self) -> None:
		source = "func f() -> void:\n\tpass\n\nconst X := 1\n\nstatic func g() -> void:\n\tpass\n"
		self.assertEqual(lines_of(source), [2, 7])

	def test_comments_and_blank_lines_are_not_statements(self) -> None:
		source = "func f() -> void:\n\t# note\n\n\tpass\n"
		self.assertEqual(lines_of(source), [4])

	def test_ranges(self) -> None:
		self.assertEqual(_ranges([1, 2, 3, 7, 9, 10]), "1-3, 7, 9-10")


if __name__ == "__main__":
	unittest.main()
