from pathlib import Path
import tempfile
import unittest

import check_docs


class DocumentationChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "docs/agent-guide").mkdir(parents=True)
        self.entry = self.root / "CLAUDE.md"
        self.entry.write_text("# Instructions\n[Topic](docs/agent-guide/topic.md#details)\n")
        self.alias = self.root / "AGENTS.md"
        self.alias.symlink_to("CLAUDE.md")
        self.guide = self.root / "docs/agent-guide/topic.md"
        self.guide.write_text("# Topic\n## Details\n[Root](../../CLAUDE.md#instructions)\n")
        (self.root / "README.md").write_text("# Toolkit\n[Instructions](AGENTS.md)\n")

    def assert_error(self, expected):
        self.assertIn(expected, "\n".join(check_docs.check(self.root)))

    def test_valid_documents(self):
        self.assertEqual(check_docs.check(self.root), [])

    def test_root_budget_counts_bytes(self):
        self.entry.write_text("\u00e9" * (check_docs.ROOT_BUDGET // 2 + 1), encoding="utf-8")
        self.assert_error("exceeds 8192-byte budget")

    def test_guide_budget(self):
        self.guide.write_text("x" * (check_docs.GUIDE_BUDGET + 1))
        self.assert_error("exceeds 16384-byte budget")

    def test_alias_must_be_relative_symlink(self):
        self.alias.unlink()
        self.alias.write_text("# Copy\n")
        self.assert_error("must be a relative symlink")
        self.alias.unlink()
        self.alias.symlink_to(self.entry)
        self.assert_error("must be a relative symlink")

    def test_missing_document(self):
        (self.root / "README.md").unlink()
        self.assert_error("README.md: cannot read document")

    def test_broken_link_and_heading(self):
        self.guide.write_text("[Bad file](missing.md)\n[Bad heading](../../CLAUDE.md#absent)\n")
        self.assert_error("missing.md: missing target")
        self.assert_error("CLAUDE.md#absent: missing heading")

    def test_unrouted_guide(self):
        (self.root / "docs/agent-guide/extra.md").write_text("# Extra\n")
        self.assert_error("extra.md: not linked from CLAUDE.md")

    def test_remote_links_and_fenced_examples(self):
        self.guide.write_text(
            "# Topic\n## Details\n[Web](https://example.com/no-probe)\n"
            "```md\n[Example](missing.md)\n```\n"
            "~~~md\n[Example](absent.md)\n~~~\n"
        )
        self.assertEqual(check_docs.check(self.root), [])

    def test_heading_anchors(self):
        self.assertEqual(
            check_docs.anchors("# Topic\n## `DPI` Settings\n## Topic\n```\n# Hidden\n```\n"),
            {"topic", "dpi-settings", "topic-1"},
        )


if __name__ == "__main__":
    unittest.main()
