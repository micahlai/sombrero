from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest


class BundleTests(unittest.TestCase):
    def test_file_launcher_builds_without_dependencies_or_module_fetches(self):
        app = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "animation-lab.html"
            subprocess.run([sys.executable, "-B", str(app / "launch.py"), "--no-open", "--output", str(output)],
                           check=True, capture_output=True, text=True)
            html = output.read_text()
            self.assertIn("window.PREVIEW_BOOTSTRAP=", html)
            self.assertIn('"placeholderFrames": 10', html)
            self.assertNotIn('src="/app.mjs"', html)
            self.assertNotIn('href="/styles.css"', html)
            self.assertNotIn("Matcha", html)
            self.assertNotIn("data:font", html)
            script = re.search(r'<script type="module">(.*?)</script>', html, re.DOTALL).group(1)
            self.assertNotRegex(script, r"(?m)^import ")
            result = subprocess.run(["node", "--input-type=module", "--check"], input=script,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
