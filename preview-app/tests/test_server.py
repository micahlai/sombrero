import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("preview_server", Path(__file__).resolve().parents[1] / "server.py")
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)
GRAPH = json.loads(server.GRAPH_FILE.read_text())


class ManifestTests(unittest.TestCase):
    def test_missing_and_empty_folders_have_ten_frames_and_timeout_has_none(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "1A").mkdir()
            manifest = server.asset_manifest(GRAPH, root)
            for state in GRAPH["states"]:
                clip = manifest["clips"][state["id"]]
                self.assertEqual(clip["frameCount"], 0 if state["kind"] == "hidden" else 10)
                self.assertEqual(clip["placeholder"], state["kind"] != "hidden")
                self.assertEqual(clip["assetStatus"], "hidden" if state["kind"] == "hidden" else "empty-folder" if state["id"] == "1a" else "missing-folder")

    def test_case_insensitive_ids_natural_sort_and_encoded_urls(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root / "1A"
            folder.mkdir()
            for name in ["frame 10.png", "frame 2.PNG", "frame 1.webp", "notes.txt", ".hidden.png"]:
                (folder / name).write_bytes(b"fixture")
            manifest = server.asset_manifest(GRAPH, root)
            clip = manifest["clips"]["1a"]
            self.assertFalse(clip["placeholder"])
            self.assertEqual(clip["frameCount"], 3)
            self.assertIn("frame%201.webp", clip["frames"][0])
            self.assertIn("frame%202.PNG", clip["frames"][1])
            self.assertIn("frame%2010.png", clip["frames"][2])

    def test_external_symlink_assets_are_not_served(self):
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as external:
            root = Path(directory)
            (root / "1a").symlink_to(Path(external), target_is_directory=True)
            (Path(external) / "frame.png").write_bytes(b"fixture")
            self.assertTrue(server.asset_manifest(GRAPH, root)["clips"]["1a"]["placeholder"])

    def test_scale_map_is_loaded_with_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            calibration = {"schemaVersion": 1, "canvas": {"width": 1000, "height": 1000},
                           "animations": {"1a": {"status": "calibrated", "scale": 1.5, "offsetX": 42, "offsetY": -12}}}
            (root / "animation-scales.json").write_text(json.dumps(calibration))
            self.assertEqual(server.asset_manifest(GRAPH, root)["calibration"], calibration)
            calibration["animations"]["1a"]["scale"] = -1
            (root / "animation-scales.json").write_text(json.dumps(calibration))
            manifest = server.asset_manifest(GRAPH, root)
            self.assertIsNone(manifest["calibration"])
            self.assertIn("Alignment disabled", manifest["warnings"][0])


if __name__ == "__main__":
    unittest.main()
