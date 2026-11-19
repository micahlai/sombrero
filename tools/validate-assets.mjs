import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {sharp,walk} from './asset-contract.mjs';

export async function alphaBounds(input) {
  const {data,info}=await sharp(input).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  let left=info.width,top=info.height,right=-1,bottom=-1,opaque=0,soft=0;
  for(let y=0;y<info.height;y++)for(let x=0;x<info.width;x++){
    const a=data[(y*info.width+x)*4+3];
    if(a){left=Math.min(left,x);right=Math.max(right,x);top=Math.min(top,y);bottom=Math.max(bottom,y);opaque++;if(a<255)soft++;}
  }
  return {x:left,y:top,width:right<0?0:right-left+1,height:bottom<0?0:bottom-top+1,nonzeroPixels:opaque,softAlphaPixels:soft,totalPixels:info.width*info.height};
}

export async function validateAssets(directory='assets/duck/v1/clips',{root=process.cwd()}={}) {
  const files=await walk(directory);
  const errors=[],warnings=[],clips=[],ids=new Set();
  if(!files.length)errors.push('No clip.json files found; production frames have not been exported.');
  const lock=JSON.parse(await fs.readFile(path.join(root,'docs/character-reference.json'),'utf8'));
  const actualHash=crypto.createHash('sha256').update(await fs.readFile(path.join(root,lock.reference.path))).digest('hex');
  if(actualHash!==lock.reference.sha256)errors.push('Character reference hash differs from reference lock.');
  const masterBytes=await fs.readFile(path.join(root,'assets/duck/v1/source/master.json'));
  const master=JSON.parse(masterBytes.toString('utf8'));
  const masterHash=crypto.createHash('sha256').update(masterBytes).digest('hex');
  for(const file of files){
    let clip;try{clip=JSON.parse(await fs.readFile(file,'utf8'));}catch(error){errors.push(`${file}: ${error.message}`);continue;}
    const label=clip.clipId??file;
    const err=s=>errors.push(`${label}: ${s}`);
    if(clip.schemaVersion!==1)err('schemaVersion must be 1');
    if(clip.characterId!=='watercolor-duck')err('wrong characterId');
    if(clip.referenceVersion!==lock.referenceVersion)err('referenceVersion differs from shared lock');
    if(clip.sourceMasterVersion!==master.masterVersion)err('sourceMasterVersion differs from shared master');
    if(clip.sourceMasterSha256!==masterHash)err('sourceMasterSha256 differs from frozen master bytes');
    if(clip.sourceReferenceSha256!==lock.reference.sha256)err('sourceReferenceSha256 differs from shared reference');
    if(!clip.clipId||!/^[a-z][a-z0-9]*(?:\.[a-z0-9]+)+$/.test(clip.clipId))err('invalid clipId');
    if(ids.has(clip.clipId))err('duplicate clipId');ids.add(clip.clipId);
    if(clip.canvas?.width!==512||clip.canvas?.height!==512)err('canvas must be 512 × 512');
    if(clip.groundPivot?.x!==256||clip.groundPivot?.y!==448)err('groundPivot must be (256,448)');
    if(clip.frameRate?.numerator!==12||clip.frameRate?.denominator!==1)err('frameRate must be exactly 12/1');
    if(typeof clip.loop!=='boolean')err('loop must be boolean');
    if(!clip.entryPose||!clip.exitPose)err('entryPose and exitPose required');
    if(!Array.isArray(clip.frames)||!clip.frames.length){err('frames array is empty');continue;}
    if(!Array.isArray(clip.safeInterruptionFrames)||clip.safeInterruptionFrames.some(i=>!Number.isInteger(i)||i<0||i>=clip.frames.length))err('invalid safeInterruptionFrames');
    const frameChecks=new Map();
    let ticks=0;
    for(const [index,frame] of clip.frames.entries()){
      const frameLabel=`frame ${index}`;
      if(!Number.isInteger(frame.durationFrames)||frame.durationFrames<1)err(`${frameLabel}: durationFrames must be positive integer`);else ticks+=frame.durationFrames;
      if(frame.durationMs!==undefined&&Math.abs(frame.durationMs-frame.durationFrames*1000/12)>0.001)err(`${frameLabel}: durationMs does not match exact 12fps tick duration`);
      if(typeof frame.file!=='string'||path.isAbsolute(frame.file)||frame.file.split(/[\\/]/).includes('..')){err(`${frameLabel}: file must be a safe relative path`);continue;}
      const image=path.join(path.dirname(file),frame.file);
      if(!frameChecks.has(image)){
        try{
          const metadata=await sharp(image).metadata();
          if(metadata.format!=='png'||metadata.width!==512||metadata.height!==512||!metadata.hasAlpha)err(`${frameLabel}: requires 512 × 512 RGBA PNG`);
          const bounds=await alphaBounds(image);
          if(!bounds.width)err(`${frameLabel}: character image is empty`);
          if(bounds.nonzeroPixels>bounds.totalPixels*0.97)err(`${frameLabel}: near-solid alpha suggests a backdrop`);
          if(bounds.x===0||bounds.y===0||bounds.x+bounds.width===512||bounds.y+bounds.height===512)warnings.push(`${label} ${frameLabel}: visible pixels touch canvas edge; inspect clipping`);
          frameChecks.set(image,bounds);
        }catch(error){err(`${frameLabel}: cannot read ${frame.file}: ${error.message}`);}
      }
      for(const [name,attachment] of Object.entries(frame.attachments??{})){
        if(!attachment||typeof attachment!=='object'){err(`${frameLabel}: attachment ${name} must be object`);continue;}
        for(const [key,value] of Object.entries(attachment))if(typeof value==='number'&&!Number.isFinite(value))err(`${frameLabel}: ${name}.${key} must be finite`);
        if(attachment.x!==undefined&&(attachment.x<0||attachment.x>512)||attachment.y!==undefined&&(attachment.y<0||attachment.y>512))warnings.push(`${label} ${frameLabel}: attachment ${name} outside canvas`);
      }
      if(frame.markers!==undefined&&(!Array.isArray(frame.markers)||frame.markers.some(m=>typeof m!=='string')))err(`${frameLabel}: markers must be an array of strings`);
    }
    clips.push({clipId:clip.clipId,frames:clip.frames.length,uniqueFiles:frameChecks.size,ticks,durationMs:ticks*1000/12,file:path.relative(root,path.resolve(file))});
  }
  for(const file of files){const c=JSON.parse(await fs.readFile(file,'utf8'));if(c.fallbackClip&&!ids.has(c.fallbackClip))warnings.push(`${c.clipId}: fallback ${c.fallbackClip} is not exported in this selection`);}
  return {status:errors.length?'failed':'passed',referenceVersion:lock.referenceVersion,sourceMasterVersion:master.masterVersion,sourceMasterSha256:masterHash,frameRate:{numerator:12,denominator:1},clipCount:clips.length,frameRecords:clips.reduce((s,c)=>s+c.frames,0),errors,warnings,clips,visualIdentityRequiresHumanReview:true};
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===path.resolve(process.argv[1])){
  const directory=process.argv.find(a=>a.startsWith('--clips='))?.slice(8)??'assets/duck/v1/clips';
  const report=await validateAssets(directory);
  const out=process.argv.find(a=>a.startsWith('--report='))?.slice(9);
  if(out){await fs.mkdir(path.dirname(out),{recursive:true});await fs.writeFile(out,JSON.stringify(report,null,2)+'\n');}
  console.log(JSON.stringify(report,null,2));if(report.errors.length)process.exitCode=1;
}
