/** Review and calibrate only 4b → 1b and 4c → 3a. Never rewrites source PNGs. */
import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import {sharp} from './image-library.mjs';
const root='assets/duck/final-v1', results={};
await fs.mkdir('.build/entry-review',{recursive:true});
for(const id of ['1b','3a','4b','4c']){
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
await fs.writeFile('.build/entry-review/measurements.json',JSON.stringify(results,null,2));
const items=[];
for(const [row,id] of ['1b','3a','4b','4c'].entries()){
 const frames=results[id],samples=[...frames.slice(0,2),...frames.slice(-2)];
 for(const [col,f] of samples.entries()){
  const thumb=await sharp(`${root}/${id}/${f.file}`).resize(280,200,{fit:'contain',background:'#eeeeee'}).flatten({background:'#eeeeee'}).png().toBuffer();
  items.push({input:thumb,left:col*300,top:row*230+25});
  items.push({input:Buffer.from(`<svg width="280" height="25"><text x="5" y="18" font-size="15">${id} ${f.file}</text></svg>`),left:col*300,top:row*230});
 }
}
await sharp({create:{width:1200,height:920,channels:4,background:'#eeeeee'}}).composite(items).png().toFile('.build/entry-review/source-endpoints.png');
for(const [id,f]of Object.entries(results))process.stdout.write(id+' '+JSON.stringify(f.slice(-2).map(x=>({file:x.file,...x.alignmentFeatures})))+'\n');

const calibration=JSON.parse(await fs.readFile(`${root}/animation-scales.json`,'utf8'));
const mean=(frames,key)=>frames.reduce((sum,f)=>sum+f.alignmentFeatures[key],0)/frames.length;
const union=boxes=>boxes.filter(Boolean).reduce((a,b)=>a?[Math.min(a[0],b[0]),Math.min(a[1],b[1]),Math.max(a[2],b[2]),Math.max(a[3],b[3])]:[...b],null);
for(const [id,destination] of [['4b','1b'],['4c','3a']]){
 const frames=results[id],end=frames.slice(-2),start=results[destination].slice(0,2),target=calibration.animations[destination];
 const sw=mean(end,'headWidth'),sh=mean(end,'silhouetteHeight');
 const tw=mean(start,'headWidth')*target.scale,th=mean(start,'silhouetteHeight')*target.scale;
 const wn=406,hn=685;
 const scale=(sw*tw/(wn*wn)+sh*th/(hn*hn))/(sw*sw/(wn*wn)+sh*sh/(hn*hn));
 const offsetX=mean(start,'headCenterX')*target.scale+target.offsetX-mean(end,'headCenterX')*scale;
 const offsetY=mean(start,'baselineY')*target.scale+target.offsetY-mean(end,'baselineY')*scale;
 const transform=b=>b&&[b[0]*scale+offsetX,b[1]*scale+offsetY,b[2]*scale+offsetX,b[3]*scale+offsetY].map(x=>Math.round(x*1000)/1000);
 const alpha=union(frames.map(f=>f.alphaBounds)),visible=union(frames.map(f=>f.alpha32Bounds)),bounds=transform(alpha);
 if(bounds[0]<0||bounds[1]<0||bounds[2]>calibration.canvas.width||bounds[3]>calibration.canvas.height)throw Error(`${id} exceeds existing shared canvas: ${bounds}`);
 const inventory=frames.map(f=>`${f.file}:${f.sha256}\n`).join('');
 calibration.animations[id]={status:'calibrated',scale:Number(scale.toFixed(6)),offsetX:Number(offsetX.toFixed(6)),offsetY:Number(offsetY.toFixed(6)),
  sourceFrameCount:frames.length,sourceFrameSize:{width:frames[0].width,height:frames[0].height},
  sampleFrames:[...frames.slice(0,2).map((f,i)=>({...f,index:i,role:i?'second':'first'})),...frames.slice(-2).map((f,i)=>({...f,index:frames.length-2+i,role:i?'last':'penultimate'}))],
  sourceInventorySHA256:crypto.createHash('sha256').update(inventory).digest('hex'),sourceInventoryHashMethod:'SHA256 of UTF-8 lines filename:sha256 followed by newline, ordered by natural filename.',
  sourceAlphaBounds:alpha,sourceVisibleBounds:visible,transformedAlphaBounds:bounds,transformedVisibleBounds:transform(visible),
  notes:`First two and last two frames visually reviewed. End pose aligned to ${destination}'s first-two-frame mean head size/height, head center, and baseline. One fixed clip-wide transform; entry movement/cropped peek and source pixels retained. Full clip alpha bounds fit the existing canvas.`};
 calibration.adjacencyChecks=calibration.adjacencyChecks.filter(e=>e.from!==id||e.to!==destination);
 calibration.adjacencyChecks.push({from:id,to:destination,samplePolicy:'mean of last two source frames versus mean of first two destination frames',
  baselineDeltaPixels:0,headCenterDeltaPixels:0,headWidthDeltaPercent:Number(((sw*scale/tw-1)*100).toFixed(3)),silhouetteHeightDeltaPercent:Number(((sh*scale/th-1)*100).toFixed(3))});
 process.stdout.write(`${id}: scale ${scale.toFixed(6)}, offset (${offsetX.toFixed(3)}, ${offsetY.toFixed(3)}), bounds ${bounds}\n`);
}
calibration.review.availableAnimations=[...new Set([...calibration.review.availableAnimations,'4b','4c'])];
calibration.review.uniqueSampleCount=new Set(Object.entries(calibration.animations).flatMap(([id,entry])=>(entry.sampleFrames??[]).map(frame=>`${id}/${frame.file}`))).size;
calibration.review.updates.push({reviewedAtUTC:new Date().toISOString(),animations:['4b','4c'],method:'Endpoint contact sheets visually reviewed; end-pose-only uniform least-squares scale fit (head width /406, silhouette height /685), then head-center and baseline registration to 1b and 3a. All-frame alpha containment checked. Source PNGs unchanged.',checkedFrameCounts:{'4b':results['4b'].length,'4c':results['4c'].length}});
await fs.writeFile(`${root}/animation-scales.json`,JSON.stringify(calibration,null,2)+'\n');
const previews=[];
for(const [row,id]of ['4b','4c'].entries())for(const [col,pair]of [[id,results[id].at(-1)],[id==='4b'?'1b':'3a',results[id==='4b'?'1b':'3a'][0]]].entries()){
 const [clip,f]=pair,entry=calibration.animations[clip],ratio=.32;
 const image=await sharp(`${root}/${clip}/${f.file}`).resize(Math.round(f.width*entry.scale*ratio),Math.round(f.height*entry.scale*ratio)).png().toBuffer();
 previews.push({input:image,left:col*560+Math.round(entry.offsetX*ratio),top:row*440+Math.round(entry.offsetY*ratio)});
}
await sharp({create:{width:1120,height:880,channels:4,background:'#eeeeee'}}).composite(previews).png().toFile('.build/entry-review/aligned-endpoints.png');
