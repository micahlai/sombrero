import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {walk} from './asset-contract.mjs';

export async function buildPreview(directory='assets/duck/v1/clips',output='previews/index.html') {
  const clips=[];
  for(const file of await walk(directory)){
    const clip=JSON.parse(await fs.readFile(file,'utf8'));
    if(!clip.frames?.length)continue;
    clip.frames=clip.frames.map(frame=>({...frame,src:path.relative(path.dirname(path.resolve(output)),path.resolve(path.dirname(file),frame.file)).split(path.sep).join('/')}));
    clips.push(clip);
  }
  if(!clips.length)throw new Error('No actual exported clips to preview');
  const data=JSON.stringify(clips).replaceAll('<','\\u003c');
  const html=`<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Duck animation review</title>
<style>
:root{font-family:ui-sans-serif,system-ui,sans-serif;color:#28291f;background:#f5f2e9;font-size:14px}*{box-sizing:border-box}body{margin:0}main{max-width:1200px;margin:40px auto;padding:0 28px}header{display:flex;align-items:end;justify-content:space-between;gap:24px;border-bottom:1px solid #d8d5c9;padding-bottom:24px}h1{font-family:Georgia,serif;font-weight:400;font-size:38px;margin:8px 0}p{line-height:1.6;color:#636454}.eyebrow{text-transform:uppercase;letter-spacing:.16em;font-size:10px;color:#878975}header p{margin:0}aside{padding:18px 0}.layout{display:grid;grid-template-columns:230px 1fr;gap:24px;margin-top:24px}nav{display:flex;flex-direction:column;gap:4px;max-height:700px;overflow:auto}button,select{font:inherit;border:1px solid #d3d1c6;background:#fffdf7;border-radius:7px;padding:9px 12px;color:inherit;cursor:pointer}nav button{text-align:left;border-color:transparent;background:transparent;font-size:12px}nav button.active{background:#e1e5cf;border-color:#ced5b7}button:hover{background:#ecebdc}.stage{min-height:475px;background:#c7d9e4;border-radius:12px;display:grid;place-items:center;position:relative;overflow:hidden}.stage.dark{background:#272b32}.stage.light{background:#fff}.stage.checker{background-color:#eee;background-image:linear-gradient(45deg,#ddd 25%,transparent 25%),linear-gradient(-45deg,#ddd 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#ddd 75%),linear-gradient(-45deg,transparent 75%,#ddd 75%);background-size:24px 24px;background-position:0 0,0 12px,12px -12px,-12px 0}.duck{width:310px;height:310px;object-fit:contain;image-rendering:auto}.stage>span{position:absolute;left:18px;top:16px;color:#59626b;font-size:11px}.stage.dark>span{color:#bbc4cc}.controls{display:flex;flex-wrap:wrap;gap:12px;align-items:center;margin:18px 0}.controls label{display:flex;gap:8px;align-items:center;color:#636454}.meta{display:flex;gap:20px;flex-wrap:wrap;color:#636454;font-size:12px}.detail{padding-top:20px;border-top:1px solid #d8d5c9;font-size:12px}.detail p{margin:6px 0}code{font-family:ui-monospace,monospace;font-size:11px}.status{min-height:22px;color:#636454;font-size:12px}@media(max-width:700px){main{margin:20px auto;padding:0 16px}header{display:block}h1{font-size:30px}.layout{grid-template-columns:1fr}nav{flex-direction:row;max-height:none;overflow:auto}nav button{white-space:nowrap}.stage{min-height:370px}}
</style>
<main><header><div><div class="eyebrow">Desktop companion · artist review</div><h1>One duck. A little movement.</h1><p>Shared watercolor master · fixed bill and two nostrils</p></div><p><strong>12 fps</strong><br>Exact integer frame clock</p></header>
<div class="layout"><nav id="clips" aria-label="Animation clips"></nav><section><div class="stage" id="stage"><span id="acting">Character acting · transparent frames</span><img class="duck" id="duck" alt="Animated watercolor duck"></div>
<div class="controls"><button id="play">Pause</button><button id="restart">Restart</button><label>Background <select id="bg"><option value="">Sky</option><option value="dark">Charcoal</option><option value="light">White</option><option value="checker">Alpha checker</option></select></label><label>Size <input id="size" type="range" min="200" max="500" value="310"></label></div><div class="status" id="status"></div><div class="meta" id="meta"></div><div class="detail"><p><strong id="name"></strong></p><p id="continuity"></p><p>Bill movement: none. Watercolor pixels move with the shared parts. Flight and screen-edge travel are metadata for the desktop host; this surface reviews the character frames.</p><p id="provenance"></p><p>Open this file locally with the packaged assets alongside it. No server, account, LLM, or network connection is used.</p></div></section></div></main>
<script>
const clips=${data};
const img=document.getElementById('duck'),stage=document.getElementById('stage'),status=document.getElementById('status'),buttons=[];
let current,images=[],start=performance.now(),pausedAt=0,paused=false,token=0,lastFrame=-1;
for(const clip of clips){const b=document.createElement('button');b.textContent=clip.clipId;b.onclick=()=>select(clip);document.getElementById('clips').append(b);buttons.push(b);}
async function select(clip){const thisToken=++token;current=undefined;status.textContent='Loading '+clip.clipId+'…';buttons.forEach((b,i)=>b.classList.toggle('active',clips[i]===clip));const loaded=await Promise.all(clip.frames.map(frame=>new Promise((resolve,reject)=>{const i=new Image();i.onload=()=>resolve(i);i.onerror=()=>reject(new Error(frame.src));i.src=frame.src;}))).catch(e=>{status.textContent='Frame could not load: '+e.message;return null});if(!loaded||thisToken!==token)return;current=clip;images=loaded;start=performance.now();pausedAt=0;paused=false;lastFrame=-1;document.getElementById('play').textContent='Pause';document.getElementById('name').textContent=clip.clipId;const ticks=clip.frames.reduce((s,f)=>s+f.durationFrames,0);document.getElementById('meta').textContent=ticks+' ticks · '+(ticks/12).toFixed(2)+' s · '+clip.frames.length+' frame records · '+(clip.loop?'loop':'one shot, held on last frame');document.getElementById('continuity').textContent='Entry: '+clip.entryPose+' → Exit: '+clip.exitPose;document.getElementById('provenance').textContent='Source: '+clip.sourceMasterVersion+' · '+(clip.sourceMasterSha256||'').slice(0,16)+'…';status.textContent='';}
function tick(now){requestAnimationFrame(tick);if(!current)return;const elapsed=paused?pausedAt:now-start;const total=current.frames.reduce((s,f)=>s+f.durationFrames,0);let tick=Math.floor(elapsed*12/1000);tick=current.loop?tick%total:Math.min(total-1,tick);let end=0,index=0;for(;index<current.frames.length;index++){end+=current.frames[index].durationFrames;if(tick<end)break;}if(index!==lastFrame){img.src=images[index].src;lastFrame=index;status.textContent='Tick '+tick+' / '+total+' · Frame '+String(index+1).padStart(3,'0')+' / '+current.frames.length;}}
document.getElementById('play').onclick=()=>{if(!current)return;if(paused){start=performance.now()-pausedAt;paused=false;}else{pausedAt=performance.now()-start;paused=true;}document.getElementById('play').textContent=paused?'Play':'Pause';};document.getElementById('restart').onclick=()=>{start=performance.now();pausedAt=0;lastFrame=-1;};document.getElementById('bg').onchange=e=>stage.className='stage '+e.target.value;document.getElementById('size').oninput=e=>{img.style.width=e.target.value+'px';img.style.height=e.target.value+'px';};select(clips[0]);requestAnimationFrame(tick);
</script></html>`;
  await fs.mkdir(path.dirname(output),{recursive:true});await fs.writeFile(output,html);
  return {output,clips:clips.length,frameRate:12};
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===path.resolve(process.argv[1])){
  const directory=process.argv.find(a=>a.startsWith('--clips='))?.slice(8)??'assets/duck/v1/clips';
  const output=process.argv.find(a=>a.startsWith('--out='))?.slice(6)??'previews/index.html';
  console.log(JSON.stringify(await buildPreview(directory,output),null,2));
}
