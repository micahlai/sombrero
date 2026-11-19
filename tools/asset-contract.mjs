/** Technical raster assembly only. All painted inputs are authored by the artists. */
import fs from 'node:fs/promises';
import path from 'node:path';
import { createRequire } from 'node:module';
import crypto from 'node:crypto';
const require = createRequire(import.meta.url);

export function imageLibrary(name = 'sharp') {
  const dirs = [process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES, ...(process.env.NODE_REPL_NODE_MODULE_DIRS || '').split(path.delimiter), '/Applications/ChatGPT.app/Contents/Resources/cua_node/lib/node_modules'];
  try { return require(name); } catch {}
  for (const dir of dirs.filter(Boolean)) { try { return require(path.join(dir, name)); } catch {} }
  throw new Error(`Missing ${name}; install it locally or expose its module directory via NODE_REPL_NODE_MODULE_DIRS.`);
}
export const sharp = imageLibrary();
export const FRAME_RATE = Object.freeze({numerator:12,denominator:1});
export const REFERENCE_VERSION = 'duck-v1-nostrils';
export const CANVAS = Object.freeze({width:512,height:512});
export const GROUND_PIVOT = Object.freeze({x:256,y:448});

export async function loadMaster(manifestPath) {
  const absolute = path.resolve(manifestPath);
  const manifestBytes=await fs.readFile(absolute);
  const manifest = JSON.parse(manifestBytes.toString('utf8'));
  const baseDir = path.dirname(absolute);
  if (!Array.isArray(manifest.layers)) throw new Error('Master requires layers array');
  const layers = await Promise.all(manifest.layers.map(async (layer,index) => {
    const file = path.resolve(baseDir,layer.file);
    const input = await fs.readFile(file);
    const metadata = await sharp(input).metadata();
    return {...layer,file,input,width:layer.width??metadata.width,height:layer.height??metadata.height,x:layer.x??0,y:layer.y??0,z:layer.z??index};
  }));
  return {...manifest,manifestPath:absolute,manifestSha256:crypto.createHash('sha256').update(manifestBytes).digest('hex'),canvas:manifest.canvas??CANVAS,groundPivot:manifest.groundPivot??GROUND_PIVOT,baseDir,layers};
}
const n=(value,fallback=0)=>Number.isFinite(value)?value:fallback;
const esc=value=>String(value).replaceAll('&','&amp;').replaceAll('"','&quot;').replaceAll('<','&lt;');
/** Stable local raster bending. Pixels are displaced, never re-generated. */
export async function bendLayer(input,{bendPx=0,bendAxis='x',anchor=0.5,width,height}={}) {
  if(!bendPx)return {input,xOffset:0,yOffset:0,width,height};
  const {data,info}=await sharp(input).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  const horizontal=bendAxis!=='y';
  const ratio=horizontal?info.width/width:info.height/height;
  const amount=bendPx*ratio;
  const pad=Math.ceil(Math.abs(amount))+2;
  const outW=info.width+(horizontal?pad*2:0),outH=info.height+(horizontal?0:pad*2);
  const out=Buffer.alloc(outW*outH*4);
  const a=Math.max(0,Math.min(1,anchor));
  const shift=t=>amount*Math.sin(Math.PI/2*((t-a)/Math.max(a,1-a,0.01)));
  for(let y=0;y<outH;y++)for(let x=0;x<outW;x++){
    const sx=horizontal?x-pad-shift(y/Math.max(1,info.height-1)):x;
    const sy=horizontal?y:y-pad-shift(x/Math.max(1,info.width-1));
    const loX=Math.floor(sx),loY=Math.floor(sy),dx=sx-loX,dy=sy-loY;
    const dst=(y*outW+x)*4;let alpha=0,r=0,g=0,b=0;
    for(let iy=0;iy<2;iy++)for(let ix=0;ix<2;ix++){
      const px=loX+ix,py=loY+iy;if(px<0||py<0||px>=info.width||py>=info.height)continue;
      const weight=(ix?dx:1-dx)*(iy?dy:1-dy),src=(py*info.width+px)*4;
      const wa=weight*data[src+3];alpha+=wa;r+=wa*data[src];g+=wa*data[src+1];b+=wa*data[src+2];
    }
    if(alpha>0){out[dst]=Math.round(r/alpha);out[dst+1]=Math.round(g/alpha);out[dst+2]=Math.round(b/alpha);out[dst+3]=Math.round(alpha);}
  }
  return {input:await sharp(out,{raw:{width:outW,height:outH,channels:4}}).png().toBuffer(),xOffset:horizontal?-pad/ratio:0,yOffset:horizontal?0:-pad/ratio,width:horizontal?outW/ratio:width,height:horizontal?height:outH/ratio};
}
function transformSVG(t={},pivot={x:256,y:448}) {
  const p=t.pivot??pivot;
  return `translate(${n(t.x)} ${n(t.y)}) translate(${n(p.x)} ${n(p.y)}) rotate(${n(t.rotationDeg)}) skewX(${n(t.skewXDeg??t.skewDeg)}) skewY(${n(t.skewYDeg)}) scale(${n(t.scaleX,1)} ${n(t.scaleY,1)}) translate(${-n(p.x)} ${-n(p.y)})`;
}

/**
 * transforms keys match layer.id, layer.group, or root. All pivots and x/y
 * offsets are expressed in output-canvas coordinates. A group transform applies
 * equally to its source parts (e.g. head + face + eyes). Layer-specific keys may
 * add local motion; don't put face articulation on the fixed bill group.
 * extraLayers supports props interleaved by z with the master draw stack.
 */
export async function renderPose({master,transforms={},eyeState='open',output,extraLayers=[],layersBefore=[],layersAfter=[],clipRect=null}) {
  if(typeof master==='string')master=await loadMaster(master);
  const canvas=master.canvas??CANVAS;
  const all=[...layersBefore.map(l=>({...l,z:l.z??-1000})),...master.layers,...extraLayers,...layersAfter.map(l=>({...l,z:l.z??1000}))];
  const drawn=[];
  for(const [index,l] of all.sort((a,b)=>(a.z??0)-(b.z??0)).entries()) {
    if(l.visible===false || (l.whenEyeState && l.whenEyeState!==eyeState))continue;
    const local=transforms[l.id]??{};
    if(local.visible===false)continue;
    let input=l.input??await fs.readFile(path.resolve(master.baseDir,l.file));
    const meta=(l.width&&l.height)?null:await sharp(input).metadata();
    const group=l.group;
    const groupTransform=group&&group!==l.id?transforms[group]:null;
    const pivot=l.pivot??{x:n(l.x)+(l.width??meta.width)/2,y:n(l.y)+(l.height??meta.height)/2};
    const groupPivot=master.groupPivots?.[group]??pivot;
    const opacity=Math.max(0,Math.min(1,n(local.opacity??l.opacity,1)));
    const width=l.width??meta.width,height=l.height??meta.height;
    const bend=await bendLayer(input,{bendPx:local.bendPx??local.bendXPx??0,bendAxis:local.bendAxis??'x',anchor:local.bendAnchor??0.5,width,height});
    input=bend.input;
    let markup=`<image x="${n(l.x)+bend.xOffset}" y="${n(l.y)+bend.yOffset}" width="${bend.width}" height="${bend.height}" opacity="${opacity}" href="data:image/png;base64,${input.toString('base64')}"/>`;
    markup=`<g transform="${esc(transformSVG(local,pivot))}">${markup}</g>`;
    if(groupTransform)markup=`<g transform="${esc(transformSVG(groupTransform,groupPivot))}">${markup}</g>`;
    drawn.push(markup);
  }
  let body=`<g transform="${esc(transformSVG(transforms.root,master.groundPivot??GROUND_PIVOT))}">${drawn.join('')}</g>`;
  if(clipRect)body=`<defs><clipPath id="clip"><rect x="${n(clipRect.x)}" y="${n(clipRect.y)}" width="${n(clipRect.width)}" height="${n(clipRect.height)}"/></clipPath></defs><g clip-path="url(#clip)">${body}</g>`;
  const svg=`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${canvas.width}" height="${canvas.height}" viewBox="0 0 ${canvas.width} ${canvas.height}">${body}</svg>`;
  const buffer=await sharp(Buffer.from(svg)).ensureAlpha().png().toBuffer();
  if(output){await fs.mkdir(path.dirname(output),{recursive:true});await fs.writeFile(output,buffer);}
  return buffer;
}

export function makeClip(clipId,frames,options={}) {
  return {schemaVersion:1,characterId:'watercolor-duck',referenceVersion:REFERENCE_VERSION,clipId,canvas:CANVAS,groundPivot:GROUND_PIVOT,frameRate:FRAME_RATE,loop:false,entryPose:'neutral',exitPose:'neutral',safeInterruptionFrames:[0],fallbackClip:'idle.wait',...options,frames:frames.map(frame=>({...frame,durationMs:frame.durationFrames*1000/12}))};
}
export async function writeClip(directory,clip) {
  await fs.mkdir(directory,{recursive:true});await fs.writeFile(path.join(directory,'clip.json'),JSON.stringify(clip,null,2)+'\n');
}
export function durationMs(clip){return clip.frames.reduce((sum,f)=>sum+f.durationFrames,0)*1000/12;}
export async function walk(directory,name='clip.json') {
  const out=[];
  try {for(const item of await fs.readdir(directory,{withFileTypes:true})) {const file=path.join(directory,item.name);if(item.isDirectory())out.push(...await walk(file,name));else if(item.name===name)out.push(file);}}catch(error){if(error.code!=='ENOENT')throw error;}
  return out.sort();
}
