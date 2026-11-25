"""Tests for tool-audit's handling of mise's install layout (no network, no ClamAV)."""
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent.parent / "tool-audit"
_loader = SourceFileLoader("tool_audit", str(SCRIPT))
tool_audit = module_from_spec(spec_from_loader("tool_audit", _loader))
_loader.exec_module(tool_audit)


def make_version(installs, tool, version, content="v1"):
    folder = installs / tool / version
    folder.mkdir(parents=True)
    (folder / tool).write_text(content)
    return folder


def point(installs, tool, alias, version):
    link = installs / tool / alias
    if link.is_symlink():
        link.unlink()
    link.symlink_to("./" + version)


class MiseLayout(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.mise = Path(self.directory.name) / "mise"
        self.installs = self.mise / "installs"
        make_version(self.installs, "claude", "2.1.331")
        point(self.installs, "claude", "latest", "2.1.331")
        (self.installs / "claude" / ".mise.backend.toml").write_text("backend = 'aqua'\n")
        make_version(self.installs, "ruby", "3.4.10")
        point(self.installs, "ruby", "3", "3.4.10")
        point(self.installs, "ruby", "3.4", "3.4.10")

    def test_version_folders_are_real_directories_only(self):
        found = tool_audit.mise_version_dirs([str(self.mise)])
        self.assertEqual(sorted(found), sorted([
            str(self.installs / "claude" / "2.1.331"),
            str(self.installs / "ruby" / "3.4.10"),
        ]))

    def test_roots_not_named_mise_are_ignored(self):
        other = Path(self.directory.name) / "uv"
        make_version(other / "installs", "tool", "1.0")
        self.assertEqual(tool_audit.mise_version_dirs([str(other)]), [])

    def test_claude_version_from_mise_folder(self):
        binary = self.installs / "claude" / "2.1.331" / "claude"
        self.assertEqual(tool_audit.claude_version(binary), "2.1.331")

    def test_report_groups_mise_changes_by_tool_and_version(self):
        path = str(Path.home() / ".local/share/mise/installs/claude/2.1.331/claude")
        self.assertEqual(tool_audit.group_label(path), "~/.local/share/mise/installs/claude/2.1.331")

    def test_claude_version_from_vendor_layout(self):
        self.assertEqual(tool_audit.claude_version(Path("/x/claude/versions/2.1.332")), "2.1.332")


class FindTool(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.bin = Path(self.directory.name) / "bin"
        self.bin.mkdir()
        self.fallback = Path(self.directory.name) / "fallback-claude"
        self.fallback.write_text("vendor")
        self.old_path = os.environ["PATH"]
        self.addCleanup(os.environ.__setitem__, "PATH", self.old_path)

    def stub_mise(self, body):
        stub = self.bin / "mise"
        stub.write_text("#!/bin/sh\n" + body)
        stub.chmod(0o755)
        os.environ["PATH"] = f"{self.bin}:{self.old_path}"

    def test_prefers_mise_which(self):
        target = Path(self.directory.name) / "mise-claude"
        target.write_text("mise")
        self.stub_mise(f'[ "$1 $2" = "which claude" ] && echo {target} && exit 0\nexit 1\n')
        self.assertEqual(tool_audit.find_tool("claude", self.fallback), target)

    def test_falls_back_when_mise_does_not_know_the_tool(self):
        self.stub_mise("echo 'mise ERROR tool not found' >&2; exit 1\n")
        self.assertEqual(tool_audit.find_tool("claude", self.fallback), self.fallback)

    def test_none_when_neither_exists(self):
        self.stub_mise("exit 1\n")
        self.assertIsNone(tool_audit.find_tool("claude", Path(self.directory.name) / "missing"))


class UpgradeIsNotARedFlag(unittest.TestCase):
    """End to end: an upgrade adds a folder and moves `latest`; tampering is a red flag."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        base = Path(self.directory.name)
        self.mise = base / "mise"
        self.installs = self.mise / "installs"
        self.state = base / "state"
        make_version(self.installs, "claude", "2.1.331")
        point(self.installs, "claude", "latest", "2.1.331")
        (self.installs / "claude" / ".mise.backend.toml").write_text("a\n")
        self.assertEqual(self.audit("--accept").returncode, 0)

    def audit(self, *extra):
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--root", str(self.mise), "--state-dir", str(self.state),
             "--no-scan", "--offline", "--no-watch", *extra],
            capture_output=True, text=True, timeout=60)

    def test_upgrade_is_not_a_red_flag(self):
        make_version(self.installs, "claude", "2.1.332", "v2")
        point(self.installs, "claude", "latest", "2.1.332")
        (self.installs / "claude" / ".mise.backend.toml").write_text("b\n")
        result = self.audit()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("RED FLAG", result.stdout)

    def test_change_inside_a_version_folder_is_a_red_flag(self):
        (self.installs / "claude" / "2.1.331" / "claude").write_text("tampered")
        result = self.audit()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("RED FLAG", result.stdout)


if __name__ == "__main__":
    unittest.main()
