/** Export the control icon's alpha mask at each native menu-bar density. */
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sharp} from './image-library.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.join(root, 'assets/control-bar-icon.png');
for (const density of [1, 2, 3]) {
  const suffix = density === 1 ? '' : `@${density}x`;
  await sharp(source).resize(18 * density, 18 * density).png()
    .toFile(path.join(root, `Sources/PetAssets/Resources/Controls/DuckTemplate${suffix}.png`));
}
console.log('Exported control icon at 1x, 2x and 3x.');
