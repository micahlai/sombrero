import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {GraphController, evaluateGuard} from '../web/engine.mjs';
const graph = JSON.parse(readFileSync(new URL('../../docs/sombrero-v1-state-graph.json', import.meta.url)));
const make = (rng = () => 0) => new GraphController(graph, rng);

test('guard parser handles precedence without executing arbitrary code', () => {
  assert.equal(evaluateGuard('pet && !event || reading', {pet: true, event: false, reading: false}), true);
  assert.equal(evaluateGuard('!(pet || event)', {pet: false, event: false}), true);
  assert.throws(() => evaluateGuard('pet;alert(1)', {pet: true}));
  assert.throws(() => evaluateGuard('missing', {}));
});
test('standing pet interrupts; release waits until clip end', () => {
  const c = make(); c.setFlag('pet', true); assert.equal(c.state, '1d');
  c.setFlag('pet', false); assert.equal(c.state, '1d');
  c.complete(); assert.equal(c.state, '1c'); c.complete(); assert.equal(c.state, '1a');
});
test('required sitting-pet photo route skips gateways without losing request', () => {
  const c = make(() => { throw Error('No RNG expected'); });
  c.jump('3c'); c.setFlag('pet', true); c.setFlag('showPhoto', true);
  c.trigger('photoShow'); assert.equal(c.state, '3c');
  c.complete(); assert.equal(c.state, '2b'); assert.equal(c.signals.event, true);
  assert.deepEqual(c.history.slice(-2).map(h => [h.to, h.skipped]), [['3a', false], ['2b', true]]);
  c.complete(); assert.equal(c.state, '5a'); assert.equal(c.signals.event, false);
  assert.equal(c.active, 'photoShow');
  assert.deepEqual(c.history.slice(-2).map(h => [h.to, h.skipped]), [['1a', false], ['5a', true]]);
  c.complete(); c.complete(); assert.equal(c.state, '5c');
  c.complete(); assert.equal(c.state, '5c');
  c.setFlag('showPhoto', false); assert.equal(c.state, '5c');
  c.complete(); assert.equal(c.state, '5d');
});
test('page-two requests outrank pet and stay FIFO during active routines', () => {
  const c = make(); c.jump('1d'); c.trigger('photoShow'); c.trigger('bibleRead');
  c.setFlag('pet', true); c.complete(); assert.equal(c.state, '5a');
  assert.equal(c.active, 'photoShow'); assert.deepEqual(c.queue, ['bibleRead']);
  c.complete(); c.complete(); c.complete(); assert.equal(c.state, '5d');
  c.complete(); assert.equal(c.state, '7a'); assert.equal(c.active, 'bibleRead');
});
test('1b finishes before event; 3b interrupts immediately; 1c has no event interrupt', () => {
  for (const [start, immediate, completed] of [['1b','1b','6a'], ['3b','2b','6a'], ['1c','1c','6a']]) {
    const c = make(); c.jump(start); c.trigger('photoTake'); assert.equal(c.state, immediate);
    c.complete(); assert.equal(c.state, completed);
  }
});
test('sit-down cannot be interrupted by a page-two request', () => {
  const c = make(); c.jump('2a'); c.trigger('bibleRead'); assert.equal(c.state, '2a');
  c.complete(); assert.equal(c.state, '2b'); c.complete(); assert.equal(c.state, '7a');
});
test('goodbye has priority, timeout stays hidden until a recall event', () => {
  const c = make(); c.setFlag('goodbye', true); assert.equal(c.state, '4a');
  c.complete(); assert.equal(c.state, 'timeout'); assert.equal(c.hidden, true);
  assert.equal(c.flags.goodbye, false); c.trigger('photoShow'); assert.equal(c.state, 'timeout');
  assert.equal(c.complete(), false); c.trigger('manualRecall'); assert.equal(c.state, '4b');
  c.complete(); assert.equal(c.state, '1b');
  c.complete(); assert.equal(c.state, '5a');
});
test('event includes goodbye and remains true while either goodbye or requests are pending', () => {
  const c = make(); c.setMode(false);
  assert.equal(c.signals.event, false);
  c.setFlag('goodbye', true); assert.equal(c.signals.event, true);
  c.trigger('photoShow'); c.setFlag('goodbye', false); assert.equal(c.signals.event, true);
  c.clearQueue(); assert.equal(c.signals.event, false);
  c.setFlag('goodbye', true); c.clearQueue(); assert.equal(c.signals.event, true);
  c.reset(); assert.equal(c.signals.event, false);
});
test('goodbye exits sitting pet even while pet stays held and clears on timeout', () => {
  const c = make(); c.jump('3c'); c.setFlag('pet', true); c.setFlag('goodbye', true);
  assert.equal(c.signals.event, true);
  c.complete(); assert.equal(c.state, '2b');
  c.complete(); assert.equal(c.state, '4a');
  c.complete(); assert.equal(c.state, 'timeout'); assert.equal(c.signals.event, false);
});
test('weighted defaults normalize 1a total 1.02 and deterministic edges use no RNG', () => {
  for (const [sample, state] of [[0,'1a'], [.956,'1b'], [.98,'1c'], [.9999,'2a']]) {
    const c = make(() => sample); c.complete(); assert.equal(c.state, state);
  }
  const c = make(() => { throw Error('No RNG expected'); }); c.jump('2a'); c.complete(); assert.equal(c.state, '3a');
});
test('camera/read held booleans exit only at completion', () => {
  for (const [event, flag, idle, exit] of [['photoTake','takingPhoto','6b','6c'], ['bibleRead','reading','7b','7c']]) {
    const c = make(); c.setFlag(flag, true); c.trigger(event); c.complete(); assert.equal(c.state, idle);
    c.complete(); assert.equal(c.state, idle); c.setFlag(flag, false); assert.equal(c.state, idle);
    c.complete(); assert.equal(c.state, exit);
  }
});
test('stale clip completion is ignored after interruption, jump, or reset', () => {
  const c = make(); let token = c.generation; c.setFlag('pet', true);
  assert.equal(c.complete(token), false); assert.equal(c.state, '1d');
  token = c.generation; c.jump('2a'); assert.equal(c.complete(token), false);
  token = c.generation; c.reset(); assert.equal(c.complete(token), false);
});
test('solo mode loops and suspends graph guards; resuming applies pending guards', () => {
  const c = make(); c.setMode(false); c.jump('3a'); c.setFlag('pet', true); c.trigger('photoShow');
  c.complete(); assert.equal(c.state, '3a'); c.setMode(true); assert.equal(c.state, '2b');
});
test('debug jumps start a new path while retaining the transition log', () => {
  const c = make(); c.complete(); assert.equal(c.history.length, 1);
  c.jump('3c'); assert.equal(c.history.length, 0);
  assert.ok(c.log.some(entry => entry.kind === 'default'));
  c.complete(); assert.equal(c.history[0].from, '3c');
});
test('click override only arms directly connected weighted options, without jumping', () => {
  const c=make();
  assert.equal(c.forceDefault('7a'),false);assert.equal(c.state,'1a');
  assert.equal(c.forceDefault('2a'),true);assert.equal(c.state,'1a');
  assert.deepEqual(c.outgoing().filter(e=>e.kind==='default').map(e=>c.defaultWeight(e)),[0,0,0,1]);
  assert.equal(c.graph.transitions[0].weight,.975);
  c.complete();assert.equal(c.state,'2a');assert.equal(c.defaultOverride,null);
  assert.equal(c.forceDefault('3a'),false); // One deterministic exit is not a random override.
});
test('one-shot weighted override consumes no RNG, then restores defaults', () => {
  let calls=0;const c=make(()=>{calls++;return .9999;});
  c.forceDefault('1a');c.complete();assert.equal(c.state,'1a');assert.equal(calls,0);
  assert.equal(c.outgoing()[0].weight,.975);assert.equal(c.defaultOverride,null);
  c.complete();assert.equal(c.state,'2a');assert.equal(calls,1);
});
test('conditional routes retain priority and invalidate a pending weighted override', () => {
  const c=make();c.forceDefault('2a');c.setFlag('pet',true);
  assert.equal(c.state,'1d');assert.equal(c.defaultOverride,null);
  c.setFlag('pet',false);c.jump('1b');c.forceDefault('1c');c.trigger('photoShow');
  assert.equal(c.state,'1b');c.complete();assert.equal(c.state,'5a');assert.equal(c.defaultOverride,null);
});
test('override can be canceled and cannot survive reset, jump, or solo mode', () => {
  const c=make();c.forceDefault('1b');c.forceDefault('1b');assert.equal(c.defaultOverride,null);
  c.forceDefault('1b');c.jump('3a');assert.equal(c.defaultOverride,null);
  c.forceDefault('2b');c.reset();assert.equal(c.defaultOverride,null);
  c.forceDefault('1b');c.setMode(false);assert.equal(c.defaultOverride,null);
  assert.equal(c.forceDefault('1b'),false);
});
test('all 48 authored edges are reachable with suitable flags and RNG', () => {
  const visited = new Set();
  const flagNames = ['pet','goodbye','showPhoto','takingPhoto','reading'];
  for (const state of graph.states) for (let bits = 0; bits < 32; bits++) {
    for (const event of [null, 'photoShow','photoTake','bibleRead']) for (const sample of [0,.1,.8,.956,.98,.99,.9999]) {
      const c = make(() => sample); c.state = state.id;
      c.flags = Object.fromEntries(flagNames.map((n,i) => [n, Boolean(bits & (1 << i))]));
      if (event) c.queue.push(event);
      c.resolveImmediate(false); c.complete();
      if (c.hidden) c.trigger('manualRecall');
      for (const h of c.history) visited.add(h.edge);
    }
  }
  assert.deepEqual(graph.transitions.map((_,i) => `edge-${i}`).filter(id => !visited.has(id)), []);
});
