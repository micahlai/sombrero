"""Run with: python3 -m unittest discover -s tests -p 'test_preview_animation.py'."""

import contextlib
import io
from pathlib import Path
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw

from preview_animation import Preview, Sheet, detect_frames, main, prepare_frames


class DetectionTests(unittest.TestCase):
    def test_original_sheets(self):
        from preview_animation import load_sheet

        root = Path(__file__).resolve().parents[1] / "assets/duck/v2"
        expected = {"1-look.png": [6, 6, 6, 5], "2-look.png": [5, 6, 7, 7],
                    "3-sitdown.png": [5, 5, 5, 5], "4-standup.png": [5, 5, 5, 5],
                    "5-sitting.png": [5, 5, 5, 5]}
        for name, counts in expected.items():
            with self.subTest(sheet=name):
                sheet = load_sheet(root / name)
                self.assertEqual(sheet.row_counts, counts)
                self.assertEqual(len(sheet.boxes), sum(counts))
                for left, top, right, bottom in sheet.boxes:
                    self.assertTrue(0 <= left < right <= sheet.image.width)
                    self.assertTrue(0 <= top < bottom <= sheet.image.height)
                # Every crop is separate from its neighbors, in reading order.
                offset = 0
                for count in counts:
                    row = sheet.boxes[offset:offset + count]
                    self.assertTrue(all(a[2] <= b[0] for a, b in zip(row, row[1:])))
                    offset += count

    def test_irregular_rows_transparency_and_noise(self):
        image = Image.new("RGBA", (600, 400), (255, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        expected = [(30, 20, 80, 150), (230, 20, 280, 150), (490, 20, 540, 150),
                    (70, 230, 120, 360), (390, 230, 440, 360)]
        for box in expected:
            draw.rectangle(box, fill=(240, 170, 20, 255))
        draw.point((580, 390), fill="black")
        boxes, rows, background = detect_frames(image)
        self.assertEqual(rows, [3, 2])
        self.assertEqual(background, (255, 255, 255))
        self.assertEqual(boxes, [(a - 2, b - 2, c + 3, d + 3) for a, b, c, d in expected])

    def test_blank_sheet_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "No frames"):
            detect_frames(Image.new("RGB", (300, 300), "white"))

    def test_two_clips_share_scale_and_play_in_order(self):
        image = Image.new("RGBA", (150, 150), "white")
        draw = ImageDraw.Draw(image)
        draw.rectangle((10, 10, 49, 89), fill="black")
        draw.rectangle((70, 50, 109, 89), fill="black")
        sheets = [Sheet(Path("tall.png"), image, [(10, 10, 50, 90)], [1], (255, 255, 255)),
                  Sheet(Path("short.png"), image, [(70, 50, 110, 90)], [1], (255, 255, 255))]
        frames, labels = prepare_frames(sheets, 200)
        self.assertEqual(len(frames), 2)
        self.assertTrue(labels[0].startswith("tall.png"))
        self.assertTrue(labels[1].startswith("short.png"))
        from PIL import ImageChops
        bounds = [ImageChops.difference(f, Image.new("RGB", f.size, "white")).getbbox() for f in frames]
        self.assertEqual(bounds[0][3], bounds[1][3])
        self.assertEqual(bounds[0][2] - bounds[0][0], bounds[1][2] - bounds[1][0])
        self.assertGreater(bounds[0][3] - bounds[0][1], bounds[1][3] - bounds[1][1])


class PlaybackTests(unittest.TestCase):
    def test_clock_loops_combined_sequence_and_pause_does_not_fast_forward(self):
        # Exercise playback without requiring a GUI/display server.
        player = Preview.__new__(Preview)
        player.frames = list(range(48))  # 23-frame clip followed by 25-frame clip.
        player.fps, player.started, player.paused = 8, 100, False
        player.position = 0
        player.show = lambda: None
        player.root = type("Root", (), {"after": lambda *args: None})()
        with patch("preview_animation.time.monotonic", return_value=103):
            player.tick()
            self.assertEqual(player.position, 24)  # Inside the second clip.
        with patch("preview_animation.time.monotonic", return_value=106):
            player.tick()
            self.assertEqual(player.position, 0)  # Both clips loop together.
        with patch("preview_animation.time.monotonic", return_value=107):
            player.toggle_pause()
            self.assertEqual(player.position, 8)
        with patch("preview_animation.time.monotonic", return_value=120):
            player.tick()
            self.assertEqual(player.position, 8)
            player.step(-1)
            self.assertEqual(player.position, 7)
            player.toggle_pause()
            player.tick()
            self.assertEqual(player.position, 7)

    def test_invalid_arguments(self):
        for args in (["a", "b", "c"], ["a", "--fps", "0"], ["a", "--fps", "nan"],
                     ["a", "--fps", "inf"], ["a", "--size", "1"]):
            with self.subTest(args=args), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as error:
                    main(args)
                self.assertEqual(error.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
