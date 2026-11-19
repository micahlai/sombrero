/** Technical full-frame slicing only. Originals remain unchanged; no synthesized drawings. */
import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import {sharp} from './image-library.mjs';
const root='Sources/PetAssets/Resources/Duck';
await fs.mkdir(root,{recursive:true});
const names=['1-look','2-look','3-sitdown','4-standup','5-sitting'];
const expected=[[6,6,6,5],[5,6,7,7],[5,5,5,5],[5,5,5,5],[5,5,5,5]];
const manifest={schemaVersion:1,timelineFPS:24,drawingFPS:6,holdFrames:4,frameWidth:320,frameHeight:320,anchor:{x:160,y:288},clips:[]};
for(const [id,name] of names.entries()){
 const source=`assets/duck/v2/${name}.png`, original=await fs.readFile(source);
 const {data,info}=await sharp(original).removeAlpha().raw().toBuffer({resolveWithObject:true});
 if(info.width!==4800||info.height!==3584)throw Error(`Unexpected sheet dimensions: ${name}`);
 const frames=[];
 for(let row=0;row<4;row++){
  const spans=[];let start=null,last=-1;
  for(let x=0;x<info.width;x++){
   let count=0;for(let y=row*896;y<(row+1)*896;y++){const i=(y*info.width+x)*3;if(data[i]-data[i+2]>35&&data[i+1]-data[i+2]>10&&data[i+2]<225)count++;}
   if(count>12){if(start===null)start=x;else if(x-last>100){spans.push([start,last]);start=x;}last=x;}
  }
  if(start!==null)spans.push([start,last]);
  if(spans.length!==expected[id][row])throw Error(`Unexpected drawing count ${name} row ${row}: ${spans.length}`);
  const centers=spans.map(([a,b])=>(a+b)/2);
  for(let col=0;col<spans.length;col++){
   const left=col===0?0:Math.round((centers[col-1]+centers[col])/2);
   const right=col===spans.length-1?4800:Math.round((centers[col]+centers[col+1])/2);
   const width=right-left,rgba=Buffer.alloc(width*896*4);
   let baseline=0,nonempty=0;
   for(let y=0;y<896;y++)for(let x=0;x<width;x++){
    const src=((row*896+y)*4800+left+x)*3,dst=(y*width+x)*4;
    const rgb=[data[src],data[src+1],data[src+2]];
    const alpha=Math.round(Math.max(0,Math.min(1,(255-Math.min(...rgb))/20))*255);
    for(let c=0;c<3;c++)rgba[dst+c]=alpha?Math.max(0,Math.round((rgb[c]-255*(1-alpha/255))/(alpha/255))):0;
    rgba[dst+3]=alpha;
    // Ignore near-white background; retain authored brown ground lines.
    if(rgb[0]-rgb[2]>25&&rgb[1]-rgb[2]>8&&rgb[2]<210){baseline=Math.max(baseline,y);nonempty++;}
   }
   // Flood only neutral near-white backdrop from the perimeter. This removes source
   // background noise and white fringe without deleting enclosed pale bill/wing paint.
   const visited=new Uint8Array(width*896),queue=new Int32Array(width*896);let head=0,tail=0;
   const visit=(x,y)=>{const pixel=y*width+x;if(visited[pixel])return;visited[pixel]=1;
    const i=pixel*4;
    // Use original RGB for classification, before white unmatting.
    const src=((row*896+y)*4800+left+x)*3;
    const low=Math.min(data[src],data[src+1],data[src+2]),high=Math.max(data[src],data[src+1],data[src+2]);
    if(low>210&&high-low<45){rgba[i+3]=0;queue[tail++]=pixel;}
   };
   for(let x=0;x<width;x++){visit(x,0);visit(x,895);}for(let y=0;y<896;y++){visit(0,y);visit(width-1,y);}
   while(head<tail){const p=queue[head++],x=p%width,y=Math.floor(p/width);if(x>0)visit(x-1,y);if(x+1<width)visit(x+1,y);if(y>0)visit(x,y-1);if(y<895)visit(x,y+1);}
   if(nonempty<1000)throw Error(`Empty drawing ${name}/${frames.length}`);
   const scale=1/3;
   const resized=await sharp(rgba,{raw:{width,height:896,channels:4}}).resize(Math.round(width*scale),Math.round(896*scale)).png().toBuffer();
   const x=Math.round(160-(centers[col]-left)*scale),y=Math.round(288-baseline*scale);
   const cropLeft=Math.max(0,-x),cropTop=Math.max(0,-y);
   const prepared=await sharp(resized).extract({left:cropLeft,top:cropTop,width:Math.min(Math.round(width*scale)-cropLeft,320-Math.max(0,x)),height:Math.min(Math.round(896*scale)-cropTop,320-Math.max(0,y))}).png().toBuffer();
   const resource=`${id+1}-${String(frames.length).padStart(3,'0')}.png`;
   await sharp({create:{width:320,height:320,channels:4,background:'#00000000'}}).composite([{input:prepared,left:Math.max(0,x),top:Math.max(0,y)}]).png().toFile(`${root}/${resource}`);
   frames.push({resource,durationFrames:4,sourceRect:{x:left,y:row*896,width,height:896},registration:{x,y,scale,sourceBaseline:baseline}});
  }
 }
 manifest.clips.push({state:id+1,name,source,sourceSHA256:crypto.createHash('sha256').update(original).digest('hex'),rowCounts:expected[id],frames});
 console.log(`${name}: ${frames.length} drawings, ${frames.length/6}s`);
}
await fs.writeFile(`${root}/manifest.json`,JSON.stringify(manifest,null,2)+'\n');
