/** Deterministic technical extraction/registration of imagegen-authored cutouts. */
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {sharp,loadMaster,renderPose} from './asset-contract.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const out=path.join(root,'assets/duck/v1/source');
const boardPath=path.join(root,'generated_images/exec-3b829145-e714-4dff-bc4e-9dd4c00261fc.png');
const refPath=path.join(root,'generated_images/exec-0f994ff1-3130-4298-b10e-bbb99ffb5446.png');
const specs=[
  {id:'head_paint',region:[0,0,520,500],x:152,y:88,width:208,height:230,pivot:{x:256,y:309},group:'head',z:5},
  {id:'torso',region:[600,50,400,450],x:211,y:300,width:90,height:112,pivot:{x:256,y:403},z:4},
  {id:'wing_left',region:[1100,70,350,400],x:161,y:326,width:70,height:63,pivot:{x:227,y:345},z:2},
  {id:'wing_right',region:[100,490,400,280],x:281,y:326,width:65,height:63,pivot:{x:285,y:345},z:3},
  {id:'leg_left',region:[650,500,250,250],x:224,y:400,width:28,height:48,pivot:{x:246,y:405},z:0},
  {id:'leg_right',region:[1150,500,250,250],x:267,y:400,width:28,height:48,pivot:{x:273,y:405},z:1},
  {id:'eyes_open',region:[100,810,330,150],x:222,y:202,width:68,height:25,pivot:{x:256,y:214},group:'head',z:6,whenEyeState:'open'},
  {id:'eyes_closed',region:[600,810,350,150],x:222,y:211,width:68,height:12,pivot:{x:256,y:214},group:'head',z:6,whenEyeState:'closed'}
];

await fs.mkdir(path.join(out,'layers'),{recursive:true});
const layers=[];
for(const spec of specs){
  const [left,top,width,height]=spec.region;
  const raw=await sharp(boardPath).extract({left,top,width,height}).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  let minX=width,minY=height,maxX=-1,maxY=-1;
  for(let y=0;y<height;y++)for(let x=0;x<width;x++){
    const i=(y*width+x)*4;
    if(raw.data[i+3]>3){minX=Math.min(minX,x);minY=Math.min(minY,y);maxX=Math.max(maxX,x);maxY=Math.max(maxY,y);}
    // Generated transparent pixels retain hidden RGB. Clear only alpha-zero RGB
    // to prevent accidental color leakage in later texture packing.
    if(raw.data[i+3]===0){raw.data[i]=0;raw.data[i+1]=0;raw.data[i+2]=0;}
  }
  if(maxX<minX)throw Error('Empty part '+spec.id);
  const bounds={left:Math.max(0,minX-2),top:Math.max(0,minY-2),width:Math.min(width,maxX+3)-Math.max(0,minX-2),height:Math.min(height,maxY+3)-Math.max(0,minY-2)};
  const file='layers/'+spec.id+'.png';
  await sharp(raw.data,{raw:{width,height,channels:4}}).extract(bounds).png().toFile(path.join(out,file));
  const {region,...rest}=spec;
  layers.push({...rest,file,sha256:crypto.createHash('sha256').update(await fs.readFile(path.join(out,file))).digest('hex'),sourceCrop:{x:left+bounds.left,y:top+bounds.top,width:bounds.width,height:bounds.height}});
}
const manifest={schemaVersion:1,characterId:'watercolor-duck',referenceVersion:'duck-v1-nostrils',masterVersion:'duck-master-v1.0',status:'pilot-source-accepted',canvas:{width:512,height:512},groundPivot:{x:256,y:448},standingHeightApproxPx:360,reference:{path:path.relative(out,refPath),sha256:crypto.createHash('sha256').update(await fs.readFile(refPath)).digest('hex'),neutralPoseLabel:'01'},sourceBoard:{path:path.relative(out,boardPath),sha256:crypto.createHash('sha256').update(await fs.readFile(boardPath)).digest('hex')},groupPivots:{head:{x:256,y:309}},anchors:{head:{x:256,y:309},bubble:{x:348,y:122},wingLeft:{x:227,y:345},wingRight:{x:285,y:345},propCenter:{x:256,y:366},eyeCenter:{x:256,y:214}},layers,animation:{frameRate:{numerator:12,denominator:1},style:'Noodly elastic body/wing follow-through; fixed rigid bill/head identity'},limitations:['Layer board was carefully repainted by imagegen from approved reference, not a pixel-exact extraction of concept pose01.','Head includes bill contour and both nostrils as immutable paint; eyes are separate approved open/closed overlays.','Large torso turns/flight silhouette changes require separately approved drawn keys, not extreme cutout rotation.','Canvas and layer pivots are exact technical registration; anatomical proportions still require human visual acceptance.']};
await fs.writeFile(path.join(out,'master.json'),JSON.stringify(manifest,null,2)+'\n');
const master=await loadMaster(path.join(out,'master.json'));
await renderPose({master,output:path.join(out,'neutral.png')});
await renderPose({master,eyeState:'closed',output:path.join(out,'neutral-closed-eyes.png')});
await sharp(path.join(out,'neutral.png')).resize(1024,1024).png().toFile(path.join(out,'neutral@2x.png'));
// Preview composites are technical transparency checks, not source artwork.
for(const [name,color]of [['white','#ffffff'],['charcoal','#25252a']]){
  await sharp(path.join(out,'neutral.png')).flatten({background:color}).png().toFile(path.join(out,'preview-'+name+'.png'));
}
console.log(JSON.stringify({manifest:path.join(out,'master.json'),neutral:path.join(out,'neutral.png'),layers:layers.length},null,2));
