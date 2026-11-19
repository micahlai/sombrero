/** Local deterministic acting, fixed at 12 fps. Character compositing is gated. */
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const FRAME_RATE = { numerator: 12, denominator: 1 };
export const REFERENCE_VERSION = 'duck-v1-nostrils';
const p = (x = {}) => ({ x: 0, y: 0, rotationDeg: 0, scaleX: 1, scaleY: 1, ...x });
export const pose = (x = {}) => ({
  root: p(x.root), head: p(x.head), torso: p(x.torso),
  wing_left: p(x.leftWing), wing_right: p(x.rightWing),
  leg_left: p(x.leftLeg), leg_right: p(x.rightLeg),
});
const k = (transform, durationFrames = 1, markers = [], prop = null) => ({ transform, durationFrames, markers, prop });
const prop = (id, progress, x = {}) => ({ id, progress, ...x });
const clip = (id, keys, extra = {}) => ({
  schemaVersion: 1, characterId: 'watercolor-duck', referenceVersion: REFERENCE_VERSION,
  clipId: id, frameRate: FRAME_RATE, canvas: { width: 512, height: 512 },
  groundPivot: { x: 256, y: 448 }, entryPose: 'neutral', exitPose: 'neutral',
  loop: false, fallbackClip: 'idle.wait', keys, ...extra,
});

/** Faces are a fixed head group. There is deliberately no mouth parameter. */
export function buildPropTimelines() {
  const neutral = pose();
  const talk = [
    k(neutral, 2, ['neutral', 'bubble.show']),
    k(pose({ head: { y: 2, rotationDeg: -1 }, torso: { rotationDeg: 1, scaleY: 0.99 }, leftWing: { rotationDeg: 6, x: -1, scaleY: 1.05 }, rightWing: { rotationDeg: -8, x: 1, scaleY: 1.08 } })),
    k(pose({ head: { y: -2, rotationDeg: 2 }, torso: { rotationDeg: -2, scaleY: 1.02 }, leftWing: { rotationDeg: -8, x: 2, scaleY: 1.1 }, rightWing: { rotationDeg: 13, x: -2, scaleY: 1.16 } })),
    k(pose({ head: { y: -1, rotationDeg: 3 }, torso: { rotationDeg: -1 }, leftWing: { rotationDeg: -11, x: 3, scaleY: 1.08 }, rightWing: { rotationDeg: 18, x: -3, scaleY: 1.13 } }), 2),
    k(pose({ head: { y: 1, rotationDeg: -1 }, torso: { rotationDeg: 2, scaleY: 0.98 }, leftWing: { rotationDeg: 8, x: -1, scaleY: 1.04 }, rightWing: { rotationDeg: -5, x: 1 } }), 2),
    k(pose({ head: { y: -2, rotationDeg: -3 }, torso: { rotationDeg: 1, scaleY: 1.02 }, leftWing: { rotationDeg: -17, x: 2, scaleY: 1.16 }, rightWing: { rotationDeg: 9, x: -1, scaleY: 1.08 } }), 2),
    k(pose({ head: { y: 0, rotationDeg: -1 }, leftWing: { rotationDeg: -7, x: 1, scaleY: 1.08 }, rightWing: { rotationDeg: 3 } }), 2),
    k(neutral, 4, ['neutral', 'bubble.hide']),
  ];
  const shoo = [
    k(neutral, 2, ['neutral']),
    k(pose({ head: { rotationDeg: -2, x: -2 }, torso: { rotationDeg: -3 }, rightWing: { rotationDeg: 8, x: -3, y: 2, scaleY: 0.96 } })),
    k(pose({ head: { rotationDeg: 1, x: 1 }, torso: { rotationDeg: 3 }, rightWing: { rotationDeg: -20, x: 2, y: -3, scaleY: 1.13 } })),
    k(pose({ head: { rotationDeg: 3, x: 2 }, torso: { rotationDeg: 4 }, rightWing: { rotationDeg: -39, x: 6, y: -5, scaleY: 1.24 } }), 1, ['shoo']),
    k(pose({ head: { rotationDeg: 2, x: 1 }, torso: { rotationDeg: 2 }, rightWing: { rotationDeg: -26, x: 4, y: -2, scaleY: 1.13 } })),
    k(pose({ head: { rotationDeg: -1 }, torso: { rotationDeg: -2 }, rightWing: { rotationDeg: -8, x: 1, y: 1, scaleY: 0.98 } })),
    k(pose({ head: { rotationDeg: 2, x: 1 }, torso: { rotationDeg: 3 }, rightWing: { rotationDeg: -35, x: 5, y: -4, scaleY: 1.2 } }), 1, ['shoo']),
    k(pose({ head: { rotationDeg: 1 }, torso: { rotationDeg: 1 }, rightWing: { rotationDeg: -13, x: 2, y: -1, scaleY: 1.07 } })),
    k(pose({ head: { rotationDeg: -1 }, torso: { rotationDeg: -1 }, rightWing: { rotationDeg: 5, x: -1, scaleY: 0.98 } }), 2),
    k(neutral, 4, ['neutral']),
  ];
  const held = pose({ leftWing: { rotationDeg: -30, x: 8, y: 8, scaleY: 1.08 }, rightWing: { rotationDeg: 30, x: -8, y: 8, scaleY: 1.08 } });
  const enterBook = [
    k(neutral, 1, ['neutral']),
    ...[0.2, 0.45, 0.7, 0.9, 1.03, 1].map((t, i) => k(pose({ head: { y: t * 3, rotationDeg: -t }, torso: { scaleY: 1 - t * 0.02 }, leftWing: { rotationDeg: -30 * t, x: 8 * t, y: 8 * t, scaleY: 1 + 0.08 * t }, rightWing: { rotationDeg: 30 * t, x: -8 * t, y: 8 * t, scaleY: 1 + 0.08 * t } }), 1, i === 5 ? ['book.ready'] : [], prop('book', Math.min(1, t)))),
  ];
  const read = [
    k(held, 12, ['book.ready'], prop('book', 1)),
    k(pose({ head: { y: 3, rotationDeg: -2 }, leftWing: { rotationDeg: -30, x: 8, y: 8, scaleY: 1.08 }, rightWing: { rotationDeg: 30, x: -8, y: 8, scaleY: 1.08 } }), 6, [], prop('book', 1)),
    k(pose({ head: { y: 4, rotationDeg: 2 }, leftWing: { rotationDeg: -29, x: 8, y: 8, scaleY: 1.08 }, rightWing: { rotationDeg: 31, x: -8, y: 8, scaleY: 1.08 } }), 6, [], prop('book', 1)),
    k(pose({ head: { y: 2, rotationDeg: 1 }, leftWing: { rotationDeg: -33, x: 9, y: 5, scaleY: 1.12 }, rightWing: { rotationDeg: 26, x: -7, y: 10, scaleY: 1.06 } }), 2, ['page.turn'], prop('book', 1, { rotationDeg: -2 })),
    k(held, 12, ['book.ready'], prop('book', 1)),
  ];
  const exitBook = [...enterBook].reverse().map((key, i, a) => ({ ...key, markers: i === a.length - 1 ? ['neutral'] : [] }));
  const photoHold = pose({ head: { rotationDeg: -2 }, leftWing: { rotationDeg: -22, x: 9, y: 10, scaleY: 1.12 }, rightWing: { rotationDeg: 22, x: -9, y: 10, scaleY: 1.12 } });
  const carryPhoto = pose({ leftWing: { rotationDeg: -18, x: 6, y: 14, scaleY: 1.1 }, rightWing: { rotationDeg: 18, x: -6, y: 14, scaleY: 1.1 } });
  const showPhoto = [k(carryPhoto, 1, ['photo.carried'], prop('polaroid', 0)), ...[0.15, 0.35, 0.65, 0.9, 1.04, 1].map((t, i) => k(pose({ head: { rotationDeg: -2 * t }, torso: { rotationDeg: Math.sin(t * Math.PI) * 2 }, leftWing: { rotationDeg: -18 - 4 * t, x: 6 + 3 * t, y: 14 - 4 * t, scaleY: 1.1 + 0.02 * t }, rightWing: { rotationDeg: 18 + 4 * t, x: -6 - 3 * t, y: 14 - 4 * t, scaleY: 1.1 + 0.02 * t } }), 1, i === 5 ? ['photo.ready'] : [], prop('polaroid', Math.min(t, 1))))];
  const holdPhoto = [k(photoHold, 18, ['photo.ready'], prop('polaroid', 1)), k(pose({ head: { rotationDeg: 1, y: -1 }, leftWing: { rotationDeg: -23, x: 9, y: 9, scaleY: 1.12 }, rightWing: { rotationDeg: 23, x: -9, y: 9, scaleY: 1.12 } }), 6, [], prop('polaroid', 1, { rotationDeg: 1 })), k(photoHold, 18, ['photo.ready'], prop('polaroid', 1))];
  const stowPhoto = [...showPhoto].reverse().map(key => ({ ...key, markers: [] }));
  stowPhoto.push(k(carryPhoto, 1, [], prop('polaroid', 0, { yOffset: 38 })), k(pose({ leftWing: { rotationDeg: -8, x: 3, y: 8, scaleY: 1.04 }, rightWing: { rotationDeg: 8, x: -3, y: 8, scaleY: 1.04 } }), 1, [], prop('polaroid', 0, { yOffset: 96 })), k(neutral, 2, ['neutral', 'photo.stowed']));
  return [
    clip('gesture.talk', talk), clip('gesture.shoo', shoo),
    clip('activity.read.enter', enterBook, { exitPose: 'book-held' }),
    clip('activity.read.loop', read, { loop: true, entryPose: 'book-held', exitPose: 'book-held' }),
    clip('activity.read.exit', exitBook, { entryPose: 'book-held' }),
    clip('photo.present', showPhoto, { entryPose: 'photo-carried', exitPose: 'photo-held' }),
    clip('photo.hold', holdPhoto, { loop: true, entryPose: 'photo-held', exitPose: 'photo-held' }),
    clip('photo.stow', stowPhoto, { entryPose: 'photo-held' }),
  ];
}

export function validateTimelines(clips) {
  for (const c of clips) {
    if (c.frameRate.numerator !== 12 || c.frameRate.denominator !== 1) throw new Error('Exactly 12 fps required');
    for (const key of c.keys) {
      if (!Number.isInteger(key.durationFrames) || key.durationFrames < 1) throw new Error(`${c.clipId}: invalid hold`);
      for (const part of Object.values(key.transform)) for (const n of Object.values(part)) if (!Number.isFinite(n)) throw new Error(`${c.clipId}: nonfinite transform`);
    }
    if (c.loop && JSON.stringify(c.keys[0].transform) !== JSON.stringify(c.keys.at(-1).transform)) throw new Error(`${c.clipId}: loop does not close`);
  }
  return { clipCount: clips.length, uniquePoseCount: clips.reduce((n, c) => n + c.keys.length, 0), timelineFrames: clips.reduce((n, c) => n + c.keys.reduce((m, k) => m + k.durationFrames, 0), 0) };
}

export async function exportPropClips(masterPath, outputRoot = 'assets/duck/v1/clips') {
  const lock = JSON.parse(await fs.readFile('docs/character-reference.json', 'utf8'));
  if (!lock.productionDependencies.artistFanoutReady) throw new Error('Root has not accepted the shared master/pilot gate yet');
  const { loadMaster, renderPose, makeClip, writeClip } = await import('./asset-contract.mjs');
  const master = await loadMaster(masterPath);
  const timelines = buildPropTimelines();
  validateTimelines(timelines);
  const torsoZ = master.layers.find(l => l.id === 'torso')?.z ?? 10;
  const propZ = torsoZ + 0.5;
  for (const timeline of timelines) {
    const dir = path.join(outputRoot, timeline.clipId);
    await fs.mkdir(dir, { recursive: true });
    const frames = [];
    for (const [index, key] of timeline.keys.entries()) {
      const file = `${timeline.clipId}__${String(index).padStart(3, '0')}.png`;
      const extras = [];
      let attachment = {};
      const transform = structuredClone(key.transform);
      // Reuse the source pixels, bending loose distal wings while shoulders stay anchored.
      transform.wing_left = { ...transform.wing_left, bendPx: -transform.wing_left.rotationDeg * 0.3, bendAxis: 'y', bendAnchor: 1 };
      transform.wing_right = { ...transform.wing_right, bendPx: transform.wing_right.rotationDeg * 0.3, bendAxis: 'y', bendAnchor: 0 };
      transform.torso = { ...transform.torso, bendPx: transform.torso.rotationDeg * 1.5, bendAxis: 'x', bendAnchor: 1 };
      if (key.prop) {
        const isBook = key.prop.id === 'book';
        const progress = key.prop.progress;
        const w = isBook ? 150 : 116;
        const h = isBook ? 101 : 116;
        const cx = 256;
        const cy = (isBook ? 500 - progress * 114 : 413 - progress * 26) + (key.prop.yOffset ?? 0);
        const rotationDeg = key.prop.rotationDeg ?? (1 - progress) * -6;
        extras.push({ id: 'held_prop', file: path.resolve(`assets/duck/v1/props/${isBook ? 'book-open' : 'polaroid'}.png`), x: cx - w / 2, y: cy - h / 2, width: w, height: h, pivot: { x: cx, y: cy }, z: propZ });
        transform.held_prop = { rotationDeg };
        attachment = {
          prop: { x: cx, y: cy, rotationDeg, scaleX: w / (isBook ? 580 : 520), scaleY: h / (isBook ? 390 : 520) },
          ...(isBook ? {} : { picture: { x: cx - w / 2 + 65 * w / 520, y: cy - h / 2 + 78 * h / 520, width: 390 * w / 520, height: 285 * h / 520, rotationDeg } }),
        };
      }
      const activeMaster = key.prop ? { ...master, layers: master.layers.map(l => /wing/.test(l.id) ? { ...l, z: 7 + (l.id === 'wing_right' ? 0.1 : 0) } : l) } : master;
      await renderPose({ master: activeMaster, transforms: transform, extraLayers: extras, output: path.join(dir, file) });
      frames.push({ file, durationFrames: key.durationFrames, attachments: { bubble: { x: 365, y: 130 }, ...attachment }, markers: key.markers });
    }
    const { keys, ...options } = timeline;
    await writeClip(dir, makeClip(timeline.clipId, frames, { ...options, sourceMasterVersion: master.masterVersion, sourceMasterSha256: master.manifestSha256, sourceReferenceSha256: master.reference.sha256, safeInterruptionFrames: frames.map((f, i) => f.markers.some(m => ['neutral', 'book.ready', 'photo.ready'].includes(m)) ? i : -1).filter(i => i >= 0), production: { masterManifest: path.relative(process.cwd(), path.resolve(masterPath)), method: 'Shared painted source parts with exact twelve-fps transforms; fixed closed bill', propsBaked: true } }));
  }
  return { clips: timelines.length, frames: timelines.reduce((n, c) => n + c.keys.length, 0) };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const clips = buildPropTimelines();
  const summary = validateTimelines(clips);
  const masterPath = process.argv.find(x => x.startsWith('--master='))?.slice(9);
  const dest = process.argv.find(x => x.startsWith('--timelines='))?.slice(12);
  if (masterPath && process.argv.includes('--export')) {
    console.log(JSON.stringify(await exportPropClips(masterPath)));
    process.exit(0);
  }
  if (dest) { await fs.mkdir(path.dirname(dest), { recursive: true }); await fs.writeFile(dest, JSON.stringify(clips, null, 2) + '\n'); }
  else if (!process.argv.includes('--check')) throw new Error('Character production waits for accepted master and pilot. Use --check for timing validation.');
  console.log(JSON.stringify({ ...summary, status: 'timelines-ready-master-pilot-gate-pending' }));
}
