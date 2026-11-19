/** Validates independently drawn full-frame assets; never rigs or redraws art. */
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {sharp} from './image-library.mjs';

export async function inspectFrame(file){
  const metadata=await sharp(file).metadata();
  const {data,info}=await sharp(file).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  let left=info.width,top=info.height,right=-1,bottom=-1,count=0,soft=0;
  for(let y=0;y<info.height;y++)for(let x=0;x<info.width;x++){
    const i=(y*info.width+x)*4,a=data[i+3];
    if(a){left=Math.min(left,x);top=Math.min(top,y);right=Math.max(right,x);bottom=Math.max(bottom,y);count++;if(a<255)soft++;}
    else data.fill(0,i,i+4);
  }
  return {metadata,hash:crypto.createHash('sha256').update(data).digest('hex'),bounds:{x:left,y:top,width:right<0?0:right-left+1,height:bottom<0?0:bottom-top+1},nonzeroPixels:count,softAlphaPixels:soft,totalPixels:info.width*info.height};
}

export async function validateDrawnClip(manifestPath){
  const clip=JSON.parse(await fs.readFile(manifestPath,'utf8'));
  const directory=path.dirname(path.resolve(manifestPath)),errors=[],warnings=[],frames=[],hashes=new Map();
  const id=clip.clipId??clip.id??manifestPath;
  if(clip.schemaVersion!==1)errors.push('schemaVersion must be 1');
  if(clip.animationMethod!=='individually-drawn-frames')errors.push('animationMethod must declare individually-drawn-frames');
  if(clip.frameRate?.numerator!==12||clip.frameRate?.denominator!==1)errors.push('Frame rate must be exactly 12/1');
  if(clip.canvas?.width!==512||clip.canvas?.height!==512)errors.push('Canvas must be 512 × 512');
  if(clip.frames?.length!==24)errors.push('Each clip requires 24 separately drawn frame records');
  for(const [index,frame] of (clip.frames??[]).entries()){
    if(frame.durationFrames!==1)errors.push(`Frame ${index}: durationFrames must equal 1`);
    if(typeof frame.file!=='string'||path.isAbsolute(frame.file)||frame.file.split(/[\\/]/).includes('..')){errors.push(`Frame ${index}: expected safe relative image file`);continue;}
    try{
      const image=await inspectFrame(path.join(directory,frame.file));
      if(image.metadata.width!==512||image.metadata.height!==512||image.metadata.format!=='png'||!image.metadata.hasAlpha)errors.push(`Frame ${index}: expected 512 × 512 RGBA PNG`);
      if(!image.bounds.width)errors.push(`Frame ${index}: empty image`);
      if(image.nonzeroPixels>image.totalPixels*.98)errors.push(`Frame ${index}: solid alpha backdrop`);
      if(image.bounds.x<=0||image.bounds.y<=0||image.bounds.x+image.bounds.width>=512||image.bounds.y+image.bounds.height>=512)warnings.push(`Frame ${index}: visible paint touches canvas edge; inspect clipping`);
      if(hashes.has(image.hash))errors.push(`Frame ${index}: exact pixel duplicate of frame ${hashes.get(image.hash)}`);else hashes.set(image.hash,index);
      const {metadata,...stats}=image;frames.push({index,file:frame.file,...stats});
    }catch(error){errors.push(`Frame ${index}: ${error.message}`);}
  }
  if(!clip.sourceBoard?.path||!clip.sourceBoard?.sha256)errors.push('Source board path and SHA256 are required');
  else{
    const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
    try{const hash=crypto.createHash('sha256').update(await fs.readFile(path.resolve(root,clip.sourceBoard.path))).digest('hex');if(hash!==clip.sourceBoard.sha256)errors.push('Source board hash mismatch');}catch(error){errors.push(`Source board unavailable: ${error.message}`);}
  }
  return {status:errors.length?'failed':'passed',clipId:id,manifestPath,animationMethod:clip.animationMethod,frameRate:{numerator:12,denominator:1},frameCount:clip.frames?.length??0,uniquePixelHashes:hashes.size,durationSeconds:(clip.frames??[]).reduce((s,f)=>s+(f.durationFrames??0),0)/12,errors,warnings,frames,requiresVisualReview:true,note:'Distinct pixel hashes establish no exact duplicates; drawn motion and identity still require visual review.'};
}

if(process.argv[1]&&fileURLToPath(import.meta.url)===path.resolve(process.argv[1])){
  const inputs=process.argv.slice(2).filter(a=>!a.startsWith('--'));
  if(!inputs.length)throw new Error('Usage: node tools/validate-frame-assets.mjs <clip.json> [<clip.json>...] [--report=path]');
  const results=[];for(const input of inputs)results.push(await validateDrawnClip(input));
  const report={status:results.every(r=>r.status==='passed')?'passed':'failed',clips:results};
  const out=process.argv.find(a=>a.startsWith('--report='))?.slice(9);if(out){await fs.mkdir(path.dirname(out),{recursive:true});await fs.writeFile(out,JSON.stringify(report,null,2)+'\n');}
  console.log(JSON.stringify({status:report.status,clips:results.map(({frames,...r})=>r)},null,2));if(report.status!=='passed')process.exitCode=1;
}
