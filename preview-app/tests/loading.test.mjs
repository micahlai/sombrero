import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {GraphController,evaluateGuard} from '../web/engine.mjs';
import {DrawingClock,naturalFrameSize,ClipCache} from '../web/playback.mjs';
import {validateCalibration,calibratedEntry,framePlacement} from '../web/alignment.mjs';

const flush=()=>new Promise(resolve=>setImmediate(resolve));

// Exercise the real app transition/loading flow with controlled image decoding.
// No browser, disk images, or wall-clock delays are needed.
function lab() {
  const nodes=new Map(),images=new Map(),timers=new Map(),paint=[];
  let timerId=0;
  const node=()=>({hidden:true,value:'1',checked:true,width:800,height:620,
    classList:{toggle(){},contains(){return true;}},style:{},
    setAttribute(){},addEventListener(){},append(){},replaceChildren(){},
    getContext:()=>({clearRect(){paint.push(null);},drawImage(image){paint.push(image.src);},fillRect(){paint.push('placeholder');}}),
  });
  const $=selector=>{if(!nodes.has(selector))nodes.set(selector,node());return nodes.get(selector);};
  const graph=JSON.parse(readFileSync(new URL('../../docs/sombrero-v1-state-graph.json',import.meta.url)));
  const clips=Object.fromEntries(graph.states.map(state=>[state.id,{
    folder:state.id,frames:['1a','1b','2a'].includes(state.id)?[state.id]:[],
    frameCount:state.kind==='hidden'?0:['1a','1b','2a'].includes(state.id)?1:10,placeholder:!['1a','1b','2a'].includes(state.id),
  }]));
  class Image {
    naturalWidth=100;naturalHeight=100;
    set src(url){this.url=url;images.set(url,this);}
    get src(){return this.url;}
    decode(){return new Promise(resolve=>{this.finishDecode=resolve;});}
  }
  const sandbox=vm.createContext({GraphController,evaluateGuard,DrawingClock,naturalFrameSize,ClipCache,
    validateCalibration,calibratedEntry,framePlacement,Image,structuredClone,
    window:{innerHeight:800,PREVIEW_BOOTSTRAP:{graph,clips,calibration:null,assetRoot:'test',warnings:[]}},
    document:{querySelector:$,querySelectorAll:()=>[],createElement:node,addEventListener(){}},
    performance:{now:()=>0},ResizeObserver:class {observe(){}},
    GraphView:class {update(){} destroy(){}},
    setTimeout(callback){timers.set(++timerId,callback);return timerId;},
    clearTimeout(id){timers.delete(id);},requestAnimationFrame(){},
  });
  const source=readFileSync(new URL('../web/app.mjs',import.meta.url),'utf8')
    .replace(/^import .+;\s*$/gm,'').replace('void reload();requestAnimationFrame(animate);','');
  vm.runInContext(source+`\nglobalThis.lab={reload,sync,clock,get controller(){return controller;},get loading(){return loading;},get currentClipId(){return currentClipId;}};`,sandbox);
  const app=sandbox.lab;
  async function decode(id){await images.get(id).onload();await flush();}
  // onload waits for decode; resolve it separately to simulate a decoded frame.
  async function ready(id){const done=decode(id);images.get(id).finishDecode();await done;}
  return {app,$,paint,images,timers,ready};
}

test('transitions hold the previous drawing through decoding, then swap without a loading flash',async()=>{
  const {app,$,paint,images,timers,ready}=lab();
  await app.reload();await flush();await ready('1a');
  assert.equal(app.currentClipId,'1a');assert.equal(paint.at(-1),'1a');
  assert.ok(images.has('1b')); // Successors warm while the current clip plays.
  app.clock.seek(9);
  app.controller.jump('2a');app.sync();
  assert.equal(app.loading,true);assert.equal(paint.at(-1),'1a');
  assert.equal(app.clock.frame(10),9);
  assert.equal($('#loading-message').hidden,true);
  assert.notEqual($('#running-status').textContent,'Loading');
  const decoding=images.get('2a').onload();await flush();
  assert.equal(app.loading,true); // onload alone is insufficient: wait for decode.
  images.get('2a').finishDecode();await decoding;await flush();
  assert.equal(app.currentClipId,'2a');assert.equal(paint.at(-1),'2a');
  assert.equal(app.clock.frame(10),0);assert.equal(timers.size,0);
  assert.equal($('#loading-message').hidden,true);
  app.controller.setMode(false);app.controller.complete();app.sync();
  assert.equal(app.loading,false); // Repeating a cached clip is synchronous.
  assert.equal(paint.at(-1),'2a');assert.equal(timers.size,0);
});

test('long waits show feedback and a stale decode cannot replace a newer or hidden state',async()=>{
  const {app,$,images,timers,ready,paint}=lab();
  await app.reload();await flush();await ready('1a');
  app.controller.jump('2a');app.sync();
  [...timers.values()][0]();
  assert.equal($('#loading-message').hidden,false);
  assert.equal($('#running-status').textContent,'Loading');
  app.controller.jump('1a');app.sync();
  assert.equal(app.loading,false);assert.equal($('#loading-message').hidden,true);
  await ready('2a');assert.equal(app.currentClipId,'1a');assert.equal(paint.at(-1),'1a');
  app.controller.jump('timeout');app.sync();
  await ready('1b');assert.equal(app.controller.hidden,true);assert.equal(paint.at(-1),null);
  assert.equal($('#loading-message').hidden,true);
});
