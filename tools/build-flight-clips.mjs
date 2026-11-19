/**
 * Deterministic flight/edge acting for duck-v1-nostrils.
 *
 * This module does not generate character art. Each pose transforms the same
 * shared painted parts. Root travel and edge clipping stay outside the bitmap.
 * Export wiring is added only after the lead's master and the pilot are locked.
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import os from 'node:os';

export const REFERENCE_VERSION = 'duck-v1-nostrils';
export const CANVAS = { width: 512, height: 512 };
export const GROUND_PIVOT = { x: 256, y: 448 };
export const FRAME_RATE = { numerator: 12, denominator: 1 };

const part = (values = {}) => ({ x: 0, y: 0, rotationDeg: 0, scaleX: 1, scaleY: 1, bendPx: 0, skewXDeg: 0, ...values });

/** Degrees use a screen coordinate system: positive is clockwise. */
export function pose({ head = {}, torso = {}, leftWing = {}, rightWing = {}, leftLeg = {}, rightLeg = {}, root = {} } = {}) {
  return {
    root: part(root),
    head: part(head),
    torso: part({ bendAnchor: 0, ...torso }),
    wing_left: part({ bendAxis: 'y', bendAnchor: 1, ...leftWing }),
    wing_right: part({ bendAxis: 'y', bendAnchor: 0, ...rightWing }),
    leg_left: part(leftLeg),
    leg_right: part(rightLeg),
  };
}

const key = (durationFrames, transform, marker = undefined) => ({ durationFrames, transform, ...(marker ? { marker } : {}) });

/**
 * Head here means the full fixed head + face group: eyes, bill, both nostrils.
 * The lead's layer adapter must never apply these keys to the bill separately.
 */
export function buildFlightTimelines() {
  const neutral = pose();
  const airborne = pose({ leftWing: { rotationDeg: 22 }, rightWing: { rotationDeg: -22 }, leftLeg: { rotationDeg: -9 }, rightLeg: { rotationDeg: 9 } });
  const launch = [
    key(2, neutral, 'neutral'),
    key(1, pose({ head: { y: 3, rotationDeg: -1 }, torso: { scaleY: 0.97, y: 2, bendPx: -2 }, leftWing: { rotationDeg: 5 }, rightWing: { rotationDeg: -5 } })),
    key(1, pose({ head: { y: 7, rotationDeg: -2 }, torso: { scaleY: 0.94, y: 4, bendPx: -3 }, leftWing: { rotationDeg: 10 }, rightWing: { rotationDeg: -10 } }), 'anticipation'),
    key(1, pose({ head: { y: 4, rotationDeg: 1 }, torso: { y: 2, bendPx: 3 }, leftWing: { rotationDeg: -23, bendPx: -5 }, rightWing: { rotationDeg: 23, bendPx: 5 } })),
    key(1, pose({ head: { rotationDeg: 2 }, torso: { bendPx: 2 }, leftWing: { rotationDeg: -43, bendPx: -6 }, rightWing: { rotationDeg: 43, bendPx: 6 }, leftLeg: { rotationDeg: -5 }, rightLeg: { rotationDeg: 5 } }), 'lift'),
    key(1, pose({ leftWing: { rotationDeg: -9 }, rightWing: { rotationDeg: 9 }, leftLeg: { rotationDeg: -8 }, rightLeg: { rotationDeg: 8 } })),
    key(1, airborne, 'airborne'),
  ];
  const flapAngles = [22, 8, -18, -43, -28, -6, 17, 22];
  const flap = flapAngles.map((a, index) => key(index === 3 ? 2 : 1,
    pose({ head: { rotationDeg: [0, -1, -2, -1, 0, 1, 1, 0][index] }, torso: { bendPx: [0, -2, -3, -1, 2, 3, 1, 0][index] }, leftWing: { rotationDeg: a, bendPx: [-4, 0, 4, 6, 2, -3, -5, -4][index] }, rightWing: { rotationDeg: -a, bendPx: [4, 0, -4, -6, -2, 3, 5, 4][index] }, leftLeg: { rotationDeg: -9 }, rightLeg: { rotationDeg: 9 } }),
    index === 0 ? 'loopStart' : undefined));
  const land = [
    key(1, airborne, 'airborne'),
    key(1, pose({ leftWing: { rotationDeg: -28 }, rightWing: { rotationDeg: 28 }, leftLeg: { rotationDeg: -3 }, rightLeg: { rotationDeg: 3 } })),
    key(1, pose({ leftWing: { rotationDeg: -10 }, rightWing: { rotationDeg: 10 } }), 'touchdown'),
    key(1, pose({ head: { y: 6, rotationDeg: 2 }, torso: { scaleY: 0.95, y: 3, bendPx: 3 }, leftWing: { rotationDeg: 6 }, rightWing: { rotationDeg: -6 } })),
    key(1, pose({ head: { y: 2, rotationDeg: -1 }, torso: { scaleY: 0.98, y: 1, bendPx: -2 } })),
    key(2, neutral, 'neutral'),
  ];
  const peekEnter = [
    key(1, neutral, 'offstage'),
    key(1, pose({ head: { rotationDeg: 2, x: 1 } })),
    key(1, pose({ head: { rotationDeg: 4, x: 2 }, leftWing: { rotationDeg: -3 } })),
    key(1, pose({ head: { rotationDeg: 6, x: 3 }, leftWing: { rotationDeg: -5 } })),
    key(1, pose({ head: { rotationDeg: 5, x: 3 }, leftWing: { rotationDeg: -4 } })),
    key(2, pose({ head: { rotationDeg: 4, x: 2 }, leftWing: { rotationDeg: -4 } }), 'peekReady'),
  ];
  const peekHold = [
    key(8, pose({ head: { rotationDeg: 4, x: 2 }, leftWing: { rotationDeg: -4 } }), 'loopStart'),
    key(2, pose({ head: { rotationDeg: 2, x: 1 }, leftWing: { rotationDeg: -4 } })),
    key(6, pose({ head: { rotationDeg: 2, x: 1 }, leftWing: { rotationDeg: -4 } })),
    key(2, pose({ head: { rotationDeg: 4, x: 2 }, leftWing: { rotationDeg: -4 } })),
  ];
  const peekExit = [...peekEnter].reverse().map(({ durationFrames, transform }, i, arr) => key(durationFrames, transform, i === arr.length - 1 ? 'offstage' : undefined));
  // Both little wings visibly keep hold of the photo during the return. The
  // shoulders and distal paint flex gently; the prop never appears from nowhere.
  const carryPose = (head = {}, torso = {}, legs = {}, wingDelta = 0) => pose({
    head, torso,
    leftWing: { rotationDeg: -18 + wingDelta, x: 6, y: 14, scaleY: 1.1, bendPx: 5.4 },
    rightWing: { rotationDeg: 18 - wingDelta, x: -6, y: 14, scaleY: 1.1, bendPx: 5.4 },
    leftLeg: { rotationDeg: legs.left ?? -9 }, rightLeg: { rotationDeg: legs.right ?? 9 },
  });
  const carryFlap = [0, 2, 4, 0, -2, -4, -2, 0].map((wingDelta, i) => key(i === 3 ? 2 : 1,
    carryPose({ rotationDeg: [0, -1, -2, -1, 0, 1, 1, 0][i] }, { bendPx: [0, -2, -3, -1, 2, 3, 1, 0][i] }, {}, wingDelta), i === 0 ? 'loopStart' : undefined));
  const carryLand = [
    key(1, carryPose(), 'airborne'),
    key(1, carryPose({ rotationDeg: -1 }, { bendPx: -2 }, { left: -3, right: 3 }, 2)),
    key(1, carryPose({}, {}, { left: 0, right: 0 }), 'touchdown'),
    key(1, carryPose({ y: 5, rotationDeg: 2 }, { scaleY: 0.95, y: 3, bendPx: 3 }, { left: 0, right: 0 }, -1)),
    key(1, carryPose({ y: 2, rotationDeg: -1 }, { scaleY: 0.98, y: 1, bendPx: -1 }, { left: 0, right: 0 })),
    key(2, carryPose({}, {}, { left: 0, right: 0 }), 'photoCarried'),
  ];
  return [
    clip('flight.launch', launch, { exitPose: 'flight.flap.start', travel: { mode: 'host-root', phase: 'launch', beginsAtMarker: 'lift', durationFrames: 4 }, entrancePose: 'neutral' }),
    clip('flight.flap', flap, { loop: true, entrancePose: 'flight.flap.start', exitPose: 'flight.flap.start', travel: { mode: 'host-root', phase: 'travel', edgeClip: true, path: { kind: 'cubicBezier', coordinateSpace: 'normalizedCurrentToEdge', points: [[0, 0], [0.24, -0.28], [0.68, 0.12], [1, -0.18]] }, bob: { amplitudePx: 3, periodFrames: 9 } } }),
    clip('flight.land', land, { entrancePose: 'flight.flap.start', exitPose: 'neutral', travel: { mode: 'host-root', phase: 'landing', endsAtMarker: 'touchdown' } }),
    clip('edge.peek.enter', peekEnter, { entrancePose: 'neutral', exitPose: 'peek', edge: { mode: 'runtime-mask', defaultSide: 'left', mirrorValidated: false, progressFrom: 0, progressTo: 1, visibleFractionAtHold: 0.46 } }),
    clip('edge.peek.hold', peekHold, { loop: true, entrancePose: 'peek', exitPose: 'peek', edge: { mode: 'runtime-mask', defaultSide: 'left', mirrorValidated: false, progressFrom: 1, progressTo: 1, visibleFractionAtHold: 0.46 } }),
    clip('edge.peek.exit', peekExit, { entrancePose: 'peek', exitPose: 'neutral', edge: { mode: 'runtime-mask', defaultSide: 'left', mirrorValidated: false, progressFrom: 1, progressTo: 0, visibleFractionAtHold: 0.46 } }),
    clip('flight.flap.photo', carryFlap, { loop: true, entrancePose: 'flight.photo.start', exitPose: 'flight.photo.start', photo: { center: { x: 256, y: 413 }, size: 116 }, travel: { mode: 'host-root', phase: 'return', edgeClip: true, path: { kind: 'cubicBezier', coordinateSpace: 'normalizedEdgeToHome', points: [[0, 0], [0.22, -0.20], [0.64, 0.14], [1, 0]] } } }),
    clip('flight.land.photo', carryLand, { entrancePose: 'flight.photo.start', exitPose: 'photo-carried', photo: { center: { x: 256, y: 413 }, size: 116 }, travel: { mode: 'host-root', phase: 'landing', endsAtMarker: 'touchdown' } }),
  ];
}

function clip(id, keys, extra = {}) {
  return { schemaVersion: 1, referenceVersion: REFERENCE_VERSION, id, frameRate: FRAME_RATE, canvas: CANVAS, groundPivot: GROUND_PIVOT, loop: false, fallbackClip: 'idle.wait', keys, ...extra };
}

export function validateTimelines(clips) {
  const ids = new Set();
  for (const c of clips) {
    if (ids.has(c.id)) throw new Error(`Duplicate clip ${c.id}`);
    ids.add(c.id);
    for (const [i, k] of c.keys.entries()) {
      if (!Number.isInteger(k.durationFrames) || k.durationFrames <= 0) throw new Error(`${c.id}[${i}] has invalid duration`);
      for (const transform of Object.values(k.transform)) {
        for (const [name, value] of Object.entries(transform)) {
          if (name === 'bendAxis' && ['x', 'y'].includes(value)) continue;
          if (!Number.isFinite(value)) throw new Error(`${c.id}[${i}] has invalid transform`);
        }
      }
    }
    if (c.loop && JSON.stringify(c.keys[0].transform) !== JSON.stringify(c.keys.at(-1).transform)) throw new Error(`${c.id} does not close exactly`);
  }
  return { clips: clips.length, frames: clips.reduce((sum, c) => sum + c.keys.length, 0) };
}

/** Export only after the root has accepted the master and idle/pet pilot. */
export async function exportFlightClips(masterPath, projectRoot) {
  const { loadMaster, renderPose, makeClip, writeClip } = await import('./asset-contract.mjs');
  const master = await loadMaster(masterPath);
  const clips = buildFlightTimelines();
  validateTimelines(clips);
  if (master.referenceVersion && master.referenceVersion !== REFERENCE_VERSION) throw new Error('Master character version mismatch');
  const layerKeys = new Set(master.layers.flatMap(l => [l.id, l.group].filter(Boolean)));
  const required = ['head', 'torso', 'wing_left', 'wing_right', 'leg_left', 'leg_right'];
  for (const name of required) if (!layerKeys.has(name)) throw new Error(`Master missing required part/group ${name}`);
  const outputRoot = path.join(projectRoot, 'assets/duck/v1/clips');
  const previewRoot = path.join(projectRoot, 'assets/duck/v1/previews');
  await fs.mkdir(previewRoot, { recursive: true });
  const built = [];
  for (const timeline of clips) {
    const directory = path.join(outputRoot, timeline.id);
    await fs.mkdir(directory, { recursive: true });
    const frames = [];
    for (const [index, k] of timeline.keys.entries()) {
      const file = `${timeline.id}__${String(index).padStart(3, '0')}.png`;
      const transforms = structuredClone(k.transform);
      const extras = [];
      let activeMaster = master;
      let propAttachments = {};
      if (timeline.photo) {
        const { center: { x: cx, y: cy }, size } = timeline.photo;
        extras.push({ id: 'carried_polaroid', file: path.join(projectRoot, 'assets/duck/v1/props/polaroid.png'), x: cx - size / 2, y: cy - size / 2, width: size, height: size, pivot: { x: cx, y: cy }, z: 4.5 });
        activeMaster = { ...master, layers: master.layers.map(l => /wing/.test(l.id) ? { ...l, z: 7 + (l.id === 'wing_right' ? 0.1 : 0) } : l) };
        propAttachments = { prop: { x: cx, y: cy, rotationDeg: 0, scaleX: size / 520, scaleY: size / 520 }, picture: { x: cx - size / 2 + 65 * size / 520, y: cy - size / 2 + 78 * size / 520, width: 390 * size / 520, height: 285 * size / 520, rotationDeg: 0 } };
      }
      await renderPose({ master: activeMaster, transforms, extraLayers: extras, output: path.join(directory, file) });
      const bubble = transformPoint(master.anchors?.bubble ?? master.attachments?.bubble ?? { x: 256, y: 72 }, transforms.head, master.groupPivots?.head ?? { x: 256, y: 300 });
      frames.push({ file, durationFrames: k.durationFrames, attachments: { bubble, ...propAttachments }, markers: k.marker ? [k.marker] : [] });
    }
    const clip = makeClip(timeline.id, frames, {
      loop: timeline.loop,
      entryPose: timeline.entrancePose,
      exitPose: timeline.exitPose,
      safeInterruptionFrames: timeline.keys.flatMap((k, index) => ['neutral', 'airborne', 'loopStart', 'peekReady', 'offstage', 'photoCarried'].includes(k.marker) ? [index] : []),
      ...(timeline.travel ? { rootMotion: timeline.travel } : {}),
      ...(timeline.edge ? { edgeMask: timeline.edge } : {}),
      sourceMaster: path.relative(projectRoot, path.resolve(masterPath)),
      sourceMasterVersion: master.masterVersion,
      sourceMasterSha256: master.manifestSha256,
      sourceReferenceSha256: master.reference.sha256,
      authoring: { technique: 'shared-painted-part-animation', faceArticulation: false, pigmentRerendered: false, frameTransforms: timeline.keys.map(k => k.transform) },
    });
    await writeClip(directory, clip);
    const previewPath = path.join(previewRoot, `flight-${timeline.id}.gif`);
    await makePreview(directory, clip, previewPath);
    built.push({ clipId: clip.clipId, frames: frames.length, durationFrames: frames.reduce((s, f) => s + f.durationFrames, 0), preview: previewPath });
  }
  await fs.writeFile(path.join(previewRoot, 'flight-production-notes.md'), `# Flight and edge animation handoff\n\nSource: ${path.relative(projectRoot, path.resolve(masterPath))}. All body frames reuse the shared watercolor layers and fixed head/face. Runtime clip timing is exactly 12 fps through integer frame holds. GIFs are review proxies whose centisecond timestamps cannot exactly represent every 1/12-second hold.\n\nFlight root travel is intentionally separate from pose art, using a curved host-driven path and an edge clip. Peek frames are intentionally unmasked; apply the manifest edge mask and entry/exit progress in the application. The default side is left; right-side mirroring remains subject to visual validation.\n\nThe head/bill/nostrils remain a rigid group. Small torso and wing bends provide loose acting while preserving the master proportions. No independently generated character frames, external image integrations, or mouth motion are included.\n`);
  return built;
}

function transformPoint(point, transform = {}, pivot) {
  const angle = (transform.rotationDeg ?? 0) * Math.PI / 180;
  const x = (point.x - pivot.x) * (transform.scaleX ?? 1);
  const y = (point.y - pivot.y) * (transform.scaleY ?? 1);
  return { x: Number((pivot.x + x * Math.cos(angle) - y * Math.sin(angle) + (transform.x ?? 0)).toFixed(3)), y: Number((pivot.y + x * Math.sin(angle) + y * Math.cos(angle) + (transform.y ?? 0)).toFixed(3)) };
}

async function makePreview(directory, clip, output) {
  const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'duck-flight-preview-'));
  try {
    let index = 0;
    for (const frame of clip.frames) {
      for (let held = 0; held < frame.durationFrames; held++) {
        await fs.symlink(path.join(directory, frame.file), path.join(temp, `frame${String(index++).padStart(4, '0')}.png`));
      }
    }
    const ffmpeg = process.env.FFMPEG_PATH || '/opt/homebrew/bin/ffmpeg';
    await promisify(execFile)(ffmpeg, ['-y', '-v', 'error', '-framerate', '12', '-i', path.join(temp, 'frame%04d.png'), '-filter_complex', '[0:v]scale=256:256:flags=lanczos,split[a][b];[a]palettegen=reserve_transparent=1[p];[b][p]paletteuse=alpha_threshold=96', '-loop', '0', output], { maxBuffer: 1024 * 1024 });
  } finally {
    await fs.rm(temp, { recursive: true, force: true });
  }
}

async function main() {
  const clips = buildFlightTimelines();
  const result = validateTimelines(clips);
  if (process.argv.includes('--check')) {
    console.log(JSON.stringify({ ...result, status: 'timelines-valid-master-gate-pending' }));
    return;
  }
  const masterPath = process.argv.find(x => x.startsWith('--master='))?.slice('--master='.length);
  if (process.argv.includes('--export')) {
    if (!process.argv.includes('--accepted-master-pilot')) throw new Error('Export requires the accepted master/pilot gate.');
    if (!masterPath) throw new Error('Export requires --master=<real accepted manifest path>.');
    const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
    console.log(JSON.stringify(await exportFlightClips(masterPath, root), null, 2));
    return;
  }
  const output = process.argv.find(x => x.startsWith('--timelines='))?.slice('--timelines='.length);
  if (!output) throw new Error('Production export waits for accepted master/pilot. Use --check or --timelines=<path> to inspect acting keys.');
  await fs.mkdir(path.dirname(output), { recursive: true });
  await fs.writeFile(output, `${JSON.stringify(clips, null, 2)}\n`);
  console.log(`${output}: ${result.clips} timeline specifications, no art generated`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) main().catch(error => { console.error(error.message); process.exitCode = 1; });
