// Pure graph controller. No DOM, timers, rendering, native shell, or services.
export const FLAG_NAMES = ['pet', 'goodbye', 'showPhoto', 'takingPhoto', 'reading', 'window_available', 'window_side_available', 'dialogue_open'];

export function evaluateGuard(expression, flags) {
  if (!expression) return true;
  const tokens = expression.match(/\s*(&&|\|\||!|\(|\)|[A-Za-z][A-Za-z0-9_]*)/g)?.map(t => t.trim()) ?? [];
  if (tokens.join('') !== expression.replace(/\s/g, '')) throw new Error(`Invalid guard: ${expression}`);
  let index = 0;
  const atom = () => {
    const token = tokens[index++];
    if (token === '!') return !atom();
    if (token === '(') {
      const value = or();
      if (tokens[index++] !== ')') throw new Error(`Unclosed guard: ${expression}`);
      return value;
    }
    if (!token || !Object.hasOwn(flags, token)) throw new Error(`Unknown guard: ${token}`);
    return Boolean(flags[token]);
  };
  const and = () => {
    let value = atom();
    while (tokens[index] === '&&') { index++; const next = atom(); value = value && next; }
    return value;
  };
  const or = () => {
    let value = and();
    while (tokens[index] === '||') { index++; const next = and(); value = value || next; }
    return value;
  };
  const value = or();
  if (index !== tokens.length) throw new Error(`Invalid guard: ${expression}`);
  return value;
}

export class GraphController {
  constructor(graph, random = Math.random) {
    this.graph = graph;
    this.random = random;
    this.states = new Map(graph.states.map(s => [s.id, s]));
    if (this.states.size !== graph.states.length || !this.states.has(graph.initialState)) throw new Error('Invalid state inventory');
    this.edges = graph.transitions.map((e, i) => ({...e, id: `edge-${i}`}));
    const guardFlags = {...Object.fromEntries(FLAG_NAMES.map(n => [n, false])), event: false,
      photoShowRequested: false, photoTakeRequested: false, bibleReadRequested: false,
      manualRecall: false, timedAwayExpired: false, petCycleCompleted: false,
      cameraCanceled: false, reversingCamera: false};
    for (const edge of this.edges) {
      if (!this.states.has(edge.from) || !this.states.has(edge.to)) throw new Error('Unknown transition state');
      if (!['default', 'interrupt', 'afterClip', 'recall'].includes(edge.kind)) throw new Error('Unknown transition kind');
      if (edge.kind === 'default' && (!Number.isFinite(edge.weight) || edge.weight <= 0)) throw new Error('Invalid transition weight');
      if (edge.weightByFlag && (!FLAG_NAMES.includes(edge.weightByFlag.flag) ||
          ![edge.weightByFlag.true, edge.weightByFlag.false].every(n => Number.isFinite(n) && n >= 0))) throw new Error('Invalid conditional weight');
      if (edge.weightByFlags && (!edge.weightByFlags.flags.every(f => FLAG_NAMES.includes(f)) ||
          !Object.values(edge.weightByFlags.values).every(n => Number.isFinite(n) && n >= 0))) throw new Error('Invalid clearance weights');
      evaluateGuard(edge.guard, guardFlags);
    }
    for (const target of Object.values(graph.eventTargets)) if (!this.states.has(target)) throw new Error('Unknown event target');
    this.followGraph = true;
    this.reset();
  }

  reset() {
    this.flags = Object.fromEntries(FLAG_NAMES.map(n => [n, false]));
    this.queue = [];
    this.active = null;
    this.defaultOverride = null;
    this.history = [];
    this.log = [];
    this.serial = 0;
    this.generation = (this.generation ?? 0) + 1;
    this.state = this.graph.initialState;
    this.petCycleCompleted = false;
    this.recallEntry = null;
    this.cameraCanceled = false;
    this.reversingCamera = false;
    this.note('reset', `Start at ${this.state.toUpperCase()}`);
  }

  note(kind, message, detail = {}) {
    const item = {kind, message, time: Date.now(), serial: ++this.serial, ...detail};
    this.log.unshift(item);
    this.log.length = Math.min(this.log.length, 100);
    return item;
  }

  get hidden() { return this.states.get(this.state).kind === 'hidden'; }
  get signals() {
    const pending = this.queue[0];
    return {...this.flags, pet: this.flags.pet && !this.flags.dialogue_open, petCycleCompleted: this.petCycleCompleted,
      event: this.flags.goodbye || Boolean(pending),
      photoShowRequested: pending === 'photoShow', photoTakeRequested: pending === 'photoTake',
      bibleReadRequested: pending === 'bibleRead', manualRecall: false, timedAwayExpired: false,
      cameraCanceled:this.cameraCanceled, reversingCamera:this.reversingCamera};
  }

  outgoing(state = this.state) { return this.edges.filter(e => e.from === state); }
  canForceDefault(target) {
    const defaults = this.outgoing().filter(e => e.kind === 'default');
    return this.followGraph && defaults.length > 1 && defaults.some(e => e.to === target);
  }

  forceDefault(target) {
    if (!this.canForceDefault(target)) return false;
    if (this.defaultOverride?.to === target) { this.clearDefaultOverride(); return true; }
    this.defaultOverride = {from:this.state,to:target,generation:this.generation};
    this.note('override', `Next default roll: ${this.state.toUpperCase()} → ${target.toUpperCase()} (one time)`);
    return true;
  }

  clearDefaultOverride() {
    if (this.defaultOverride) this.note('override', 'Cleared next-roll override');
    this.defaultOverride = null;
  }

  defaultWeight(edge) {
    const override = this.defaultOverride;
    if (edge.kind === 'default' && override?.from === edge.from && override.generation === this.generation) {
      return edge.to === override.to ? 1 : 0;
    }
    return this.edgeWeight(edge);
  }
  edgeWeight(edge) {
    if(edge.weightByFlags) { const key=edge.weightByFlags.flags.map(f=>this.flags[f]?'1':'0').join('');return edge.weightByFlags.values[key]; }
    return edge.weightByFlag ? edge.weightByFlag[String(Boolean(this.flags[edge.weightByFlag.flag]))] : edge.weight;
  }
  chooseWeighted(edges) {
    const candidates = edges.filter(e => this.edgeWeight(e) > 0);
    if (candidates.length < 2) return candidates[0];
    const sample = this.random();
    if (!Number.isFinite(sample) || sample < 0 || sample >= 1) throw new Error('Random sample must be in [0, 1)');
    let remaining = sample * candidates.reduce((sum, edge) => sum + this.edgeWeight(edge), 0);
    for (const edge of candidates) { remaining -= this.edgeWeight(edge); if (remaining < 0) return edge; }
    return candidates.at(-1);
  }
  eligible(kind) {
    return this.outgoing().filter(e => e.kind === kind && evaluateGuard(e.guard, this.signals));
  }

  priority(edge) {
    if (edge.guard === 'goodbye') return 0;
    if (/event|Requested/.test(edge.guard ?? '')) return 1;
    return 2;
  }

  immediate() { return this.eligible('interrupt').sort((a, b) => this.priority(a) - this.priority(b))[0]; }

  setFlag(name, value) {
    if (!FLAG_NAMES.includes(name)) throw new Error(`Unknown boolean: ${name}`);
    this.flags[name] = Boolean(value);
    if (this.flags.dialogue_open) this.flags.pet = false;
    this.note('input', `${name} = ${this.flags[name]}`);
    if (this.followGraph) this.resolveImmediate(false);
  }

  trigger(name) {
    if (name === 'photoTake') this.cameraCanceled = false;
    if (name === 'manualRecall' || name === 'timedAwayExpired') {
      if (!this.hidden || !this.followGraph) {
        this.note('input', `${name}: only applies in timeout`);
        return false;
      }
      const signals = {...this.signals, [name]: true};
      const edge = this.chooseWeighted(this.outgoing().filter(e => e.kind === 'recall' && evaluateGuard(e.guard, signals)));
      if (!edge) return false;
      this.note('input', name);
      this.take(edge, false);
      this.resolveImmediate(true);
      return true;
    }
    if (!Object.hasOwn(this.graph.eventTargets, name)) throw new Error(`Unknown event: ${name}`);
    if (this.queue.length >= 8) { this.note('input', 'Queue is full (8 requests).'); return false; }
    this.queue.push(name);
    this.note('input', `Queued ${name}`);
    if (this.followGraph) this.resolveImmediate(false);
    return true;
  }

  clearQueue() { this.queue = []; this.note('input', 'Cleared pending requests'); }

  cancelCamera() {
    this.queue = this.queue.filter(name => name !== 'photoTake');
    this.flags.takingPhoto = false;
    this.cameraCanceled = true;
    this.note('input', 'Canceled message; finish 6B, then play 6A backwards');
    if (this.followGraph) this.resolveImmediate(false);
  }

  take(edge, skipped) {
    const from = this.state;
    const wasReversingCamera = this.reversingCamera;
    this.reversingCamera = edge.playback === 'reverse';
    if (this.defaultOverride) {
      this.note('override', edge.kind === 'default' ? 'Used one-time default override; original weights restored' : 'Conditional transition won; default override cleared');
      this.defaultOverride = null;
    }
    if (from !== edge.to) this.petCycleCompleted = false;
    this.state = edge.to;
    if(edge.kind==='recall')this.recallEntry=edge.entry;
    this.generation++;
    if (from === '1a' && edge.kind === 'interrupt' && this.queue.length &&
        this.graph.eventTargets[this.queue[0]] === edge.to) {
      this.active = this.queue.shift();
      this.note('request', `Started ${this.active}`);
    }
    if ((['5c', '6c', '7c'].includes(from) || (from === '6a' && wasReversingCamera)) && edge.to === '1a') {
      if (this.active) this.note('request', `Completed ${this.active}`);
      this.active = null;
    }
    if (this.hidden) {
      this.flags.pet = false;
      this.flags.goodbye = false;
    }
    const record = this.note(edge.kind, `${from.toUpperCase()} → ${edge.to.toUpperCase()}`, {edge: edge.id, from, to: edge.to, skipped});
    this.history.push(record);
    if (this.history.length > 40) this.history.shift();
  }

  resolveImmediate(onEntry) {
    const visited = new Set();
    for (let hop = 0; hop <= this.states.size; hop++) {
      const edge = this.immediate();
      if (!edge) return;
      if (visited.has(this.state)) throw new Error('Immediate transition cycle detected');
      visited.add(this.state);
      this.take(edge, onEntry);
      onEntry = true;
    }
    throw new Error('Too many immediate transitions');
  }

  complete(token = this.generation) {
    if (token !== this.generation || this.hidden) return false;
    if (['1d','3c'].includes(this.state)) this.petCycleCompleted = true;
    if (!this.followGraph) { this.generation++; this.note('loop', `Repeat ${this.state.toUpperCase()} (solo)`); return true; }
    // A boolean can have changed since the final rendered drawing.
    if (this.immediate()) { this.resolveImmediate(false); return true; }
    let edge = this.eligible('afterClip').sort((a, b) => this.priority(a) - this.priority(b))[0];
    if (!edge) {
      const defaults = this.outgoing().filter(e => e.kind === 'default');
      if (!defaults.length) { this.note('error', `No eligible exit from ${this.state}`); return false; }
      if (this.defaultOverride?.from === this.state && this.defaultOverride.generation === this.generation) {
        edge = defaults.find(candidate => candidate.to === this.defaultOverride.to);
      }
      if (!edge && defaults.length === 1) edge = defaults[0];
      else if (!edge) {
        const total = defaults.reduce((sum, e) => sum + e.weight, 0);
        const sample = this.random();
        if (!Number.isFinite(sample) || sample < 0 || sample >= 1) throw new Error('Random sample must be in [0, 1)');
        let remaining = sample * total;
        edge = defaults.at(-1);
        for (const candidate of defaults) { remaining -= candidate.weight; if (remaining < 0) { edge = candidate; break; } }
      }
    }
    this.take(edge, false);
    this.resolveImmediate(true);
    return true;
  }

  jump(id) {
    if (!this.states.has(id)) throw new Error(`Unknown state: ${id}`);
    this.state = id;
    this.recallEntry = null;
    this.cameraCanceled = false;
    this.reversingCamera = false;
    this.petCycleCompleted = false;
    this.queue = [];
    this.active = null;
    this.defaultOverride = null;
    this.history = [];
    this.generation++;
    this.note('debug', `Jump to ${id.toUpperCase()}`);
    if (this.hidden) { this.flags.pet = false; this.flags.goodbye = false; }
    if (this.followGraph) this.resolveImmediate(true);
  }

  setMode(followGraph) {
    this.clearDefaultOverride();
    this.followGraph = Boolean(followGraph);
    this.note('debug', this.followGraph ? 'Following state graph' : 'Looping one clip; graph guards suspended');
    if (this.followGraph) this.resolveImmediate(false);
  }
}
