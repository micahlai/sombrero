// Monotonic drawing clock; the renderer supplies timestamps and enable/disable.
export class DrawingClock {
  constructor(fps = 6) { this.fps = fps; this.elapsed = 0; this.last = null; this.speed = 1; }
  reset(now = null) { this.elapsed = 0; this.last = now; }
  advance(now, enabled = true) {
    if (this.last !== null && enabled) this.elapsed += Math.max(0, now - this.last) / 1000 * this.speed;
    this.last = now;
  }
  setFPS(fps) {
    if (!Number.isFinite(fps) || fps <= 0) throw new Error('FPS must be positive');
    this.elapsed *= this.fps / fps;
    this.fps = fps;
  }
  seek(frame) { this.elapsed = Math.max(0, frame) / this.fps; }
  frame(count, reversed = false) {
    const last = Math.max(0, count - 1);
    const frame = Math.min(last, Math.floor(this.elapsed * this.fps + 1e-8));
    return reversed ? last - frame : frame;
  }
  completed(count) { return count > 0 && this.elapsed * this.fps + 1e-8 >= count; }
}

export function naturalFrameSize(images) {
  return {width: Math.max(1, ...images.map(i => i.naturalWidth)),
    height: Math.max(1, ...images.map(i => i.naturalHeight))};
}

// Keep ready clips available synchronously so a cache hit never enters loading.
export class ClipCache {
  constructor(load, limit = 3) { this.loader = load; this.limit = limit; this.entries = new Map(); }
  peek(id) { return this.entries.get(id)?.clip; }
  load(id) {
    let entry = this.entries.get(id);
    if (entry) {
      this.entries.delete(id); this.entries.set(id, entry);
      return entry.promise;
    }
    entry = {};
    entry.promise = Promise.resolve().then(() => this.loader(id)).then(clip => {
      entry.clip = clip;
      return clip;
    }, error => {
      if (this.entries.get(id) === entry) this.entries.delete(id);
      throw error;
    });
    this.entries.set(id, entry);
    while (this.entries.size > this.limit) this.entries.delete(this.entries.keys().next().value);
    return entry.promise;
  }
}
