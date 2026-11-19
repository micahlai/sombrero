/**
 * Technical grid slicing/whole-frame registration ONLY.
 * Every input cell was drawn as a complete watercolor duck by imagegen.
 * No cutout parts, rig transforms, image warps, synthetic in-betweens or tweens.
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {sharp} from './image-library.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const boardRelative='generated_images/exec-69a3955c-8e85-4796-baae-c8e6342c93d7.png';
const board=path.join(root,boardRelative);
const out=path.join(root,'assets/duck/frame-by-frame/v1/idle');
const frameDir=path.join(out,'frames');
const referenceRelative='generated_images/exec-0f994ff1-3130-4298-b10e-bbb99ffb5446.png';
const digest=buffer=>crypto.createHash('sha256').update(buffer).digest('hex');
await fs.mkdir(frameDir,{recursive:true});
const boardBytes=await fs.readFile(board);
const metadata=await sharp(boardBytes).metadata();
if(metadata.width!==1024||metadata.height!==1536||!metadata.hasAlpha)throw new Error('Expected 1024×1536 RGBA 4×6 board.');
await fs.copyFile(board,path.join(out,'source-board.png'));

const frames=[];
const scale=410/256; // One identical whole-cell scale across all 24 drawings.
for(let index=0;index<24;index++) {
  const cell={left:(index%4)*256,top:Math.floor(index/4)*256,width:256,height:256};
  const {data,info}=await sharp(boardBytes).extract(cell).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  let bottom=-1;
  for(let y=0;y<256;y++)for(let x=0;x<256;x++){
    const i=(y*256+x)*4,a=data[i+3];
    // Remove only the transparent background's 0/1-alpha quantization residue.
    // This is matte sanitation, not new painting or color-key background removal.
    if(a<=1)data.fill(0,i,i+4);
    if(a>90)bottom=Math.max(bottom,y);
  }
  if(bottom<0)throw new Error(`Empty cell ${index}`);
  let minX=256,maxX=-1;
  for(let y=Math.max(0,bottom-19);y<=bottom;y++)for(let x=0;x<256;x++){
    const i=(y*256+x)*4;
    if(data[i+3]>90&&data[i]<180&&data[i+1]<165&&data[i+2]<145){minX=Math.min(minX,x);maxX=Math.max(maxX,x);}
  }
  if(maxX<minX)throw new Error(`Cannot locate feet in cell ${index}`);
  const footCenter=(minX+maxX+1)/2;
  const left=Math.round(256-footCenter*scale),top=Math.round(448-(bottom+1)*scale);
  if(left<0||top<0||left+410>512||top+410>512)throw new Error(`Whole-cell registration out of bounds in ${index}`);
  const tile=await sharp(data,{raw:info}).resize(410,410,{kernel:'lanczos3'}).png().toBuffer();
  const file=`frames/idle.wait__${String(index).padStart(3,'0')}.png`;
  await sharp({create:{width:512,height:512,channels:4,background:{r:0,g:0,b:0,alpha:0}}}).composite([{input:tile,left,top}]).png().toFile(path.join(out,file));
  frames.push({file,durationFrames:1,durationMs:1000/12,registration:{sourceCell:cell,sourceFootCenter:footCenter,sourceFootBaseline:bottom+1,uniformScale:scale,translation:{x:left,y:top}}});
}

const clip={
  schemaVersion:1,characterId:'watercolor-duck',referenceVersion:'duck-v1-nostrils',
  animationMethod:'individually-drawn-frames',clipId:'idle.wait',
  stage:'frame-by-frame-review-candidate',frameRate:{numerator:12,denominator:1},
  canvas:{width:512,height:512},groundPivot:{x:256,y:448},loop:true,
  entryPose:'neutral',exitPose:'neutral',safeInterruptionFrames:[0,23],fallbackClip:'idle.wait',
  sourceBoard:{path:boardRelative,sha256:digest(boardBytes),grid:{columns:4,rows:6,cellWidth:256,cellHeight:256},localCopy:'source-board.png'},
  sourceReference:{path:referenceRelative,sha256:digest(await fs.readFile(path.join(root,referenceRelative))),neutralPoseLabel:'01'},
  technicalProcessing:['Exact 4×6 grid extraction in row-major order.','Background alpha 0/1 quantization cleared; alpha >=2 preserved.','One global whole-cell scale410/256 used for every frame.','Whole-frame translation only to register feet to pivot(256,448).'],
  noRigging:true,noMathematicalInbetweens:true,noSeparateTexturePass:true,
  reviewNotes:['24 full-duck drawings generated together in a single imagegen call; no frame assembled from parts.','Distinct paint/contour drawings may show watercolor boil and small shape variation; motion consistency requires visual review.','A few blink/settling poses are visually close, but exact duplicate validation is delegated to the shared validator.','First/final drawings are near-matching rather than mathematically identical; inspect the loop seam in video.'],
  frames,
};
await fs.writeFile(path.join(out,'clip.json'),JSON.stringify(clip,null,2)+'\n');

// Separate review contact sheet; labels never enter runtime frames.
const tiles=[];
for(let index=0;index<24;index++) {
  const x=index%6*200,y=Math.floor(index/6)*220;
  const image=await sharp(path.join(out,frames[index].file)).resize(200,200).flatten({background:'#292b31'}).png().toBuffer();
  tiles.push({input:image,left:x,top:y});
  tiles.push({input:Buffer.from(`<svg width="200" height="20"><rect width="200" height="20" fill="#292b31"/><text x="100" y="14" fill="#eee8dc" font-size="11" font-family="sans-serif" text-anchor="middle">${String(index+1).padStart(2,'0')}</text></svg>`),left:x,top:y+200});
}
await sharp({create:{width:1200,height:880,channels:4,background:'#292b31'}}).composite(tiles).png().toFile(path.join(out,'contact-sheet.png'));
console.log(JSON.stringify({clip:path.join(out,'clip.json'),frames:frames.length,frameRate:clip.frameRate,sourceBoardSha256:clip.sourceBoard.sha256},null,2));
