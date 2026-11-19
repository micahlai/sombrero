/** Technical slicing, one shared uniform scale, and foot registration only.
 * Every pose is a complete imagegen drawing; no parts, rig, tween, or deformation.
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { sharp } from './image-library.mjs';

const boardPath = 'generated_images/exec-e78e25f8-375b-4269-bb96-63533414fc4d.png';
const output = 'assets/duck/frame-by-frame/v1/pet';
const cellSize = 256;
const uniformExportCellSize = 410;
const scale = uniformExportCellSize / cellSize;
const boardBytes = await fs.readFile(boardPath);
const sha256 = crypto.createHash('sha256').update(boardBytes).digest('hex');
const metadata = await sharp(boardBytes).metadata();
if (metadata.width !== 1024 || metadata.height !== 1536) throw new Error('Expected exact 4 by 6 grid of 256 pixel cells');
await fs.mkdir(path.join(output, 'previews'), { recursive: true });
const frames = [];
const contactLayers = [];
for (let index = 0; index < 24; index++) {
  const sourceCell = { left: (index % 4) * cellSize, top: Math.floor(index / 4) * cellSize, width: cellSize, height: cellSize };
  const { data } = await sharp(boardBytes).extract(sourceCell).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  let sourceBottom = -1;
  let clearedQuantizationPixels = 0;
  for (let y = 0; y < cellSize; y++) for (let x = 0; x < cellSize; x++) {
    const i = (y * cellSize + x) * 4;
    if (data[i + 3] <= 1) { data[i] = data[i + 1] = data[i + 2] = data[i + 3] = 0; clearedQuantizationPixels++; }
    if (data[i + 3] > 90) sourceBottom = Math.max(sourceBottom, y);
  }
  let footMinX = cellSize, footMaxX = -1;
  for (let y = sourceBottom - 20; y <= sourceBottom; y++) for (let x = 0; x < cellSize; x++) {
    const i = (y * cellSize + x) * 4;
    if (data[i + 3] > 90 && data[i] < 190 && data[i + 1] < 160 && data[i + 2] < 120) {
      footMinX = Math.min(footMinX, x); footMaxX = Math.max(footMaxX, x);
    }
  }
  if (footMaxX < footMinX) throw new Error(`Could not locate feet for drawing ${index}`);
  const sourceFootCenterX = (footMinX + footMaxX + 1) / 2;
  const left = Math.round(256 - sourceFootCenterX * scale);
  const top = Math.round(448 - (sourceBottom + 1) * scale);
  if (left < 0 || top < 0 || left + uniformExportCellSize > 512 || top + uniformExportCellSize > 512) throw new Error(`Full cell ${index} cannot fit after registration`);
  const input = await sharp(data, { raw: { width: cellSize, height: cellSize, channels: 4 } }).resize(uniformExportCellSize, uniformExportCellSize).png().toBuffer();
  const file = `react.pet__${String(index).padStart(3, '0')}.png`;
  const rendered = await sharp({ create: { width: 512, height: 512, channels: 4, background: '#00000000' } }).composite([{ input, left, top }]).png().toBuffer();
  await fs.writeFile(path.join(output, file), rendered);
  frames.push({ file, durationFrames: 1, markers: index === 0 || index === 23 ? ['neutral'] : [], attachments: { bubble: { x: 365, y: 125 } }, registration: { sourceCell, sourceFootCenterX, sourceFootBaseline: sourceBottom + 1, uniformScale: scale, translation: { x: left, y: top }, clearedQuantizationPixels } });
  const tile = await sharp(rendered).resize(256, 256).flatten({ background: '#272b32' }).png().toBuffer();
  contactLayers.push({ input: tile, left: index % 4 * 256, top: Math.floor(index / 4) * 256 });
}
const clip = {
  schemaVersion: 1, characterId: 'watercolor-duck', referenceVersion: 'duck-v1-nostrils',
  animationMethod: 'individually-drawn-frames', clipId: 'react.pet',
  frameRate: { numerator: 12, denominator: 1 }, canvas: { width: 512, height: 512 }, groundPivot: { x: 256, y: 448 },
  loop: false, entryPose: 'neutral-redrawn', exitPose: 'neutral-redrawn', safeInterruptionFrames: [0, 23],
  sourceBoard: { path: boardPath, sha256, width: 1024, height: 1536, columns: 4, rows: 6, order: 'row-major', generatedFrom: 'generated_images/exec-0f994ff1-3130-4298-b10e-bbb99ffb5446.png' },
  acting: 'Unseen petting from upper right; anticipatory lean, comfortable closed eyes, loose wing wiggle, soft body bends, follow-through, neutral return. No hand or bill articulation.',
  technicalProcessing: { gridSlicingOnly: true, uniformExportCellSize, uniformScale: scale, perFrameTranslationOnly: true, alphaCleanup: 'Clear only background quantization alpha <=1 and hidden RGB; preserve all source paint alpha >=2', noRig: true, noTween: true, noPerPartTransform: true },
  frames,
};
await fs.writeFile(path.join(output, 'clip.json'), JSON.stringify(clip, null, 2) + '\n');
await sharp({ create: { width: 1024, height: 1536, channels: 4, background: '#272b32' } }).composite(contactLayers).png().toFile(path.join(output, 'previews', 'pet-contact-charcoal.png'));
console.log(JSON.stringify({ clip: path.join(output, 'clip.json'), drawings: frames.length, frameRate: 12, durationSeconds: 2, sourceBoardSha256: sha256 }));
