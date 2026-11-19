import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DrawingClock,naturalFrameSize,ClipCache} from '../web/playback.mjs';

test('10 placeholder frames hold for exactly 10/6 seconds, not 10 timeline frames',()=>{
  const c=new DrawingClock(6);c.reset(0);c.advance(1500);
  assert.equal(c.frame(10),9);assert.equal(c.completed(10),false);
  c.advance(10000/6);assert.equal(c.completed(10),true);
});
test('pause/loading/hidden freezes the clock without a resume fast-forward',()=>{
  const c=new DrawingClock(6);c.reset(0);c.advance(500);assert.equal(c.frame(10),3);
  c.advance(10000,false);c.advance(10100);assert.equal(c.frame(10),3);
  assert.ok(Math.abs(c.elapsed-.6)<1e-9);
});
test('rate changes preserve the drawing and speed changes change elapsed time',()=>{
  const c=new DrawingClock(6);c.reset(0);c.advance(500);c.setFPS(12);assert.equal(c.frame(10),3);
  c.speed=2;c.advance(750);assert.equal(c.frame(10),9);
  c.seek(2);assert.equal(c.frame(10),2);c.advance(700);assert.equal(c.frame(10),2);
});
test('frame dimensions use one common scale rather than fitting each frame',()=>{
  assert.deepEqual(naturalFrameSize([{naturalWidth:100,naturalHeight:200},{naturalWidth:200,naturalHeight:100}]),{width:200,height:200});
});
test('prefetched clips are decoded once and available without an asynchronous loading state', async()=>{
  let finish, calls=0;
  const cache=new ClipCache(()=>{calls++;return new Promise(resolve=>{finish=resolve;});});
  const first=cache.load('1a'), second=cache.load('1a');
  assert.equal(first,second);assert.equal(cache.peek('1a'),undefined);
  await Promise.resolve();
  const clip={images:[{}],frameCount:1};finish(clip);
  await first;
  assert.equal(calls,1);assert.equal(cache.peek('1a'),clip);
  assert.equal(await cache.load('1a'),clip);assert.equal(calls,1);
});
test('prefetch stays bounded and an evicted pending load cannot replace newer entries', async()=>{
  let finish;
  const cache=new ClipCache(id=>id==='old'?new Promise(resolve=>{finish=resolve;}):{id},3);
  const pending=cache.load('old');await Promise.resolve();
  await cache.load('1a');await cache.load('1b');await cache.load('1c');
  finish({id:'old'});await pending;
  assert.equal(cache.peek('old'),undefined);
  assert.equal(cache.peek('1a').id,'1a');
  await cache.load('1a');await cache.load('2a');
  assert.equal(cache.peek('1b'),undefined);assert.equal(cache.peek('1a').id,'1a');
});
