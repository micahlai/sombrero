import {GraphController,evaluateGuard} from './engine.mjs';
import {DrawingClock,naturalFrameSize,ClipCache} from './playback.mjs';
import {GraphView} from './graph.mjs';
import {validateCalibration,calibratedEntry,framePlacement} from './alignment.mjs';

const $=selector=>document.querySelector(selector);
const canvas=$('#preview'), context=canvas.getContext('2d');
const clock=new DrawingClock();
let project,controller,view,currentClip,currentClipId,selected,followCurrent=true;
let paused=false,loading=false,playGeneration=-1,loadSerial=0,lastLogSerial=-1;
let loadingVisible=false,loadingTimer;
let backgrounds=['checker','white','dark'],backgroundIndex=0;
let cache;
const offline=Boolean(window.PREVIEW_BOOTSTRAP);
let objectURLs=[];
let inspectorKey='',queueKey=null;

function details(open) {
  $('.graph-panel').classList.toggle('details-collapsed',!open);
  $('#details').setAttribute('aria-expanded',String(open));
}
details(window.innerHeight>950);

function report(error) {
  $('#error').hidden=false;
  $('#error').textContent=error instanceof Error?error.message:String(error);
}
function safely(action) { try { action(); sync(); } catch(error) { paused=true;report(error); } }

function createClipCache(projectAtLoad,controllerAtLoad) {
  return new ClipCache(async id=>{
    const clip=projectAtLoad.clips[id];
    if (clip.placeholder||!clip.frames.length) return {...clip,images:[],width:320,height:320};
    const results=await Promise.allSettled(clip.frames.map(url=>new Promise((resolve,reject)=>{
      const image=new Image();
      image.onload=async()=>{
        try { await image.decode(); resolve(image); } catch(error) { reject(error); }
      };
      image.onerror=()=>reject(new Error(url)); image.src=url;
    })));
    if (results.some(result=>result.status==='rejected')) {
      const fallback={...clip,placeholder:true,frameCount:10,assetStatus:'unreadable'};
      if(project===projectAtLoad) {
        controllerAtLoad.note('asset',`${id.toUpperCase()}: unreadable frame; using 10 pink-square frames`);
        projectAtLoad.clips[id]=fallback;
      }
      return {...fallback,images:[],width:320,height:320,error:true};
    }
    const images=results.map(result=>result.value);
    return {...clip,images,...naturalFrameSize(images)};
  });
}

function warmNextClips() {
  if(!controller.followGraph)return;
  const routes=controller.outgoing(controller.state).slice().sort((a,b)=>
    Number(b.kind==='default')-Number(a.kind==='default') || (b.weight??0)-(a.weight??0));
  const targets=[...new Set(routes.map(edge=>edge.to))].filter(id=>id!==controller.state&&!project.clips[id].placeholder&&project.clips[id].frames.length);
  // Reserve one of the three cache slots for the playing clip.
  for(const id of targets.slice(0,2))void cache.load(id).catch(()=>{});
}

async function loadCurrent() {
  const serial=++loadSerial,token=controller.generation,id=controller.state;
  clearTimeout(loadingTimer);loadingVisible=false;
  $('#loading-message').hidden=true;
  if (controller.hidden) { loading=false;currentClip=null;clock.reset(performance.now());render();return; }
  const ready=cache.peek(id);
  loading=!ready;
  if(loading)loadingTimer=setTimeout(()=>{
    if(serial!==loadSerial||token!==controller.generation)return;
    loadingVisible=true;$('#loading-message').hidden=false;render();
  },250);
  try {
    const clip=ready??await cache.load(id);
    if (serial!==loadSerial||token!==controller.generation) return;
    // Touch the active entry before warming successors, keeping it in cache.
    void cache.load(id);
    clearTimeout(loadingTimer);loadingVisible=false;
    currentClip=clip;currentClipId=id;loading=false;clock.reset(performance.now());
    $('#loading-message').hidden=true;
    if (clip.error) report(`Could not read all frames in ${project.assetRoot}/${clip.folder}. Playing the 10-frame placeholder. Fix the files and reload assets.`);
    render();
    warmNextClips();
  } catch(error) {
    if (serial!==loadSerial||token!==controller.generation) return;
    clearTimeout(loadingTimer);loadingVisible=false;
    currentClip={placeholder:true,frameCount:10,images:[],width:320,height:320};currentClipId=id;
    loading=false;$('#loading-message').hidden=true;clock.reset(performance.now());report(error);
  }
}

function sync() {
  if (!controller) return;
  if (followCurrent) selected=controller.state;
  if (controller.generation!==playGeneration) {
    playGeneration=controller.generation;
    void loadCurrent();
  }
  for (const input of document.querySelectorAll('[data-flag]')) input.checked=controller.flags[input.dataset.flag];
  $('#derived-event').checked=controller.signals.event;
  $('#mode').value=controller.followGraph?'graph':'solo';
  render();
}

function draw() {
  context.clearRect(0,0,canvas.width,canvas.height);
  if (!controller||controller.hidden||!currentClip) return;
  const frame=clock.frame(currentClip.frameCount);
  if (currentClip.placeholder) {
    context.fillStyle='#e58db8';
    context.fillRect((canvas.width-225)/2,(canvas.height-225)/2,225,225);
  } else {
    const image=currentClip.images[frame];
    const calibration=$('#use-scale-map').checked?project.calibration:null;
    const box=framePlacement(image,currentClip,calibration,currentClipId,canvas,Number($('#scene-zoom').value));
    context.drawImage(image,box.x,box.y,box.width,box.height);
  }
}

function render() {
  if (!controller) return;
  const state=controller.states.get(controller.state),clip=project.clips[controller.state];
  const count=currentClip?.frameCount??clip.frameCount,frame=clock.frame(count);
  const hidden=controller.hidden;
  $('#current-id').textContent=controller.state.toUpperCase();$('#current-name').textContent=state.name;
  $('#clip-source').textContent=hidden?'No animation while hidden':loadingVisible?'Loading frames…':clip.placeholder?'Pink-square placeholder':`${clip.folder} / ${clip.frameCount} drawings`;
  $('#running-status').textContent=hidden?'Hidden':loadingVisible?'Loading':paused?'Paused':controller.followGraph?'Playing':'Solo';
  $('#running-status').classList.toggle('paused',paused||hidden);
  $('#hidden-message').hidden=!hidden;$('#placeholder-label').hidden=hidden||loading||!currentClip?.placeholder;
  $('#background').hidden=hidden;
  $('#play').textContent=paused?'Play':'Pause';$('#play').disabled=hidden;
  $('#previous-frame').disabled=hidden||loading;$('#next-frame').disabled=hidden||loading;$('#finish').disabled=hidden||loading;
  $('#frame-label').textContent=hidden?'—':`${frame+1} / ${count}`;
  $('#scrubber').max=String(Math.max(0,count-1));$('#scrubber').value=String(frame);$('#scrubber').disabled=hidden||loading;
  for (const button of document.querySelectorAll('[data-event="manualRecall"],[data-event="timedAwayExpired"]')) button.disabled=!hidden||!controller.followGraph;
  $('#stage-recall').disabled=!controller.followGraph;
  $('#queue-count').textContent=controller.queue.length?`${controller.queue.length} queued`:'Nothing queued';
  $('#request-status').textContent=controller.active?`Active request: ${controller.active}`:'No active request';
  $('#request-status').classList.toggle('active',Boolean(controller.active));
  const nextQueueKey=controller.queue.join(',');
  if(queueKey!==nextQueueKey) {
    queueKey=nextQueueKey;const queue=$('#queue');queue.replaceChildren();
    for (const [index,event] of controller.queue.entries()) {
      const token=document.createElement('span');token.className='queue-token';token.textContent=`${index+1}. ${event}`;queue.append(token);
    }
  }
  $('#clear-queue').hidden=!controller.queue.length;
  $('#graph-current').textContent=`${controller.state.toUpperCase()} · ${state.name}`;
  $('#state-picker').value=selected;
  const alignment=calibratedEntry(project.calibration,controller.state);
  $('#use-scale-map').disabled=!project.calibration;
  $('#scene-zoom').disabled=!alignment||!$('#use-scale-map').checked||clip.placeholder||hidden;
  $('#alignment-status').textContent=hidden?'':clip.placeholder?'No artwork to align':!$('#use-scale-map').checked?'Source framing (scale map off)':alignment?`Scale ${alignment.scale.toFixed(3)} · offset (${Math.round(alignment.offsetX)}, ${Math.round(alignment.offsetY)})`:'Not calibrated yet';
  const clips=Object.values(project.clips).filter(c=>c.frameCount>0);
  const ready=clips.filter(c=>!c.placeholder).length;
  $('#asset-summary').textContent=`${ready} / ${clips.length} animations ready · ${clips.length-ready} missing`;
  draw();
  const progress=hidden?0:Math.min(1,clock.elapsed*clock.fps/Math.max(1,count));
  view?.update(controller,project.clips,progress,selected);
  renderInspector();renderLog();
}

function renderInspector() {
  const key=`${controller.serial}:${selected}:${clock.fps}:${project.clips[selected]?.frameCount}`;
  if(inspectorKey===key)return;inspectorKey=key;
  const state=controller.states.get(selected);if(!state)return;
  const clip=project.clips[selected];
  const alignment=calibratedEntry(project.calibration,selected);
  $('#selected-meta').textContent=state.kind==='hidden'?'Hidden state · no drawing clock':`${project.assetRoot}/${clip.folder}/ · ${clip.frameCount} frames · ${(clip.frameCount/clock.fps).toFixed(2)}s${clip.placeholder?' · Missing artwork: pink placeholder':alignment?` · aligned ×${alignment.scale.toFixed(3)}`:' · alignment not calibrated'}`;
  const list=$('#transitions');list.replaceChildren();
  const defaults=controller.outgoing(selected).filter(e=>e.kind==='default');
  const total=defaults.reduce((n,e)=>n+controller.defaultWeight(e),0);
  for(const edge of controller.outgoing(selected)) {
    const row=document.createElement('div');row.className='transition-row';
    if(edge.kind!=='default'&&evaluateGuard(edge.guard,controller.signals))row.classList.add('eligible');
    const destination=document.createElement('span');destination.className='route-id';destination.textContent=edge.to.toUpperCase();
    const condition=document.createElement('span');condition.className='route-condition';
    const weight=controller.defaultWeight(edge);
    condition.textContent=edge.kind==='default'?`weight ${weight} · ${(weight/total*100).toFixed(2)}%${weight!==edge.weight?' · preview override':''}`:edge.guard;
    const kind=document.createElement('span');kind.className=`route-kind ${edge.kind}`;
    kind.textContent={default:'clip end',interrupt:'immediate',afterClip:'after clip',recall:'recall'}[edge.kind];
    row.append(destination,condition,kind);list.append(row);
  }
}

function renderLog() {
  if(lastLogSerial===controller.serial)return;lastLogSerial=controller.serial;
  const log=$('#log');log.replaceChildren();
  for(const entry of controller.log.slice(0,50)) {
    const row=document.createElement('li');row.className=entry.kind;
    const time=document.createElement('time');time.textContent=new Date(entry.time).toLocaleTimeString([],{hour12:false});
    const message=document.createElement('span');message.className='log-message';message.textContent=entry.message;
    const kind=document.createElement('span');kind.className='log-tag';kind.textContent=entry.skipped?'gateway skipped':entry.kind;
    row.append(time,message,kind);log.append(row);
  }
  const trail=$('#trail');trail.replaceChildren();
  const history=controller.history.slice(-9);
  const addToken=(id,skip=false)=>{const t=document.createElement('span');t.className=`trail-token${skip?' skip':''}`;t.textContent=id.toUpperCase();t.title=skip?'Gateway skipped before drawing':'';trail.append(t);};
  if(!history.length)addToken(controller.state);
  else {
    addToken(history[0].from,history[0].skipped);
    history.forEach((entry,index)=>{const arrow=document.createElement('span');arrow.className='trail-arrow';arrow.textContent='→';trail.append(arrow);addToken(entry.to,Boolean(history[index+1]?.skipped));});
  }
  trail.scrollLeft=trail.scrollWidth;
}

function selectState(id,fromGraph=false) {
  selected=id;followCurrent=false;
  // Choosing a roll should not shrink the graph by opening its inspector.
  if(fromGraph&&controller.canForceDefault(id))controller.forceDefault(id);
  else details(true);
  render();
}
function step(direction) {
  if(!controller||controller.hidden||loading||!currentClip)return;
  paused=true;
  const next=clock.frame(currentClip.frameCount)+direction;
  if(next>=currentClip.frameCount)safely(()=>controller.complete());
  else {clock.seek(Math.max(0,next));render();}
}
function finish() {if(!controller||controller.hidden||loading)return;safely(()=>controller.complete());}

async function reload(override=null) {
  $('#reload').disabled=true;
  try {
    let next=override;
    if(!next&&offline)next=structuredClone(window.PREVIEW_BOOTSTRAP);
    if(!next) {
      const response=await fetch('/api/project',{cache:'no-store'});
      if(!response.ok)throw new Error(`Could not load state graph (${response.status}). Check the server terminal.`);
      next=await response.json();
    }
    validateCalibration(next.calibration);
    const graphChanged=!project||JSON.stringify(project.graph)!==JSON.stringify(next.graph);
    // Validate before replacing the live project, so a bad graph leaves recovery available.
    const nextController=graphChanged?new GraphController(next.graph):controller;
    project=next;controller=nextController;cache=createClipCache(project,controller);
    if(graphChanged) {
      view?.destroy();selected=controller.state;followCurrent=true;
      clock.setFPS(project.graph.cadence?.drawingFPS??6);$('#fps').value=clock.fps;
      const picker=$('#state-picker');picker.replaceChildren();
      for(const state of project.graph.states) {const option=document.createElement('option');option.value=state.id;option.textContent=`${state.id.toUpperCase()} · ${state.name}`;picker.append(option);}
      view=new GraphView($('#state-graph'),$('#graph-viewport'),project.graph,id=>selectState(id,true));
      lastLogSerial=-1;
      inspectorKey='';
    }
    const clips=Object.values(project.clips).filter(c=>c.frameCount>0);
    const ready=clips.filter(c=>!c.placeholder).length;
    $('#asset-summary').textContent=`${ready} / ${clips.length} animations ready`;
    $('#root-path').textContent=project.assetRoot;
    $('#graph-subtitle').textContent=`${project.graph.states.length} states · ${project.graph.transitions.length} transitions`;
    $('#error').hidden=true;
    if(project.warnings.length)report(project.warnings.join(' '));
    playGeneration=-1;controller.note('asset',`Loaded folders: ${ready} animations, ${clips.length-ready} placeholders`);
    sync();
  }catch(error){report(error);}finally{$('#reload').disabled=false;}
}

$('#reload').addEventListener('click',()=>{if(offline)$('#folder-input').click();else void reload();});
$('#folder-input').addEventListener('change',async event=>{
  const files=[...event.target.files];if(!files.length)return;
  const groups=new Map();
  for(const file of files) {
    const parts=file.webkitRelativePath.split('/');
    if(parts.length!==3||file.name.startsWith('.')||!/[.](png|jpe?g|webp|avif)$/i.test(file.name))continue;
    const id=parts[1].toLowerCase();
    if(!groups.has(id))groups.set(id,[]);groups.get(id).push(file);
  }
  if(!groups.size){report('No supported animation frames found. Choose the final-v1 folder containing 1A, 1B, etc.');return;}
  const scaleFile=files.find(file=>{const parts=file.webkitRelativePath.split('/');return parts.length===2&&parts[1]==='animation-scales.json';});
  let calibration=null;
  try { if(scaleFile)calibration=validateCalibration(JSON.parse(await scaleFile.text())); }
  catch(error){report(error);return;}
  for(const url of objectURLs)URL.revokeObjectURL(url);objectURLs=[];
  const next=structuredClone(project);
  next.calibration=calibration;
  for(const state of next.graph.states) {
    if(state.kind==='hidden')continue;
    const frames=(groups.get(state.id.toLowerCase())??[]).sort((a,b)=>a.name.localeCompare(b.name,undefined,{numeric:true}));
    const urls=frames.map(file=>{const url=URL.createObjectURL(file);objectURLs.push(url);return url;});
    next.clips[state.id]={folder:frames[0]?.webkitRelativePath.split('/')[1]??state.id.toUpperCase(),frames:urls,frameCount:urls.length||10,placeholder:!urls.length,assetStatus:urls.length?'ready':'missing-folder'};
  }
  void reload(next);event.target.value='';
});
$('#play').addEventListener('click',()=>{paused=!paused;clock.last=performance.now();render();});
$('#finish').addEventListener('click',finish);
$('#previous-frame').addEventListener('click',()=>step(-1));$('#next-frame').addEventListener('click',()=>step(1));
$('#scrubber').addEventListener('input',event=>{paused=true;clock.seek(Number(event.target.value));render();});
$('#reset').addEventListener('click',()=>safely(()=>{controller.reset();followCurrent=true;lastLogSerial=-1;}));
$('#fps').addEventListener('change',event=>{
  const fps=Number(event.target.value);
  if(!Number.isFinite(fps)||fps<1||fps>60){event.target.value=clock.fps;return;}
  clock.setFPS(fps);render();
});
$('#speed').addEventListener('change',event=>{clock.speed=Number(event.target.value);});
$('#mode').addEventListener('change',event=>safely(()=>controller.setMode(event.target.value==='graph')));
for(const input of document.querySelectorAll('[data-flag]'))input.addEventListener('change',()=>safely(()=>controller.setFlag(input.dataset.flag,input.checked)));
for(const button of document.querySelectorAll('[data-event]'))button.addEventListener('click',()=>safely(()=>controller.trigger(button.dataset.event)));
$('#stage-recall').addEventListener('click',()=>safely(()=>controller.trigger('manualRecall')));
$('#clear-queue').addEventListener('click',()=>safely(()=>controller.clearQueue()));
$('#use-scale-map').addEventListener('change',()=>render());
$('#scene-zoom').addEventListener('change',()=>render());
$('#state-picker').addEventListener('change',event=>selectState(event.target.value));
$('#jump').addEventListener('click',()=>safely(()=>controller.jump(selected)));
$('#follow-current').addEventListener('click',()=>{followCurrent=true;sync();});
$('#clear-log').addEventListener('click',()=>{controller.log=[];controller.note('debug','Log cleared');renderLog();});
$('#edge-filter').addEventListener('change',event=>{if(view)view.filter=event.target.value;render();});
$('#fit').addEventListener('click',()=>view?.fit());$('#center-current').addEventListener('click',()=>view?.center(controller.state));
$('#details').addEventListener('click',()=>details($('.graph-panel').classList.contains('details-collapsed')));
$('#zoom-in').addEventListener('click',()=>view?.zoom(1/1.25));$('#zoom-out').addEventListener('click',()=>view?.zoom(1.25));
$('#background').addEventListener('click',()=>{backgroundIndex=(backgroundIndex+1)%backgrounds.length;const name=backgrounds[backgroundIndex];$('#stage').dataset.background=name;$('#background').textContent={checker:'Checkerboard',white:'White',dark:'Dark'}[name];});
$('#help').addEventListener('click',()=>$('#help-dialog').showModal());$('#close-help').addEventListener('click',()=>$('#help-dialog').close());
document.addEventListener('keydown',event=>{
  if(!controller||$('#help-dialog').open||event.target.closest('input,select,button,textarea,[contenteditable]'))return;
  if(event.code==='Space'){event.preventDefault();paused=!paused;clock.last=performance.now();render();}
  else if(event.key==='ArrowRight'){event.preventDefault();step(1);}
  else if(event.key==='ArrowLeft'){event.preventDefault();step(-1);}
  else if(event.key==='Enter'){event.preventDefault();finish();}
});
document.addEventListener('visibilitychange',()=>{clock.last=performance.now();});
new ResizeObserver(()=>{
  const rect=canvas.getBoundingClientRect(),ratio=window.devicePixelRatio||1;
  canvas.width=Math.max(1,Math.round(rect.width*ratio));canvas.height=Math.max(1,Math.round(rect.height*ratio));
  draw();
}).observe(canvas);

let lastRender=0;
function animate(now) {
  try {
    const enabled=controller&&!paused&&!loading&&!controller.hidden&&!document.hidden;
    clock.advance(now,enabled);
    if(enabled&&currentClip&&clock.completed(currentClip.frameCount)) {
      controller.complete(playGeneration);sync();
    }
    if(controller&&now-lastRender>40){render();lastRender=now;}
  }catch(error){paused=true;report(error);}
  requestAnimationFrame(animate);
}
void reload();requestAnimationFrame(animate);
