"""Copy the five authored notification drawings without modifying their pixels."""
from pathlib import Path
import shutil
import struct

root = Path(__file__).resolve().parents[1]
source = root / "assets/exclaimation"
target = root / "Sources/PetAssets/Resources/Notifications"
frames = [source / f"ex{index:04d}.png" for index in range(5)]
for frame in frames:
    header = frame.read_bytes()[:26]
    if header[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", header[16:24]) != (512, 512) or header[25] not in (4, 6):
        raise SystemExit(f"Expected a transparent 512 x 512 PNG: {frame.name}")
target.mkdir(parents=True, exist_ok=True)
for frame in frames:
    shutil.copyfile(frame, target / frame.name)
print("Notification: 5 authored watercolor frames")
