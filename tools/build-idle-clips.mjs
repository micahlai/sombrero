/**
 * Deterministic 12fps idle/petting authoring plans.
 * Character imagery comes exclusively from the accepted shared source master.
 * A compositor adapter is wired once that master passes visual acceptance.
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import crypto from 'node:crypto';

export const FRAME_RATE = Object.freeze({ numerator: 12, denominator: 1 });
export const FRAME_MS = 1000 / 12;
const TAU = Math.PI * 2;
const smooth = t => t * t * (3 - 2 * t);
const clamp = (x, a, b) => Math.max(a, Math.min(b, x));

function openEyes(t, blinkAt, width = 0.22) {
  const d = Math.abs(t - blinkAt);
  return d < width * .27 ? 'closed' : d < width * .5 ? 'half' : 'open';
}

/** Relative transforms, not replacement artwork. Positive x/y means right/down. */
export function neutralPose() {
  return {
    head: { x: 0, y: 0, rotationDeg: 0, scaleX: 1, scaleY: 1 },
    torso: { x: 0, y: 0, rotationDeg: 0, skewDeg: 0, scaleX: 1, scaleY: 1, bendPx:0,bendAxis:'x',bendAnchor:1 },
    wing_left: { x: 0, y: 0, rotationDeg: 0,bendPx:0,bendAxis:'y',bendAnchor:1 },
    wing_right: { x: 0, y: 0, rotationDeg: 0,bendPx:0,bendAxis:'y',bendAnchor:0 },
    leg_left: { x: 0, y: 0, rotationDeg: 0 },
    leg_right: { x: 0, y: 0, rotationDeg: 0 },
    eyeState: 'open',
  };
}

function fluidPose(phase, amount = 1) {
  const p = neutralPose();
  // Delay wings/feet relative to torso/head to give loose follow-through.
  const s = Math.sin(phase), c = Math.cos(phase);
  p.head = { x: amount * 7 * s, y: amount * -3.8 * (1 - c), rotationDeg: amount * (5.5 * s + 1.2 * Math.sin(phase * 2)), scaleX: 1, scaleY: 1 };
  p.torso = { x: amount * 2.5 * s, y: amount * 1.5 * (1 - c), rotationDeg: amount * 2.1 * s, skewDeg: amount * -4.8 * s, scaleX: 1 + amount * .017 * (1 - c), scaleY: 1 - amount * .018 * (1 - c),bendPx:amount*6.5*s,bendAxis:'x',bendAnchor:1 };
  p.wing_left = { x: amount * 1.7 * s, y: amount * 1.3 * (1-c), rotationDeg: amount * 12 * (Math.sin(phase - .45) - Math.sin(-.45)),bendPx:amount*7*Math.sin(phase),bendAxis:'y',bendAnchor:1 };
  p.wing_right = { x: amount * 1.7 * s, y: amount * 1.3 * (1-c), rotationDeg: amount * -10 * (Math.sin(phase + .25) - Math.sin(.25)),bendPx:amount*-6*Math.sin(phase),bendAxis:'y',bendAnchor:0 };
  p.leg_left = { x: 0, y: 0, rotationDeg: amount * -2.3 * s };
  p.leg_right = { x: 0, y: 0, rotationDeg: amount * -2.3 * s };
  return p;
}

function blend(a, b, t) {
  const out = structuredClone(a);
  for (const k of ['head','torso','wing_left','wing_right','leg_left','leg_right']) {
    for (const field of new Set([...Object.keys(a[k]), ...Object.keys(b[k])])) {
      const fallback = field.startsWith('scale') ? 1 : 0;
      const av=a[k][field]??fallback,bv=b[k][field]??fallback;
      out[k][field] = typeof av==='number'&&typeof bv==='number' ? av*(1-t)+bv*t : t<.5?av:bv;
    }
  }
  out.eyeState = t < .5 ? a.eyeState : b.eyeState;
  return out;
}

function petPose(phase = 0) {
  const p = neutralPose();
  const sway = Math.sin(phase);
  p.head = { x: 10 + 4.2 * sway, y: 6 + 2 * Math.cos(phase), rotationDeg: 7.5 + 3 * sway, scaleX: 1, scaleY: 1 };
  p.torso = { x: 3 + 1.5 * sway, y: 2, rotationDeg: 2.5 + 1.4 * sway, skewDeg: -5.5 - 1.5 * sway, scaleX: 1.032, scaleY: .966,bendPx:5+3*sway,bendAxis:'x',bendAnchor:1 };
  p.wing_left = { x: 2, y: 1, rotationDeg: -13 + 5 * Math.sin(phase - .4),bendPx:6+3*sway,bendAxis:'y',bendAnchor:1 };
  p.wing_right = { x: 2, y: 1, rotationDeg: 16 + 5.5 * Math.sin(phase + .5),bendPx:-7-3*sway,bendAxis:'y',bendAnchor:0 };
  p.eyeState = 'closed';
  return p;
}

const finishNeutral = frames => {
  frames[0].pose = neutralPose();
  frames[frames.length - 1].pose = neutralPose();
  return frames;
};

function sequence(count, sample) {
  return Array.from({ length: count }, (_, i) => ({
    tick: i, durationFrames: 1, durationMs: FRAME_MS,
    pose: sample(i, i / Math.max(1, count - 1)),
  }));
}

export function buildIdlePlans() {
  const wait = finishNeutral(sequence(48, (i, t) => {
    const p = fluidPose(TAU * t, .9);
    p.eyeState = openEyes(i/12, 2.25, .34);
    return p;
  }));
  const look = finishNeutral(sequence(48, (i, t) => {
    // Anticipation, curious glance, loose settle, opposite glance, then recovery.
    const envelope = Math.sin(Math.PI*t);
    const side = Math.sin(TAU*t);
    const p = fluidPose(TAU*t, 1.1);
    p.head.x += 7 * side * envelope;
    p.head.rotationDeg += 4 * side * envelope;
    p.head.y += -3 * envelope;
    p.eyeState = openEyes(i/12, 1.25, .28);
    return p;
  }));
  const petStart = petPose(0);
  const enter = sequence(9, (i, t) => {
    // Elastic ease overshoots slightly and settles without deforming the face.
    const ease = t === 1 ? 1 : 1 - Math.exp(-5*t) * Math.cos(7*t);
    const p = blend(neutralPose(), petStart, clamp(ease,0,1.09));
    p.eyeState = t < .45 ? 'open' : t < .65 ? 'half' : 'closed';
    return p;
  });
  const loop = sequence(24, (_, t) => petPose(TAU*t));
  const exit = sequence(9, (_, t) => blend(petStart, neutralPose(), smooth(t)));
  exit[exit.length-1].pose = neutralPose();
  return [
    { id:'idle.wait', loop:true, entryPose:'neutral', exitPose:'neutral', frames:wait },
    { id:'idle.look', loop:false, entryPose:'neutral', exitPose:'neutral', frames:look },
    { id:'react.pet.enter', loop:false, entryPose:'neutral', exitPose:'pet', frames:enter },
    { id:'react.pet.loop', loop:true, entryPose:'pet', exitPose:'pet', frames:loop },
    { id:'react.pet.exit', loop:false, entryPose:'pet', exitPose:'neutral', frames:exit },
  ];
}

export async function writePlans(directory) {
  await fs.mkdir(directory, { recursive: true });
  const plans = buildIdlePlans();
  const file = path.join(directory, 'idle-authoring-plans.json');
  await fs.writeFile(file, JSON.stringify({
    schemaVersion:1, characterId:'watercolor-duck', referenceVersion:'duck-v1-nostrils',
    frameRate:FRAME_RATE, authoringOnly:true, canvas:{width:512,height:512},
    groundPivot:{x:256,y:448}, plans,
  },null,2)+'\n');
  return file;
}

function attachedPoint(point,transform,pivot) {
  const a = (transform.rotationDeg ?? 0) * Math.PI / 180;
  const x = point.x-pivot.x, y = point.y-pivot.y;
  return {x:pivot.x+x*Math.cos(a)-y*Math.sin(a)+(transform.x??0),y:pivot.y+x*Math.sin(a)+y*Math.cos(a)+(transform.y??0)};
}

/** Export only after root has accepted the actual source master. */
export async function buildClips(masterPath,projectRoot) {
  const {loadMaster,renderPose,makeClip,writeClip,sharp} = await import('./asset-contract.mjs');
  const master = await loadMaster(masterPath);
  if(master.referenceVersion !== 'duck-v1-nostrils') throw new Error('Master reference version mismatch.');
  const frameRoot = path.join(projectRoot,'assets/duck/v1/clips');
  const plans = buildIdlePlans();
  const previewDir = path.join(projectRoot,'assets/duck/v1/previews');
  await fs.mkdir(previewDir,{recursive:true});
  const previewSequence=[];
  for(const plan of plans) {
    const directory=path.join(frameRoot,plan.id);
    await fs.mkdir(directory,{recursive:true});
    const frames=[];
    for(let i=0;i<plan.frames.length;i++) {
      const f=plan.frames[i];
      const file=`${plan.id}__${String(i).padStart(3,'0')}.png`;
      // The shared master's face and eyes inherit the exact same head transform.
      const transforms={...f.pose};
      if(master.layers.some(l=>l.group==='headgroup')) {
        delete transforms.head;
        transforms.headgroup=f.pose.head;
      }
      // Grounded idle feet remain pinned while the small leg strips follow.
      for(const id of ['leg_left','leg_right']) {
        const layer=master.layers.find(l=>l.id===id);
        if(layer) transforms[id]={...transforms[id],pivot:{x:layer.x+layer.width/2,y:448}};
      }
      delete transforms.eyeState;
      await renderPose({master,transforms,eyeState:f.pose.eyeState==='open'?'open':'closed',output:path.join(directory,file)});
      const pivot=master.groupPivots?.headgroup??master.groupPivots?.head??{x:256,y:290};
      const point=master.anchors?.bubble??master.attachments?.bubble??master.sockets?.bubble??{x:256,y:69};
      const bubble=attachedPoint(point,f.pose.head,pivot);
      frames.push({file,durationFrames:1,attachments:{bubble},markers:i===plan.frames.length-1?['complete']:[]});
      previewSequence.push(path.join(directory,file));
    }
    const clip=makeClip(plan.id,frames,{
      loop:plan.loop,entryPose:plan.entryPose,exitPose:plan.exitPose,
      safeInterruptionFrames:plan.loop?[0,frames.length-1]:[frames.length-1],
      sourceMasterVersion:master.masterVersion??master.version??'duck-master-v1',
      sourceMasterSha256:crypto.createHash('sha256').update(await fs.readFile(masterPath)).digest('hex'),
      sourceReferenceSha256:master.reference.sha256,
      authoring:'Shared watercolor raster parts with rigid face group and curved 12fps pose sampling; no independent per-frame image generation.',
    });
    await writeClip(directory,clip);
    console.log(`${plan.id}: ${frames.length} frames @ 12fps`);
  }
  const list=path.join(previewDir,'idle-pilot-frames.ffconcat');
  // Concat file timing would quantize frame timestamps; use a numbered staging
  // sequence and input -framerate 12 so the video has an exact rational rate.
  const staging=path.join(previewDir,'.idle-pilot-video-frames');
  await fs.mkdir(staging,{recursive:true});
  for(let i=0;i<previewSequence.length;i++) await fs.copyFile(previewSequence[i],path.join(staging,`${String(i).padStart(4,'0')}.png`));
  const movie=path.join(previewDir,'idle-pilot.mp4');
  const result=spawnSync('/opt/homebrew/bin/ffmpeg',['-hide_banner','-loglevel','error','-y','-framerate','12','-i',path.join(staging,'%04d.png'),'-filter_complex','color=c=0xf3f0e8:s=512x512:r=12[bg];[bg][0:v]overlay=shortest=1:format=auto,format=yuv420p[out]','-map','[out]','-c:v','libx264','-crf','18','-r','12','-movflags','+faststart',movie],{encoding:'utf8'});
  if(result.status!==0) throw new Error(`Preview export failed: ${result.stderr}`);
  await fs.rm(staging,{recursive:true,force:true});
  await fs.rm(list,{force:true});
  await fs.writeFile(path.join(previewDir,'idle-pilot.json'),JSON.stringify({
    frameRate:FRAME_RATE,clips:plans.map(p=>({clipId:p.id,frameCount:p.frames.length})),
    description:'12fps pilot: waiting sway/blink, look-around, pet entrance/loop/exit. Dark/transparent runtime frames are separate from the pale preview background.',
    limitations:['Sitting is not authored in this pilot; it needs an approved seated source silhouette.','Eye half-state maps to the approved closed-eye marks until a separate half-blink source is supplied.'],
  },null,2)+'\n');
  const selections=[
    ['idle.wait',0,'Neutral'],['idle.wait',12,'Idle bend'],['idle.wait',27,'Blink'],['idle.look',12,'Curious look'],
    ['react.pet.enter',0,'Pet entry: neutral'],['react.pet.enter',4,'Elastic entry'],['react.pet.loop',6,'Pet lean + closed eyes'],['react.pet.exit',8,'Recovered neutral'],
  ];
  const tiles=[];
  for(let i=0;i<selections.length;i++) {
    const[id,index,label]=selections[i];
    const input=path.join(frameRoot,id,`${id}__${String(index).padStart(3,'0')}.png`);
    const tile=await sharp(input).resize(256,256).flatten({background:i<4?'#f5f3ec':'#292b31'}).png().toBuffer();
    const x=(i%4)*256,y=Math.floor(i/4)*284;
    tiles.push({input:tile,left:x,top:y});
    const labelSVG=Buffer.from(`<svg width="256" height="28"><rect width="256" height="28" fill="${i<4?'#f5f3ec':'#292b31'}"/><text x="128" y="18" text-anchor="middle" fill="${i<4?'#3e3b35':'#eee8dc'}" font-family="sans-serif" font-size="12">${label}</text></svg>`);
    tiles.push({input:labelSVG,left:x,top:y+256});
  }
  await sharp({create:{width:1024,height:568,channels:4,background:'#f5f3ec'}}).composite(tiles).png().toFile(path.join(previewDir,'idle-pilot-contact-sheet.png'));
  return movie;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  if(process.argv.includes('--plans-only')) console.log(await writePlans(path.join(root,'assets/duck/v1/authoring/idle')));
  else {
    const mi=process.argv.indexOf('--master');
    if(mi<0||!process.argv[mi+1]) throw new Error('Pass --master <accepted shared manifest> or --plans-only.');
    console.log(await buildClips(path.resolve(root,process.argv[mi+1]),root));
  }
}
