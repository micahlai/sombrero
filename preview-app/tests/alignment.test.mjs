import {test} from 'node:test';
import assert from 'node:assert/strict';
import {validateCalibration,framePlacement,calibratedEntry} from '../web/alignment.mjs';

const calibration={schemaVersion:1,canvas:{width:1000,height:1000},animations:{
  '1a':{status:'calibrated',scale:2,offsetX:100,offsetY:200},
  '1b':{status:'calibrated',scale:1,offsetX:100,offsetY:200},
  '1c':{status:'missing',scale:1,offsetX:0,offsetY:0},
}};
test('uniform scale and position use one shared canvas across clips',()=>{
  const viewport={width:1060,height:1050};
  const a=framePlacement({naturalWidth:200,naturalHeight:300},{width:200,height:300},calibration,'1a',viewport);
  const b=framePlacement({naturalWidth:400,naturalHeight:600},{width:900,height:900},calibration,'1b',viewport);
  assert.deepEqual(a,{x:130,y:225,width:400,height:600});
  assert.deepEqual(a,b); // Different source/crop dimensions cannot add a second per-clip fit.
});
test('all drawings in a calibrated clip receive the same transform',()=>{
  const viewport={width:1060,height:1050};
  const a=framePlacement({naturalWidth:200,naturalHeight:300},{width:700,height:500},calibration,'1a',viewport);
  const b=framePlacement({naturalWidth:300,naturalHeight:400},{width:700,height:500},calibration,'1a',viewport);
  assert.equal(a.x,b.x);assert.equal(a.y,b.y);assert.equal(a.width/200,b.width/300);
});
test('scene zoom is global and preserves the shared ground anchor',()=>{
  const map={...calibration,canvas:{...calibration.canvas,anchor:{x:500,y:800}}};
  const image={naturalWidth:200,naturalHeight:300},clip={width:200,height:300},viewport={width:1060,height:1050};
  const a=framePlacement(image,clip,map,'1a',viewport,1);
  const b=framePlacement(image,clip,map,'1a',viewport,2);
  assert.equal(b.width,a.width*2);assert.equal(b.height,a.height*2);
  const anchorX=530,anchorY=825;
  assert.equal(b.x-anchorX,(a.x-anchorX)*2);assert.equal(b.y-anchorY,(a.y-anchorY)*2);
});
test('unreviewed/missing entries do not claim an applied calibration',()=>{
  assert.equal(calibratedEntry(calibration,'1c'),null);
  assert.equal(calibratedEntry(calibration,'4a'),null);
  assert.equal(calibratedEntry(calibration,'1A').scale,2);
  assert.deepEqual(framePlacement({naturalWidth:200,naturalHeight:300},{width:200,height:300},null,'1a',{width:800,height:620}),
    framePlacement({naturalWidth:200,naturalHeight:300},{width:200,height:300},calibration,'1c',{width:800,height:620}));
});
test('calibration validation rejects unsafe/nonfinite transforms',()=>{
  assert.equal(validateCalibration(calibration),calibration);
  assert.equal(validateCalibration(null),null);
  for(const changes of [{scale:0},{offsetX:NaN},{offsetY:Infinity}]) {
    assert.throws(()=>validateCalibration({...calibration,animations:{'1a':{...calibration.animations['1a'],...changes}}}));
  }
  assert.throws(()=>validateCalibration({...calibration,canvas:{width:0,height:1000}}));
});
