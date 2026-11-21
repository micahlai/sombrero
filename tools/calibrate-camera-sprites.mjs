/** Review camera endpoints, then --write clip-wide transforms. Source PNGs stay unchanged. */
import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import {sharp} from './image-library.mjs';

const root='assets/duck/final-v1', output='.build/camera-review';
await fs.mkdir(output,{recursive:true});
const calibration=JSON.parse(await fs.readFile(`${root}/animation-scales.json`,'utf8'));
const inventory={};
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const union=boxes=>boxes.reduce((a,b)=>a?[Math.min(a[0],b[0]),Math.min(a[1],b[1]),Math.max(a[2],b[2]),Math.max(a[3],b[3])]:[...b],null);
for(const id of ['1a','6a','6b']) {
  const files=(await fs.readdir(`${root}/${id}`)).filter(x=>x.endsWith('.png')).sort((a,b)=>a.localeCompare(b,undefined,{numeric:true}));
  const frames=[];
  for(const file of files) {
    const bytes=await fs.readFile(`${root}/${id}/${file}`);
    const {data,info}=await sharp(bytes).ensureAlpha().raw().toBuffer({resolveWithObject:true});
    const bounds=[info.width,info.height,-1,-1], visible=[...bounds];
    for(let y=0;y<info.height;y++) for(let x=0;x<info.width;x++) {
      const alpha=data[(y*info.width+x)*4+3];
      for(const [box,threshold] of [[bounds,1],[visible,32]]) if(alpha>=threshold) {
        box[0]=Math.min(box[0],x); box[1]=Math.min(box[1],y); box[2]=Math.max(box[2],x+1); box[3]=Math.max(box[3],y+1);
      }
    }
    if(bounds[2]<0) throw Error(`Empty drawing: ${id}/${file}`);
    const head=[info.width,-1];
    for(let y=visible[1];y<visible[1]+(visible[3]-visible[1])*.6;y++) for(let x=visible[0];x<visible[2];x++) {
      const n=(y*info.width+x)*4;
      if(data[n+3]>=32&&data[n]>130&&data[n+1]>100&&data[n]-data[n+2]>35&&data[n+1]-data[n+2]>15) {
        head[0]=Math.min(head[0],x); head[1]=Math.max(head[1],x+1);
      }
    }
    if(head[1]<0) throw Error(`Head registration unavailable: ${id}/${file}`);
    frames.push({file,width:info.width,height:info.height,sha256:hash(bytes),alphaBounds:bounds,alpha32Bounds:visible,
      alignmentFeatures:{headWidth:head[1]-head[0],headCenterX:(head[1]+head[0])/2,silhouetteHeight:visible[3]-visible[1],baselineY:visible[3]}});
  }
  inventory[id]=frames;
}
await fs.writeFile(`${output}/measurements.json`,JSON.stringify(inventory,null,2)+'\n');
const thumbs=[];
for(const [row,id] of ['1a','6a','6b'].entries()) {
  const samples=[...inventory[id].slice(0,2),...inventory[id].slice(-2)];
  for(const [col,frame] of samples.entries()) {
    const thumb=await sharp(`${root}/${id}/${frame.file}`).resize(280,200,{fit:'contain',background:'#eeeeee'}).flatten({background:'#eeeeee'}).png().toBuffer();
    thumbs.push({input:thumb,left:col*300,top:row*230+25});
    thumbs.push({input:Buffer.from(`<svg width="280" height="25"><text x="5" y="18" font-size="15">${id} ${frame.file}</text></svg>`),left:col*300,top:row*230});
  }
}
await sharp({create:{width:1200,height:690,channels:4,background:'#eeeeee'}}).composite(thumbs).png().toFile(`${output}/source-endpoints.png`);
if(!process.argv.includes('--write')) { process.stdout.write(`${output}/source-endpoints.png\n`); process.exit(0); }
const mean=(frames,key)=>frames.reduce((n,f)=>n+f.alignmentFeatures[key],0)/frames.length;
function fit(source,target,transform) {
  const sw=mean(source,'headWidth'),sh=mean(source,'silhouetteHeight');
  const tw=mean(target,'headWidth')*transform.scale,th=mean(target,'silhouetteHeight')*transform.scale;
  const scale=(sw*tw/406**2+sh*th/685**2)/(sw**2/406**2+sh**2/685**2);
  return {scale,offsetX:mean(target,'headCenterX')*transform.scale+transform.offsetX-mean(source,'headCenterX')*scale,
    offsetY:mean(target,'baselineY')*transform.scale+transform.offsetY-mean(source,'baselineY')*scale};
}
const transforms={};
transforms['6a']=fit(inventory['6a'].slice(0,2),inventory['1a'].slice(-2),calibration.animations['1a']);
transforms['6b']=fit([...inventory['6b'].slice(0,2),...inventory['6b'].slice(-2)],inventory['6a'].slice(-2),transforms['6a']);
for(const id of ['6a','6b']) {
  const frames=inventory[id],t=transforms[id];
  for(const key of Object.keys(t)) t[key]=Number(t[key].toFixed(6));
  const apply=b=>[b[0]*t.scale+t.offsetX,b[1]*t.scale+t.offsetY,b[2]*t.scale+t.offsetX,b[3]*t.scale+t.offsetY].map(x=>Math.round(x*1000)/1000);
  const alpha=union(frames.map(f=>f.alphaBounds)),visible=union(frames.map(f=>f.alpha32Bounds)),placed=apply(alpha);
  if(placed[0]<0||placed[1]<0||placed[2]>calibration.canvas.width||placed[3]>calibration.canvas.height) throw Error(`${id} exceeds the shared canvas`);
  calibration.animations[id]={status:'calibrated',...t,sourceFrameCount:frames.length,
    sourceFrameSize:{width:frames[0].width,height:frames[0].height},
    sampleFrames:[...frames.slice(0,2).map((f,i)=>({...f,index:i,role:i?'second':'first'})),
      ...frames.slice(-2).map((f,i)=>({...f,index:frames.length-2+i,role:i?'last':'penultimate'}))],
    sourceInventorySHA256:hash(frames.map(f=>`${f.file}:${f.sha256}\n`).join('')),
    sourceAlphaBounds:alpha,sourceVisibleBounds:visible,transformedAlphaBounds:placed,transformedVisibleBounds:apply(visible),
    notes:'Endpoint drawings reviewed. One uniform transform per clip: 6a entry registered to standing 1a, 6b registered to the camera-holding exit of 6a. Source PNGs unchanged; all-frame alpha containment checked.'};
}
calibration.adjacencyChecks=calibration.adjacencyChecks.filter(e=>!(['1a','6a'].includes(e.from)&&['6a','6b'].includes(e.to)));
for(const [from,to] of [['1a','6a'],['6a','6b']]) {
  const a=inventory[from].slice(-2),b=inventory[to].slice(0,2),ta=calibration.animations[from],tb=calibration.animations[to];
  calibration.adjacencyChecks.push({from,to,samplePolicy:'last two versus first two',
    baselineDeltaPixels:mean(b,'baselineY')*tb.scale+tb.offsetY-mean(a,'baselineY')*ta.scale-ta.offsetY,
    headCenterDeltaPixels:mean(b,'headCenterX')*tb.scale+tb.offsetX-mean(a,'headCenterX')*ta.scale-ta.offsetX});
}
calibration.review.availableAnimations=[...new Set([...calibration.review.availableAnimations,'6a','6b'])];
calibration.review.uniqueSampleCount=new Set(Object.entries(calibration.animations).flatMap(([id,v])=>(v.sampleFrames??[]).map(f=>`${id}/${f.file}`))).size;
calibration.review.updates.push({reviewedAtUTC:new Date().toISOString(),animations:['6a','6b'],method:'Reviewed endpoint contact sheet, uniform head/baseline registration and all-frame containment; originals unchanged.',checkedFrameCounts:{'6a':inventory['6a'].length,'6b':inventory['6b'].length}});
await fs.writeFile(`${root}/animation-scales.json`,JSON.stringify(calibration,null,2)+'\n');
process.stdout.write('Calibrated 6a and 6b; source drawings unchanged\n');
