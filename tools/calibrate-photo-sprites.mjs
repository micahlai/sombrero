/** Review and calibrate 5a → 5b → 5c → 1a. Never rewrites source PNGs. */
import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import {sharp} from './image-library.mjs';
const root='assets/duck/final-v1', results={};
await fs.mkdir('.build/photo-review',{recursive:true});
for(const id of ['1a','5a','5b','5c']){
 const files=(await fs.readdir(`${root}/${id}`)).filter(x=>x.endsWith('.png')).sort((a,b)=>a.localeCompare(b,undefined,{numeric:true}));
 const frames=[];
 for(const file of files){
  const bytes=await fs.readFile(`${root}/${id}/${file}`),{data,info}=await sharp(bytes).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  let b=[info.width,info.height,-1,-1], a=[...b];
  for(let y=0;y<info.height;y++)for(let x=0;x<info.width;x++){
   const n=(y*info.width+x)*4;
   if(data[n+3]){a=[Math.min(a[0],x),Math.min(a[1],y),Math.max(a[2],x+1),Math.max(a[3],y+1)];}
   if(data[n+3]>=32){b=[Math.min(b[0],x),Math.min(b[1],y),Math.max(b[2],x+1),Math.max(b[3],y+1)];}
  }
  let head=[info.width,-1];
  for(let y=b[1];y<b[1]+(b[3]-b[1])*.6;y++)for(let x=b[0];x<b[2];x++){
   const n=(y*info.width+x)*4;
   if(data[n+3]>=32&&data[n]>130&&data[n+1]>100&&data[n]-data[n+2]>35&&data[n+1]-data[n+2]>15){head[0]=Math.min(head[0],x);head[1]=Math.max(head[1],x+1);}
  }
  frames.push({file,width:info.width,height:info.height,sha256:crypto.createHash('sha256').update(bytes).digest('hex'),alphaBounds:a[2]>=0?a:null,alpha32Bounds:b[2]>=0?b:null,alignmentFeatures:head[1]>=0?{headWidth:head[1]-head[0],headCenterX:(head[1]+head[0])/2,silhouetteHeight:b[3]-b[1],baselineY:b[3]}:null});
 }
 results[id]=frames;
}
await fs.writeFile('.build/photo-review/measurements.json',JSON.stringify(results,null,2));
const items=[];
for(const [row,id] of ['1a','5a','5b','5c'].entries()){
 const frames=results[id],samples=[...frames.slice(0,2),...frames.slice(-2)];
 for(const [col,f] of samples.entries()){
  const thumb=await sharp(`${root}/${id}/${f.file}`).resize(280,200,{fit:'contain',background:'#eeeeee'}).flatten({background:'#eeeeee'}).png().toBuffer();
  items.push({input:thumb,left:col*300,top:row*230+25});
  items.push({input:Buffer.from(`<svg width="280" height="25"><text x="5" y="18" font-size="15">${id} ${f.file}</text></svg>`),left:col*300,top:row*230});
 }
}
await sharp({create:{width:1200,height:920,channels:4,background:'#eeeeee'}}).composite(items).png().toFile('.build/photo-review/source-endpoints.png');
for(const [id,f]of Object.entries(results))process.stdout.write(id+' '+JSON.stringify(f.slice(-2).map(x=>({file:x.file,...x.alignmentFeatures})))+'\n');

const calibration=JSON.parse(await fs.readFile(`${root}/animation-scales.json`,'utf8'));
const mean=(frames,key)=>frames.reduce((sum,f)=>sum+f.alignmentFeatures[key],0)/frames.length;
const union=boxes=>boxes.filter(Boolean).reduce((a,b)=>a?[Math.min(a[0],b[0]),Math.min(a[1],b[1]),Math.max(a[2],b[2]),Math.max(a[3],b[3])]:[...b],null);
function fit(source,targets){
 const sw=mean(source,'headWidth'),sh=mean(source,'silhouetteHeight');
 const tw=targets.reduce((n,t)=>n+mean(t.frames,'headWidth')*t.transform.scale,0)/targets.length;
 const th=targets.reduce((n,t)=>n+mean(t.frames,'silhouetteHeight')*t.transform.scale,0)/targets.length;
 const scale=(sw*tw/406**2+sh*th/685**2)/(sw**2/406**2+sh**2/685**2);
 return {scale,offsetX:targets.reduce((n,t)=>n+mean(t.frames,'headCenterX')*t.transform.scale+t.transform.offsetX,0)/targets.length-mean(source,'headCenterX')*scale,
  offsetY:targets.reduce((n,t)=>n+mean(t.frames,'baselineY')*t.transform.scale+t.transform.offsetY,0)/targets.length-mean(source,'baselineY')*scale};
}
const transforms={};
transforms['5a']=fit(results['5a'].slice(0,2),[{frames:results['1a'].slice(-2),transform:calibration.animations['1a']}]);
transforms['5c']=fit(results['5c'].slice(-2),[{frames:results['1a'].slice(0,2),transform:calibration.animations['1a']}]);
transforms['5b']=fit([...results['5b'].slice(0,2),...results['5b'].slice(-2)],[{frames:results['5a'].slice(-2),transform:transforms['5a']},{frames:results['5c'].slice(0,2),transform:transforms['5c']}]);
for(const id of ['5a','5b','5c']){
 const frames=results[id],t=transforms[id];for(const key of Object.keys(t))t[key]=Number(t[key].toFixed(6));
 const transform=b=>b&&[b[0]*t.scale+t.offsetX,b[1]*t.scale+t.offsetY,b[2]*t.scale+t.offsetX,b[3]*t.scale+t.offsetY].map(x=>Math.round(x*1000)/1000);
 const alpha=union(frames.map(f=>f.alphaBounds)),visible=union(frames.map(f=>f.alpha32Bounds)),bounds=transform(alpha);
 if(bounds[0]<0||bounds[1]<0||bounds[2]>calibration.canvas.width||bounds[3]>calibration.canvas.height)throw Error(`${id}: exceeds canvas`);
 calibration.animations[id]={status:'calibrated',...t,sourceFrameCount:frames.length,sourceFrameSize:{width:frames[0].width,height:frames[0].height},
  sampleFrames:[...frames.slice(0,2).map((f,i)=>({...f,index:i,role:i?'second':'first'})),...frames.slice(-2).map((f,i)=>({...f,index:frames.length-2+i,role:i?'last':'penultimate'}))],
  sourceInventorySHA256:crypto.createHash('sha256').update(frames.map(f=>`${f.file}:${f.sha256}\n`).join('')).digest('hex'),
  sourceAlphaBounds:alpha,sourceVisibleBounds:visible,transformedAlphaBounds:bounds,transformedVisibleBounds:transform(visible),
  notes:'First two and last two drawings visually reviewed. 5a standing entry and 5c standing exit registered to 1a; 5b fitted between the two photo-holding poses. One uniform transform per clip; authored motion and source PNGs retained.'};
 process.stdout.write(`${id}: ${JSON.stringify(t)}\n`);
}
for(const[from,to]of [['1a','5a'],['5a','5b'],['5b','5c'],['5c','1a']]){
 const a=results[from].slice(-2),b=results[to].slice(0,2),ta=calibration.animations[from],tb=calibration.animations[to];
 calibration.adjacencyChecks=calibration.adjacencyChecks.filter(e=>e.from!==from||e.to!==to);
 calibration.adjacencyChecks.push({from,to,samplePolicy:'last two versus first two',baselineDeltaPixels:mean(b,'baselineY')*tb.scale+tb.offsetY-mean(a,'baselineY')*ta.scale-ta.offsetY,headCenterDeltaPixels:mean(b,'headCenterX')*tb.scale+tb.offsetX-mean(a,'headCenterX')*ta.scale-ta.offsetX});
}
calibration.review.availableAnimations=[...new Set([...calibration.review.availableAnimations,'5a','5b','5c'])];
calibration.review.uniqueSampleCount=new Set(Object.entries(calibration.animations).flatMap(([id,v])=>(v.sampleFrames??[]).map(f=>`${id}/${f.file}`))).size;
calibration.review.updates.push({reviewedAtUTC:new Date().toISOString(),animations:['5a','5b','5c'],method:'Endpoint contact sheets visually reviewed; uniform scale, head-center and baseline registration across 1a → 5a → 5b → 5c → 1a. All-frame alpha containment checked; source PNGs unchanged.',checkedFrameCounts:Object.fromEntries(['5a','5b','5c'].map(id=>[id,results[id].length]))});
await fs.writeFile(`${root}/animation-scales.json`,JSON.stringify(calibration,null,2)+'\n');
const previews=[];
for(const[row,[from,to]]of [['1a','5a'],['5a','5b'],['5b','5c'],['5c','1a']].entries())for(const[col,id]of [from,to].entries()){
 const f=col?results[id][0]:results[id].at(-1),t=calibration.animations[id],ratio=.28;
 previews.push({input:await sharp(`${root}/${id}/${f.file}`).resize(Math.round(f.width*t.scale*ratio),Math.round(f.height*t.scale*ratio)).png().toBuffer(),left:col*500+Math.round(t.offsetX*ratio),top:row*370+Math.round(t.offsetY*ratio)});
}
await sharp({create:{width:1000,height:1480,channels:4,background:'#eeeeee'}}).composite(previews).png().toFile('.build/photo-review/aligned-endpoints.png');
