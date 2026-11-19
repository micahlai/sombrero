/** Full-frame playback only: no rigging, deformation, tweening or retexturing. */
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {sharp} from './image-library.mjs';
import {validateDrawnClip} from './validate-frame-assets.mjs';

export async function buildDrawnPreview(manifests,{out='assets/duck/frame-by-frame/v1/previews/idle-and-pet.mp4',cycles=2}={}){
  if(!Number.isInteger(cycles)||cycles<1)throw new Error('cycles must be positive integer');
  const clips=[];
  for(const manifest of manifests){const validation=await validateDrawnClip(manifest);if(validation.errors.length)throw new Error(`${manifest}: ${validation.errors.join('; ')}`);clips.push({clip:JSON.parse(await fs.readFile(manifest,'utf8')),dir:path.dirname(path.resolve(manifest)),validation});}
  const temp=await fs.mkdtemp(path.join(os.tmpdir(),'duck-drawn-preview-'));
  let count=0;
  try{
    for(const {clip,dir} of clips){
      const title=clip.clipId.includes('pet')?'A little pet':'Just waiting';
      const bg=Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="960" height="640"><rect width="960" height="640" fill="#bdcfda"/><rect x="0" y="0" width="960" height="38" fill="#d1dce2"/><circle cx="24" cy="19" r="4" fill="#9cabb4"/><circle cx="40" cy="19" r="4" fill="#9cabb4"/><circle cx="56" cy="19" r="4" fill="#9cabb4"/><text x="480" y="25" font-size="12" text-anchor="middle" font-family="Helvetica,Arial,sans-serif" fill="#53656e">Watercolor duck · frame-by-frame animation</text><text x="480" y="90" font-size="21" text-anchor="middle" font-family="Helvetica,Arial,sans-serif" fill="#475e69">${title}</text><text x="480" y="605" font-size="12" text-anchor="middle" font-family="Helvetica,Arial,sans-serif" fill="#536b78">12 fps · individually drawn frames · no rig deformation</text></svg>`);
      const background=await sharp(bg).png().toBuffer();
      for(let cycle=0;cycle<cycles;cycle++)for(const frame of clip.frames){
        const buffer=await sharp(background).composite([{input:path.join(dir,frame.file),left:224,top:90}]).png().toBuffer();
        for(let tick=0;tick<frame.durationFrames;tick++){const file=path.join(temp,`${String(count++).padStart(5,'0')}.png`);await fs.writeFile(file,buffer);}
      }
    }
    await fs.mkdir(path.dirname(out),{recursive:true});
    const ff=spawnSync('ffmpeg',['-hide_banner','-loglevel','error','-y','-framerate','12','-start_number','0','-i',path.join(temp,'%05d.png'),'-c:v','libx264','-crf','18','-preset','medium','-pix_fmt','yuv420p','-r','12','-movflags','+faststart',out],{encoding:'utf8'});
    if(ff.status!==0)throw new Error(ff.stderr||'ffmpeg failed');
    const probe=spawnSync('ffprobe',['-v','error','-select_streams','v:0','-show_entries','stream=r_frame_rate,avg_frame_rate,nb_frames,duration,width,height','-of','json',out],{encoding:'utf8'});
    if(probe.status!==0)throw new Error(probe.stderr||'ffprobe failed');
    const stream=JSON.parse(probe.stdout).streams[0];
    if(stream.avg_frame_rate!=='12/1'||stream.r_frame_rate!=='12/1'||Number(stream.nb_frames)!==count)throw new Error('Video frame count/rate mismatch');
    const report={status:'passed',output:out,frames:count,frameRate:'12/1',durationSeconds:count/12,cyclesPerClip:cycles,clips:clips.map(c=>({clipId:c.clip.clipId,frames:c.clip.frames.length,uniquePixelHashes:c.validation.uniquePixelHashes})),video:stream,animationMethod:'individually-drawn-frames',transforms:'Full-frame positioning onto presentation background only'};
    await fs.writeFile(path.join(path.dirname(out),'video-validation.json'),JSON.stringify(report,null,2)+'\n');
    const html=`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Watercolor duck — idle and pet</title><style>body{margin:0;background:#f4f1e7;color:#344751;font:15px system-ui}main{max-width:1000px;margin:40px auto;padding:0 20px}h1{font:38px Georgia,serif;font-weight:400}video{width:100%;border-radius:12px}p{line-height:1.6;color:#68767d}</style><main><h1>A little duck, drawn frame by frame.</h1><p>Idle and pet · 24 full drawings per clip · exact 12 fps</p><video controls autoplay loop muted playsinline src="${path.basename(out)}"></video><p>Each frame is a complete drawn pose. This preview adds only the backdrop and titles; no cutout rig, deformation, or interpolation is used.</p></main></html>`;
    await fs.writeFile(path.join(path.dirname(out),'index.html'),html);
    return report;
  }finally{await fs.rm(temp,{recursive:true,force:true});}
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===path.resolve(process.argv[1])){
  const manifests=process.argv.slice(2).filter(a=>!a.startsWith('--'));
  if(!manifests.length)throw new Error('Usage: node tools/build-frame-preview.mjs <idle clip.json> <pet clip.json> [--out=path]');
  const out=process.argv.find(a=>a.startsWith('--out='))?.slice(6);
  console.log(JSON.stringify(await buildDrawnPreview(manifests,{...(out?{out}:{})}),null,2));
}
