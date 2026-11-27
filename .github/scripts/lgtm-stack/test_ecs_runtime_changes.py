import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("ecs_changes", Path(__file__).with_name("ecs-runtime-changes.py"))
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)
CHART = "charts/lgtm-stack/"


class ChangesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.previous = Path.cwd()
        self.addCleanup(os.chdir, self.previous)
        os.chdir(self.temp.name)
        self.git("init", "-q")
        self.write("seed")
        self.base = self.commit()
        self.output = Path("runner-output")
        self.output.write_text("existing=value\n")

    def git(self, *args):
        return subprocess.check_output(["git", "-c", "user.name=Fixture", "-c",
                                       "user.email=fixture@example.invalid", *args], timeout=5).decode().strip()

    def write(self, name):
        path = Path(name)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("public fixture\n")

    def commit(self):
        self.git("add", "--all")
        self.git("commit", "-qm", "public fixture")
        return self.git("rev-parse", "HEAD")

    def invoke(self, base, head):
        return M.main(["--base=" + base, "--head=" + head, "--github-output", str(self.output)])

    def test_every_run_path_in_real_git(self):
        chart_paths = ("Chart.yaml Chart.lock .helmignore values.yaml values.schema.json "
                       "templates/_gateway.tpl templates/_gateway-ecs.tpl templates/_gateway-transport.tpl "
                       "templates/_helpers.tpl templates/applications.yaml templates/gateway.yaml "
                       "presets/alloy-gateway.yaml presets/kube-prometheus-stack.yaml charts/dependency/file "
                       "files/tests/test-ecs-receiver.sh files/tests/ecs-receiver-values.yaml "
                       "files/tests/ecs-receiver-fixtures.py files/tests/ecs-receiver-runtime.py tests/ecs_profile_test.yaml").split()
        paths = [CHART + name for name in chart_paths] + [".github/workflows/pull_request.yml",
                 ".github/scripts/lgtm-stack/ecs-runtime-changes.py", ".github/scripts/lgtm-stack/test_ecs_runtime_changes.py"]
        for name in paths:
            with self.subTest(path=name):
                base = self.git("rev-parse", "HEAD")
                self.write(name)
                self.assertTrue(M.classify(base, self.commit()))

    def test_skip_and_mixed(self):
        for name in ("README.md", CHART + "README.md", CHART + "CHANGELOG.md", CHART + "templates/_gateway-kubernetes.tpl",
                     CHART + "presets/loki.yaml", CHART + "files/rules/x.yaml", "charts/other/values.yaml",
                     "unusual space\nand-newline.py"):
            self.write(name)
        head = self.commit()
        self.assertFalse(M.classify(self.base, head))
        self.assertEqual(self.invoke(self.base, head), 0)
        self.assertEqual(self.output.read_text(), "existing=value\nrun=false\n")
        self.write(CHART + "templates/_gateway-ecs.tpl")
        self.assertEqual(self.invoke(self.base, self.commit()), 0)
        self.assertEqual(self.output.read_text(), "existing=value\nrun=false\nrun=true\n")

    def test_deletion_and_renames_both_directions(self):
        tracked = CHART + "templates/_gateway-ecs.tpl"
        self.write(tracked)
        base = self.commit()
        self.git("mv", tracked, "outside.txt")
        head = self.commit()
        self.assertTrue(M.classify(base, head))
        self.git("mv", "outside.txt", tracked)
        renamed = self.commit()
        self.assertTrue(M.classify(head, renamed))
        Path(tracked).unlink()
        self.assertTrue(M.classify(renamed, self.commit()))

    def test_invalid_or_missing_commit_preserves_output(self):
        for sha in ("--help", "abc", "0" * 40):
            self.assertEqual(self.invoke(sha, self.base), 1)
            self.assertEqual(self.output.read_text(), "existing=value\n")

    def test_failed_timed_out_or_truncated_diff_preserves_output(self):
        for failure in (ValueError("failed"), TimeoutError("timeout"), b"partial", b"a\0\0"):
            with self.subTest(failure=type(failure).__name__), patch.object(M, "git", side_effect=[b"", b"", failure]):
                self.assertEqual(self.invoke(self.base, self.base), 1)
                self.assertEqual(self.output.read_text(), "existing=value\n")

    def test_real_git_failure_and_output_limit(self):
        with self.assertRaises(ValueError):
            M.git("not-a-git-command")
        with patch.object(M, "MAX_OUTPUT", 1):
            with self.assertRaisesRegex(ValueError, "limit"):
                M.git("rev-parse", "HEAD")
        with patch.object(M.time, "monotonic", side_effect=[0, 16]):
            with self.assertRaises(TimeoutError):
                M.git("rev-parse", "HEAD")

    def test_publication_failure_is_nonzero(self):
        self.output.unlink()
        self.output.mkdir()
        self.assertEqual(self.invoke(self.base, self.base), 1)


if __name__ == "__main__":
    unittest.main()
