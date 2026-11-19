#!/usr/bin/env python3
"""Cut a sprite sheet into equally sized numbered PNGs without scaling artwork.

Usage:
    python3 split_spritesheet.py sheet.png output_directory
    python3 split_spritesheet.py sheet.png output_directory --grid 6 4
    python3 split_spritesheet.py sheet.png output_directory --grid 6 4 --margin 10 10 --spacing 4 4
    python3 split_spritesheet.py sheet.png output_directory --no-remove-bg
    python3 split_spritesheet.py sheet.png output_directory --allow-misized

Automatic mode infers a uniform grid from the clearest rows, then exports full
cells, including blank cells. Nearby drawings cannot become one wide frame.
Both automatic and explicit grids preserve artwork coordinates within each cell:
no trimming, centering, bottom alignment, or resizing is applied.
Use --grid COLUMNS ROWS if the inferred layout needs correction.
--allow-misized restores the original detector in preview_animation.py: drawings
are cropped individually, blank cells are skipped, and uneven rows are supported.
In that mode, outputs share the largest crop's size; smaller crops are padded,
horizontally centered, and bottom-aligned. Artwork is never scaled.
--grid COLUMNS ROWS overrides detection and exports every full cell, including
blank cells. --margin X Y removes that many pixels from each outer edge;
--spacing X Y excludes the gutters between columns and rows. Grid cells retain
their original placement; any one-pixel rounding differences are padded on the
right/bottom so every exported frame has exactly the same dimensions.
Frames are ordered left to right, then top to bottom. Requires Pillow; no Tk.
Background removal is on by default: tolerance 30, four-way contiguous from the
frame edges. Enclosed matching areas stay intact. --no-remove-bg keeps the
background; --tolerance changes the color tolerance (0-255). This is a
Photoshop-style contiguous selection, not an exact match to Adobe's color engine.
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path
from statistics import median
import sys

from preview_animation import Box, detect_frames


def edge_background_color(image):
    """Estimate a solid background, ignoring RGB hidden under transparency."""
    width, height = image.size
    pixels = image.load()
    colors = [pixels[x, y] for y in (0, height - 1) for x in range(width)]
    colors += [pixels[x, y] for y in range(1, height - 1) for x in (0, width - 1)]
    visible = [color for color in colors if color[3] >= 250]
    if not visible:
        visible = [color for color in colors if color[3] > 0]
    return tuple(int(median(color[c] for color in visible)) for c in range(3)) if visible else (255, 255, 255)


def remove_contiguous_background(image, tolerance: int = 30):
    """Clear edge-connected background pixels; preserve RGB and remaining alpha.

    Match against one fixed perimeter color, with a maximum per-channel RGB
    difference, so a gradual color ramp cannot flood progressively into the art.
    Already transparent pixels are traversable but their hidden RGB is ignored
    when estimating the background.
    """
    from PIL import Image, ImageChops

    if not 0 <= tolerance <= 255:
        raise ValueError("tolerance must be between 0 and 255")
    frame = image.convert("RGBA")
    width, height = frame.size
    border = [y * width + x for y in (0, height - 1) for x in range(width)]
    border += [y * width + x for y in range(1, height - 1) for x in (0, width - 1)]
    background = edge_background_color(frame)
    red, green, blue = ImageChops.difference(
        frame.convert("RGB"), Image.new("RGB", frame.size, background)
    ).split()
    matching = ImageChops.lighter(ImageChops.lighter(red, green), blue).point(
        lambda value: 255 if value <= tolerance else 0
    )
    original_alpha = frame.getchannel("A")
    transparent = original_alpha.point(lambda value: 255 if value == 0 else 0)
    eligible = bytearray(ImageChops.lighter(matching, transparent).tobytes())
    alpha = bytearray(original_alpha.tobytes())
    queue = deque()

    def visit(position):
        if eligible[position]:
            eligible[position] = 0  # Mark when enqueued, not when popped.
            alpha[position] = 0
            queue.append(position)

    for position in border:
        visit(position)
    while queue:
        position = queue.popleft()
        x = position % width
        if x:
            visit(position - 1)
        if x + 1 < width:
            visit(position + 1)
        if position >= width:
            visit(position - width)
        if position + width < width * height:
            visit(position + width)
    frame.putalpha(Image.frombytes("L", frame.size, bytes(alpha)))
    return frame


def grid_boxes(width: int, height: int, grid: tuple[int, int],
               margin: tuple[int, int] = (0, 0),
               spacing: tuple[int, int] = (0, 0)) -> list[Box]:
    columns, rows = grid
    mx, my = margin
    sx, sy = spacing
    if columns <= 0 or rows <= 0:
        raise ValueError("grid columns and rows must be greater than zero")
    if min(mx, my, sx, sy) < 0:
        raise ValueError("margin and spacing cannot be negative")
    usable_width = width - 2 * mx - (columns - 1) * sx
    usable_height = height - 2 * my - (rows - 1) * sy
    if usable_width < columns or usable_height < rows:
        raise ValueError("grid, margins, and spacing do not fit inside the image")
    return [(mx + col * usable_width // columns + col * sx,
             my + row * usable_height // rows + row * sy,
             mx + (col + 1) * usable_width // columns + col * sx,
             my + (row + 1) * usable_height // rows + row * sy)
            for row in range(rows) for col in range(columns)]


def infer_grid(image) -> tuple[int, int]:
    """Use substantial drawings to infer a regular layout across the full sheet.

    A clear row supplies the column count even when other rows contain merged
    drawings. Ignore small fragments when inferring the layout, but retain their
    pixels in the final cells. Row pitch also recovers faint/fragmented end rows.
    Ambiguous sheets can always use the explicit --grid override.
    """
    boxes, row_counts, _ = detect_frames(image)
    min_height = max(d - b for a, b, c, d in boxes) * .3
    min_width = median(c - a for a, b, c, d in boxes) * .3
    rows = []
    offset = 0
    for count in row_counts:
        substantial = [box for box in boxes[offset:offset + count]
                       if box[3] - box[1] >= min_height
                       and box[2] - box[0] >= min_width]
        offset += count
        if substantial:
            rows.append(substantial)
    columns = max(map(len, rows))
    centers = [(min(b for a, b, c, d in row) + max(d for a, b, c, d in row)) / 2
               for row in rows]
    row_count = len(rows)
    if len(centers) > 1:
        pitch = median(b - a for a, b in zip(centers, centers[1:]))
        row_count = max(row_count, round(image.height / pitch))
    return columns, row_count


def split_sheet(source: Path, output: Path, *, grid: tuple[int, int] | None = None,
                margin: tuple[int, int] = (0, 0), spacing: tuple[int, int] = (0, 0),
                overwrite: bool = False, remove_bg: bool = True,
                tolerance: int = 30, allow_misized: bool = False) -> list[Path]:
    from PIL import Image, ImageOps

    source, output = Path(source).expanduser(), Path(output).expanduser()
    if grid is None and (margin != (0, 0) or spacing != (0, 0)):
        raise ValueError("--margin and --spacing require --grid")
    if not 0 <= tolerance <= 255:
        raise ValueError("tolerance must be between 0 and 255")
    with Image.open(source) as original:
        image = ImageOps.exif_transpose(original).convert("RGBA")
    inferred = grid is None and not allow_misized
    if inferred:
        grid = infer_grid(image)
    if grid is None:
        boxes, row_counts, _ = detect_frames(image)
    else:
        boxes = grid_boxes(*image.size, grid, margin, spacing)
        row_counts = [grid[0]] * grid[1]
    frame_size = (max(right - left for left, top, right, bottom in boxes),
                  max(bottom - top for left, top, right, bottom in boxes))
    transparent_padding = remove_bg or image.getchannel("A").getextrema()[0] < 255
    padding_color = (0, 0, 0, 0) if transparent_padding else (*edge_background_color(image), 255)
    digits = max(4, len(str(len(boxes))))
    paths = [output / f"frame_{index:0{digits}d}.png" for index in range(1, len(boxes) + 1)]
    # Check the entire batch before writing, so rerunning into an existing
    # directory cannot silently replace part of an earlier export.
    for path in paths:
        if path.resolve() == source.resolve():
            raise ValueError(f"output would replace the input image: {path}")
        if (path.exists() or path.is_symlink()) and not overwrite:
            raise FileExistsError(f"{path} already exists; choose another directory or pass --overwrite")
    output.mkdir(parents=True, exist_ok=True)
    for path, box in zip(paths, boxes):
        frame = image.crop(box)
        if remove_bg:
            frame = remove_contiguous_background(frame, tolerance)
        canvas = Image.new("RGBA", frame_size, padding_color)
        # Grid crops always keep their original cell origin. Registration is
        # reserved for the legacy individual-crop mode (--allow-misized).
        offset = (0, 0)
        if grid is None:
            offset = ((frame_size[0] - frame.width) // 2, frame_size[1] - frame.height)
        # Paste without a mask to retain the crop's exact RGB and partial alpha.
        canvas.paste(frame, offset)
        with path.open("wb" if overwrite else "xb") as handle:
            canvas.save(handle, format="PNG")
    mode = "automatic individual crops" if grid is None else f"{grid[0]} x {grid[1]} grid"
    if inferred:
        mode = "inferred " + mode
    print(f"Exported {len(paths)} frames to {output} ({mode}; "
          f"rows {' / '.join(map(str, row_counts))}; {frame_size[0]} x {frame_size[1]} px each; background "
          f"{'removed, tolerance ' + str(tolerance) if remove_bg else 'kept'}).")
    return paths


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("image", type=Path, help="input sprite sheet")
    parser.add_argument("output_directory", type=Path, help="destination directory (created if needed)")
    parser.add_argument("--grid", type=int, nargs=2, metavar=("COLUMNS", "ROWS"),
                        help="override automatic detection with a regular grid")
    parser.add_argument("--allow-misized", action="store_true",
                        help="restore individual drawing detection, allowing uneven rows and crop sizes (ignored with --grid)")
    parser.add_argument("--margin", type=int, nargs=2, default=(0, 0), metavar=("X", "Y"),
                        help="outer margin on each side in pixels (requires --grid)")
    parser.add_argument("--spacing", type=int, nargs=2, default=(0, 0), metavar=("X", "Y"),
                        help="gaps between grid cells in pixels (requires --grid)")
    parser.add_argument("--overwrite", action="store_true", help="replace existing numbered output files")
    parser.add_argument("--remove-bg", action=argparse.BooleanOptionalAction, default=True,
                        help="remove contiguous edge-connected background (default: enabled; --no-remove-bg disables)")
    parser.add_argument("--tolerance", type=int, default=30,
                        help="background color tolerance, 0-255 (default: 30)")
    args = parser.parse_args(argv)
    if args.grid is None and (tuple(args.margin) != (0, 0) or tuple(args.spacing) != (0, 0)):
        parser.error("--margin and --spacing require --grid")
    try:
        split_sheet(args.image, args.output_directory,
                    grid=tuple(args.grid) if args.grid is not None else None,
                    margin=tuple(args.margin), spacing=tuple(args.spacing), overwrite=args.overwrite,
                    remove_bg=args.remove_bg, tolerance=args.tolerance,
                    allow_misized=args.allow_misized)
    except ModuleNotFoundError as error:
        if error.name == "PIL":
            parser.exit(1, "Pillow is required. Install with: python3 -m pip install Pillow\n")
        raise
    except (OSError, ValueError) as error:
        parser.exit(1, f"Cannot split sprite sheet: {error}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
