"""Exercise the shipped verifier with controlled cargo process outcomes."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[1]
# This file has one literal body block; no YAML dependency needed for these tests.
BODY = textwrap.dedent((ROOT / "scripts-library/verify.cargo.cwd.yaml").read_text().split("    body: |\n", 1)[1])

@unittest.skipUnless(shutil.which("jq"), "jq required by verifier")
class VerifierTests(unittest.TestCase):
    def run_verifier(self, cargo):
        with tempfile.TemporaryDirectory() as tmp:
            stub = Path(tmp) / "cargo"
            stub.write_text("#!/bin/sh\n" + cargo)
            stub.chmod(0o755)
            env = {**os.environ, "PATH": tmp + os.pathsep + os.environ["PATH"]}
            result = subprocess.run(["bash", "-c", BODY], env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)

    def test_clean_build_is_verified(self):
        self.assertTrue(self.run_verifier("exit 0")['passed'])

    def test_formatting_diff_survives_regex_filter(self):
        result = self.run_verifier('echo "Diff in src/lib.rs: remove trailing space"; exit 1')
        self.assertFalse(result['passed'])
        self.assertTrue(result['diagnostics_available'])
        self.assertIn('trailing space', result['issues'])

    def test_silent_failure_is_explicitly_incomplete(self):
        result = self.run_verifier('exit 1')
        self.assertFalse(result['passed'])
        self.assertFalse(result['diagnostics_available'])
        self.assertIn('fmt=1 clippy=1 test=1', result['issues'])

    def test_stderr_launch_failure_is_preserved(self):
        result = self.run_verifier('echo "toolchain unavailable" >&2; exit 127')
        self.assertFalse(result['passed'])
        self.assertIn('toolchain unavailable', result['issues'])

if __name__ == "__main__":
    unittest.main()
