/** Export the generated app-icon master to every macOS icon size. */
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sharp} from './image-library.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.join(root, 'assets/app-icon.png');
const iconset = path.join(root, '.build/AppIcon.iconset');
await fs.mkdir(iconset, {recursive: true});
const chunks = [];
const types = {16: ['icp4', 'ic11'], 32: ['icp5', 'ic12'],
  128: ['ic07', 'ic13'], 256: ['ic08', 'ic14'], 512: ['ic09', 'ic10']};
for (const size of [16, 32, 128, 256, 512]) {
  for (const density of [1, 2]) {
    const suffix = density === 2 ? '@2x' : '';
    const png = await sharp(source).resize(size * density, size * density).png().toBuffer();
    await fs.writeFile(path.join(iconset, `icon_${size}x${size}${suffix}.png`), png);
    // Modern ICNS entries contain PNG data, including separate Retina variants.
    const header = Buffer.alloc(8);
    header.write(types[size][density - 1]);
    header.writeUInt32BE(png.length + 8, 4);
    chunks.push(header, png);
  }
}
const destination = path.join(root, 'macOS/AppIcon.icns');
const header = Buffer.alloc(8);
header.write('icns');
header.writeUInt32BE(8 + chunks.reduce((sum, chunk) => sum + chunk.length, 0), 4);
await fs.writeFile(destination, Buffer.concat([header, ...chunks]));
console.log(destination);
