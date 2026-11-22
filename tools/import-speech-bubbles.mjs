/** Import revised authored bubble artwork using its existing runtime registration. */
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {sharp} from './image-library.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// The first four drawings retain their calibrated exports. The revised expanded
// drawing uses the same scale and canvas position as the previous ss0004 export.
const source = path.join(root, 'assets/speech-bubble/v1/small/frame_0005.png');
const metadata = await sharp(source).metadata();
if (metadata.width !== 634 || metadata.height !== 1344) {
  throw new Error('Speech drawing canvas changed; recalibrate before importing.');
}
const registered = await sharp(source)
  .resize(473, 1003)
  .extract({left: 0, top: 228, width: 473, height: 500})
  .toBuffer();
await sharp({create: {width: 700, height: 500, channels: 4, background: '#00000000'}})
  .composite([{input: registered, left: 139, top: 0}])
  .png()
  .toFile(path.join(root, 'assets/duck/final-v1/speech_small/ss0004.png'));
console.log('Imported revised expanded speech bubble.');
