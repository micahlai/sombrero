import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {sharp,walk} from './asset-contract.mjs';
import {alphaBounds,validateAssets} from './validate-assets.mjs';

/** Shelf packing with deduplication, preserved trim offsets and edge extrusion. */
export async function packAssets(directory='assets/duck/v1/clips',out='assets/duck/v1/atlas'){
  const validation=await validateAssets(directory);
  if(validation.errors.length)throw new Error(`Cannot pack invalid assets: ${validation.errors.join('; ')}`);
  const files=await walk(directory),sources=[],byHash=new Map(),clips={};
  for(const file of files){const clip=JSON.parse(await fs.readFile(file,'utf8'));const packedFrames=[];
    for(const [index,frame] of clip.frames.entries()){
      const input=await fs.readFile(path.join(path.dirname(file),frame.file));
      const hash=crypto.createHash('sha256').update(input).digest('hex');
      let source=byHash.get(hash);
      if(!source){const b=await alphaBounds(input);source={id:`texture-${sources.length.toString().padStart(4,'0')}`,input,bounds:{left:b.x,top:b.y,width:b.width,height:b.height},w:b.width+8,h:b.height+8};byHash.set(hash,source);sources.push(source);}
      const {file:frameFile,...timing}=frame;packedFrames.push({...timing,textureId:source.id});
    }
    const {frames,...metadata}=clip;clips[clip.clipId]={...metadata,frames:packedFrames};
  }
  sources.sort((a,b)=>b.h-a.h||b.w-a.w||a.id.localeCompare(b.id));
  const pages=[];let page={items:[],x:0,y:0,rowHeight:0,width:0,height:0};
  for(const s of sources){
    if(page.x+s.w>2048){page.x=0;page.y+=page.rowHeight;page.rowHeight=0;}
    if(page.y+s.h>2048){pages.push(page);page={items:[],x:0,y:0,rowHeight:0,width:0,height:0};}
    s.x=page.x;s.y=page.y;s.page=pages.length;page.items.push(s);page.x+=s.w;page.rowHeight=Math.max(page.rowHeight,s.h);page.width=Math.max(page.width,page.x);page.height=Math.max(page.height,page.y+s.h);
  }
  if(page.items.length)pages.push(page);
  await fs.mkdir(out,{recursive:true});
  const manifest={schemaVersion:1,referenceVersion:'duck-v1-nostrils',frameRate:{numerator:12,denominator:1},pages:[],textures:{},clips};
  for(const [index,p] of pages.entries()){
    const overlays=[];
    for(const s of p.items){const cropped=await sharp(s.input).extract(s.bounds).extend({top:2,bottom:2,left:2,right:2,extendWith:'copy'}).png().toBuffer();overlays.push({input:cropped,left:s.x+2,top:s.y+2});manifest.textures[s.id]={page:index,frame:{x:s.x+4,y:s.y+4,w:s.bounds.width,h:s.bounds.height},sourceSize:{w:512,h:512},spriteSourceSize:{x:s.bounds.left,y:s.bounds.top,w:s.bounds.width,h:s.bounds.height},rotated:false,trimmed:true};}
    const file=`duck-${String(index).padStart(2,'0')}.png`;
    await sharp({create:{width:p.width,height:p.height,channels:4,background:'#00000000'}}).composite(overlays).png().toFile(path.join(out,file));
    manifest.pages.push({file,width:p.width,height:p.height,estimatedRgbaBytes:p.width*p.height*4});
  }
  manifest.decodedRgbaBytes=manifest.pages.reduce((s,p)=>s+p.estimatedRgbaBytes,0);
  manifest.uniqueTextures=sources.length;
  await fs.writeFile(path.join(out,'atlas.json'),JSON.stringify(manifest,null,2)+'\n');
  return {clips:Object.keys(clips).length,frameRecords:validation.frameRecords,uniqueTextures:sources.length,pages:pages.length,decodedRgbaMiB:Number((manifest.decodedRgbaBytes/1024/1024).toFixed(2)),manifest:path.join(out,'atlas.json')};
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===path.resolve(process.argv[1])){
  const directory=process.argv.find(a=>a.startsWith('--clips='))?.slice(8)??'assets/duck/v1/clips';
  const output=process.argv.find(a=>a.startsWith('--out='))?.slice(6)??'assets/duck/v1/atlas';
  console.log(JSON.stringify(await packAssets(directory,output),null,2));
}
