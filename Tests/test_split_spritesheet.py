"""Run with: python3 -m unittest discover -s Tests -p 'test_split_spritesheet.py'."""

import contextlib
import io
from pathlib import Path
import tempfile
import unittest

from PIL import Image, ImageDraw

from preview_animation import load_sheet
from split_spritesheet import grid_boxes, infer_grid, main, remove_contiguous_background, split_sheet


class SplitTests(unittest.TestCase):
    def test_automatic_export_preserves_source_pixels(self):
        source = Path(__file__).resolve().parents[1] / "assets/duck/v2/1-look.png"
        sheet = load_sheet(source)
        with tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
            paths = split_sheet(source, Path(temporary) / "nested/frames", remove_bg=False,
                                allow_misized=True)
            self.assertEqual(len(paths), 23)
            self.assertEqual(paths[0].name, "frame_0001.png")
            self.assertEqual(paths[-1].name, "frame_0023.png")
            canvas_size = (max(c - a for a, b, c, d in sheet.boxes),
                           max(d - b for a, b, c, d in sheet.boxes))
            for path, box in zip(paths, sheet.boxes):
                with Image.open(path) as exported:
                    expected = sheet.image.crop(box)
                    self.assertEqual(exported.size, canvas_size)
                    x, y = (canvas_size[0] - expected.width) // 2, canvas_size[1] - expected.height
                    crop = exported.crop((x, y, x + expected.width, y + expected.height))
                    self.assertEqual(crop.tobytes(), expected.tobytes())
                    if y:
                        self.assertEqual(exported.getpixel((0, 0))[3], 255)
                        self.assertGreaterEqual(min(exported.getpixel((0, 0))[:3]), 250)

    def test_override_exports_full_cells_including_blank_and_retains_alpha(self):
        with tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
            root = Path(temporary)
            source = root / "sheet.png"
            image = Image.new("RGBA", (105, 64), (255, 0, 0, 0))
            ImageDraw.Draw(image).rectangle((5, 4, 49, 29), fill=(0, 120, 255, 128))
            image.save(source)
            paths = split_sheet(source, root / "frames", grid=(2, 2), margin=(5, 4), spacing=(5, 4), remove_bg=False)
            expected_boxes = [(5, 4, 50, 30), (55, 4, 100, 30),
                              (5, 34, 50, 60), (55, 34, 100, 60)]
            self.assertEqual(len(paths), 4)
            for path, box in zip(paths, expected_boxes):
                with Image.open(path) as exported:
                    self.assertEqual(exported.tobytes(), image.crop(box).tobytes())

    def test_rounding_keeps_all_pixels_without_overlap(self):
        self.assertEqual(grid_boxes(11, 7, (2, 2)),
                         [(0, 0, 5, 3), (5, 0, 11, 3), (0, 3, 5, 7), (5, 3, 11, 7)])

    def test_grid_rounding_produces_identical_sizes_without_resampling(self):
        with tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
            root = Path(temporary)
            image = Image.new("RGBA", (11, 7), "white")
            image.putpixel((2, 1), (20, 70, 150, 128))
            image.putpixel((10, 6), (100, 200, 30, 255))
            source = root / "sheet.png"
            image.save(source)
            paths = split_sheet(source, root / "frames", grid=(2, 2), remove_bg=False)
            for path, box in zip(paths, grid_boxes(11, 7, (2, 2))):
                with Image.open(path) as frame:
                    self.assertEqual(frame.size, (6, 4))
                    crop = image.crop(box)
                    self.assertEqual(frame.crop((0, 0, crop.width, crop.height)).tobytes(), crop.tobytes())

    def test_automatic_padding_is_transparent_when_removing_background(self):
        with tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
            root = Path(temporary)
            image = Image.new("RGB", (200, 120), "white")
            draw = ImageDraw.Draw(image)
            draw.rectangle((20, 20, 59, 99), fill="black")
            draw.rectangle((120, 50, 179, 99), fill="black")
            source = root / "sheet.png"
            image.save(source)
            paths = split_sheet(source, root / "frames", allow_misized=True)
            self.assertEqual(len(paths), 2)
            with Image.open(paths[0]) as tall, Image.open(paths[1]) as short:
                self.assertEqual(tall.size, short.size)
                self.assertEqual(tall.getpixel((0, 0))[3], 0)
                self.assertEqual(short.getpixel((0, 0))[3], 0)
                self.assertEqual(tall.getchannel("A").getbbox(), (12, 2, 52, 82))
                self.assertEqual(short.getchannel("A").getbbox(), (2, 32, 62, 82))

    def test_default_grid_separates_touching_sprites_and_keeps_blank_cells(self):
        with tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
            root = Path(temporary)
            image = Image.new("RGBA", (300, 200), "white")
            draw = ImageDraw.Draw(image)
            for x in (20, 120, 220):
                draw.rectangle((x, 20, x + 59, 79), fill=(0, 120, 255, 128))
            # Two adjacent frames touch at the grid boundary; last cell is blank.
            draw.rectangle((20, 120, 179, 179), fill="black")
            source = root / "sheet.png"
            image.save(source)
            self.assertEqual(infer_grid(image), (3, 2))
            paths = split_sheet(source, root / "grid", remove_bg=False)
            self.assertEqual(len(paths), 6)
            for path, box in zip(paths, grid_boxes(300, 200, (3, 2))):
                with Image.open(path) as frame:
                    self.assertEqual(frame.size, (100, 100))
                    self.assertEqual(frame.tobytes(), image.crop(box).tobytes())
            self.assertEqual(main([str(source), str(root / "legacy"), "--allow-misized"]), 0)
            self.assertEqual(len(list((root / "legacy").glob("*.png"))), 4)

    def test_inferred_grid_recovers_faint_fragmented_last_row(self):
        image = Image.new("RGBA", (300, 300), "white")
        draw = ImageDraw.Draw(image)
        for y in (20, 120):
            for x in (20, 120, 220):
                draw.rectangle((x, y, x + 59, y + 59), fill="black")
        for x in (20, 50, 120, 150, 220, 250):
            draw.rectangle((x, 230, x + 9, 239), fill="black")
        self.assertEqual(infer_grid(image), (3, 3))

    def test_grid_preserves_off_center_pose_positions_with_and_without_background(self):
        with tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
            root = Path(temporary)
            image = Image.new("RGBA", (240, 200), "white")
            draw = ImageDraw.Draw(image)
            # Different sizes and offsets must survive as motion, without any
            # per-pose centering or alignment to a shared baseline.
            poses = [(8, 7, 40, 61), (45, 20, 105, 86),
                     (25, 37, 60, 92), (5, 5, 110, 75)]
            for index, (left, top, right, bottom) in enumerate(poses):
                x, y = (index % 2) * 120, (index // 2) * 100
                draw.rectangle((x + left, y + top, x + right - 1, y + bottom - 1),
                               fill=(20, 120, 200, 255))
                image.putpixel((x + left, y + top), (20, 120, 200, 128))
            source = root / "sheet.png"
            image.save(source)
            for grid in (None, (2, 2)):
                for remove_bg in (False, True):
                    with self.subTest(grid=grid, remove_bg=remove_bg):
                        paths = split_sheet(source, root / f"{grid}-{remove_bg}",
                                            grid=grid, remove_bg=remove_bg)
                        self.assertEqual(len(paths), 4)
                        for index, path in enumerate(paths):
                            with Image.open(path) as frame:
                                self.assertEqual(frame.size, (120, 100))
                                left, top, right, bottom = poses[index]
                                self.assertEqual(frame.getpixel((left, top)), (20, 120, 200, 128))
                                if remove_bg:
                                    self.assertEqual(frame.getchannel("A").getbbox(), poses[index])
                                else:
                                    x, y = (index % 2) * 120, (index // 2) * 100
                                    self.assertEqual(frame.tobytes(), image.crop((x, y, x + 120, y + 100)).tobytes())

    def test_conflicts_are_checked_before_any_frames_are_written(self):
        with tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
            root = Path(temporary)
            Image.new("RGB", (20, 10), "white").save(root / "sheet.png")
            output = root / "frames"
            output.mkdir()
            collision = output / "frame_0002.png"
            collision.write_bytes(b"keep me")
            with self.assertRaises(FileExistsError):
                split_sheet(root / "sheet.png", output, grid=(2, 1))
            self.assertFalse((output / "frame_0001.png").exists())
            self.assertEqual(collision.read_bytes(), b"keep me")
            paths = split_sheet(root / "sheet.png", output, grid=(2, 1), overwrite=True)
            with Image.open(paths[1]) as exported:
                self.assertEqual(exported.size, (10, 10))

    def test_invalid_layouts_and_input_overwrite_are_rejected(self):
        for grid, margin, spacing in [((0, 1), (0, 0), (0, 0)),
                                       ((2, 2), (-1, 0), (0, 0)),
                                       ((2, 2), (0, 0), (20, 20))]:
            with self.subTest(grid=grid, margin=margin, spacing=spacing), self.assertRaises(ValueError):
                grid_boxes(20, 20, grid, margin, spacing)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "frame_0001.png"
            Image.new("RGB", (20, 10), "white").save(source)
            with self.assertRaisesRegex(ValueError, "input image"):
                split_sheet(source, root, grid=(1, 1), overwrite=True)


class BackgroundTests(unittest.TestCase):
    def test_contiguous_selection_preserves_enclosed_white_and_existing_alpha(self):
        image = Image.new("RGBA", (20, 20), "white")
        draw = ImageDraw.Draw(image)
        draw.rectangle((5, 5, 14, 14), outline="black", width=2)
        image.putpixel((8, 8), (120, 30, 10, 128))
        image.putpixel((2, 2), (225, 225, 225, 255))  # Exactly tolerance 30.
        image.putpixel((3, 2), (224, 224, 224, 255))  # Outside tolerance.
        result = remove_contiguous_background(image)
        self.assertEqual(result.getpixel((0, 0))[3], 0)
        self.assertEqual(result.getpixel((2, 2))[3], 0)
        self.assertEqual(result.getpixel((3, 2)), image.getpixel((3, 2)))
        self.assertEqual(result.getpixel((10, 10)), (255, 255, 255, 255))
        self.assertEqual(result.getpixel((8, 8)), (120, 30, 10, 128))
        self.assertEqual(result.convert("RGB").tobytes(), image.convert("RGB").tobytes())
        self.assertEqual(image.getpixel((0, 0))[3], 255)  # Source not mutated.

    def test_nonwhite_background_and_transparent_hidden_rgb(self):
        image = Image.new("RGBA", (20, 20), (10, 60, 110, 255))
        ImageDraw.Draw(image).rectangle((7, 7, 12, 12), fill=(220, 160, 0, 255))
        image.putpixel((0, 0), (255, 0, 0, 0))
        result = remove_contiguous_background(image, 0)
        self.assertEqual(result.getpixel((3, 3))[3], 0)
        self.assertEqual(result.getpixel((8, 8)), image.getpixel((8, 8)))
        self.assertEqual(result.getpixel((0, 0)), (255, 0, 0, 0))

    def test_color_ramp_does_not_expand_tolerance(self):
        image = Image.new("RGBA", (20, 20), "white")
        for x, value in enumerate([245, 235, 225, 215, 205], 5):
            for y in range(5, 15):
                image.putpixel((x, y), (value, value, value, 255))
        result = remove_contiguous_background(image)
        self.assertEqual(result.getpixel((7, 10))[3], 0)
        self.assertEqual(result.getpixel((8, 10))[3], 255)

    def test_cli_default_enabled_and_disable_option(self):
        with tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
            root = Path(temporary)
            image = Image.new("RGB", (20, 20), "white")
            ImageDraw.Draw(image).rectangle((5, 5, 14, 14), fill="black")
            image.save(root / "sheet.png")
            for enabled in (True, False):
                output = root / str(enabled)
                arguments = [str(root / "sheet.png"), str(output), "--grid", "1", "1"]
                if not enabled:
                    arguments.append("--no-remove-bg")
                self.assertEqual(main(arguments), 0)
                with Image.open(output / "frame_0001.png") as frame:
                    self.assertEqual(frame.getpixel((0, 0))[3], 0 if enabled else 255)
                    self.assertEqual(frame.getpixel((10, 10)), (0, 0, 0, 255))

    def test_invalid_tolerance_is_rejected(self):
        for tolerance in (-1, 256):
            with self.assertRaises(ValueError):
                remove_contiguous_background(Image.new("RGBA", (10, 10)), tolerance)


if __name__ == "__main__":
    unittest.main()
