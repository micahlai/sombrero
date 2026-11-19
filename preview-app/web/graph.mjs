import {evaluateGuard} from './engine.mjs';
const NS = 'http://www.w3.org/2000/svg';
const COLORS = {default:'#91a7b9',interrupt:'#e27480',afterClip:'#bb9ce7',recall:'#6fb3a2',active:'#82c7ff'};
const LAYOUT = {
  '1a':[80,135], '1b':[350,135], '1c':[80,260], '1d':[350,260],
  '2a':[80,455], '2b':[350,455], '3a':[80,575], '3b':[350,575], '3c':[215,690],
  '4a':[50,890], timeout:[235,890], '4b':[420,890],
  '5a':[690,135], '5b':[960,135], '5c':[960,245], '5d':[690,245],
  '6a':[690,435], '6b':[960,435], '6c':[825,550],
  '7a':[690,735], '7b':[960,735], '7c':[825,850],
};
const SECTIONS = [
  [30,60,550,310,'Standing'],[30,405,550,385,'Sitting'],[30,825,550,180,'Away'],
  [650,60,550,285,'Photo'],[650,365,550,285,'Camera'],[650,675,550,285,'Bible'],
];
function element(name, attributes = {}, text) {
  const node = document.createElementNS(NS, name);
  for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, value);
  if (text !== undefined) node.textContent = text;
  return node;
}
const pct = n => `${(n * 100).toFixed(n < .01 ? 2 : 1).replace(/\.0$/, '')}%`;

export class GraphView {
  constructor(svg, viewport, graph, onSelect) {
    this.svg = svg; this.viewport = viewport; this.graph = graph; this.onSelect = onSelect;
    this.tooltip = document.querySelector('#graph-tooltip');
    this.zoomLabel = document.querySelector('#zoom-level');
    this.base = {x:0,y:0,width:1240,height:1030}; this.camera = {...this.base};
    this.nodes = new Map(); this.paths = new Map(); this.captions = new Map(); this.edges = [];
    this.filter = 'all'; this.drag = null;
    this.build();
    this.abort = new AbortController(); const options = {signal:this.abort.signal};
    svg.addEventListener('wheel', event => {
      event.preventDefault();
      this.zoom(event.deltaY > 0 ? 1.12 : 1 / 1.12, this.svgPoint(event.clientX, event.clientY));
    }, {...options, passive:false});
    svg.addEventListener('pointerdown', event => {
      if (event.button !== 0 || event.target.closest('.graph-node')) return;
      this.drag = {x:event.clientX,y:event.clientY,camera:{...this.camera}};
      svg.setPointerCapture(event.pointerId); svg.classList.add('dragging'); this.tooltip.hidden = true;
    }, options);
    svg.addEventListener('pointermove', event => {
      if (!this.drag) return;
      const inverse = svg.getScreenCTM().inverse();
      const first = new DOMPoint(this.drag.x, this.drag.y).matrixTransform(inverse);
      const next = new DOMPoint(event.clientX, event.clientY).matrixTransform(inverse);
      this.camera.x = this.drag.camera.x + first.x - next.x;
      this.camera.y = this.drag.camera.y + first.y - next.y;
      this.applyCamera();
    }, options);
    const stop = () => { this.drag = null; svg.classList.remove('dragging'); };
    svg.addEventListener('pointerup', stop, options); svg.addEventListener('pointercancel', stop, options);
    svg.addEventListener('pointerleave', () => { this.tooltip.hidden = true; }, options);
    this.applyCamera();
  }

  destroy() { this.abort.abort(); this.tooltip.hidden = true; }
  svgPoint(x,y) { return new DOMPoint(x,y).matrixTransform(this.svg.getScreenCTM().inverse()); }
  applyCamera() {
    const {x,y,width,height} = this.camera;
    this.svg.setAttribute('viewBox', `${x} ${y} ${width} ${height}`);
    this.zoomLabel.textContent = `${Math.round(this.base.width / width * 100)}%`;
  }
  fit() { this.camera = {...this.base}; this.applyCamera(); }
  zoom(factor, point = {x:this.camera.x + this.camera.width / 2,y:this.camera.y + this.camera.height / 2}) {
    const width = Math.min(this.base.width * 2, Math.max(260, this.camera.width * factor));
    const effective = width / this.camera.width;
    this.camera = {x:point.x - (point.x - this.camera.x) * effective,
      y:point.y - (point.y - this.camera.y) * effective,width,height:this.camera.height * effective};
    this.applyCamera();
  }
  center(id) {
    const node = this.nodes.get(id); if (!node) return;
    this.camera = {x:node.x + node.width/2 - 330,y:node.y + 38 - 274,width:660,height:548};
    this.applyCamera();
  }

  showTooltip(event, text) {
    if (this.drag) return;
    const rect = this.viewport.getBoundingClientRect();
    this.tooltip.textContent = text;
    this.tooltip.style.left = `${Math.max(8,Math.min(rect.width - 285,event.clientX - rect.left + 12))}px`;
    this.tooltip.style.top = `${Math.max(8, Math.min(rect.height - 90,event.clientY - rect.top + 12))}px`;
    this.tooltip.hidden = false;
  }

  build() {
    this.svg.replaceChildren();
    const defs = element('defs');
    for (const [kind,color] of Object.entries(COLORS)) {
      const marker = element('marker',{id:`arrow-${kind}`,viewBox:'0 0 10 10',refX:9,refY:5,markerWidth:6,markerHeight:6,orient:'auto-start-reverse'});
      marker.append(element('path',{d:'M 0 0 L 10 5 L 0 10 z',fill:color})); defs.append(marker);
    }
    const pattern = element('pattern',{id:'grid',width:24,height:24,patternUnits:'userSpaceOnUse'});
    pattern.append(element('circle',{cx:1,cy:1,r:.8,fill:'#829aaf',opacity:.18})); defs.append(pattern);
    this.svg.append(defs, element('rect',{x:-10000,y:-10000,width:20000,height:20000,fill:'url(#grid)'}));
    for (const [x,y,width,height,title] of SECTIONS) {
      const group = element('g',{class:'graph-section'});
      group.append(element('rect',{x,y,width,height}),element('text',{x:x+18,y:y+30},title)); this.svg.append(group);
    }
    for (const [index,state] of this.graph.states.entries()) {
      const [x,y] = LAYOUT[state.id] ?? [60 + index % 4 * 280,1100 + Math.floor(index/4)*125];
      const width = ['4a','4b','timeout'].includes(state.id) ? 150 : 160;
      this.nodes.set(state.id,{x,y,width,state});
    }
    const edgeGroup = element('g'); const captionGroup = element('g');
    this.graph.transitions.forEach((edge,index) => {
      const id = `edge-${index}`; const {d,x,y} = this.route(edge,index);
      const path = element('path',{d,class:`graph-edge ${edge.kind}`,'marker-end':`url(#arrow-${edge.kind})`});
      path.addEventListener('pointermove',event => this.showTooltip(event,this.edgeDescription(edge)));
      path.addEventListener('pointerleave',() => { this.tooltip.hidden = true; });
      edgeGroup.append(path); this.paths.set(id,path);
      const text = edge.kind === 'default' ? (edge.weight === 1 ? '' : String(edge.weight)) : edge.guard;
      const caption = element('text',{x,y,class:`edge-caption ${edge.kind}`,'text-anchor':'middle'},text);
      captionGroup.append(caption); this.captions.set(id,caption); this.edges.push({...edge,id});
    });
    this.svg.append(edgeGroup,captionGroup);
    for (const [id,node] of this.nodes) {
      const {x,y,width,state} = node;
      const g = element('g',{class:`graph-node ${id==='timeout'?'timeout':''}`,transform:`translate(${x},${y})`,tabindex:0,role:'button','aria-label':`${id.toUpperCase()}: ${state.name}. Select to inspect.`});
      const title = element('title',{},`${id.toUpperCase()} · ${state.name}`);
      g.append(title,element('rect',{class:'node-box',width,height:76}),element('text',{x:12,y:25,class:'node-id'},id.toUpperCase()),element('text',{x:12,y:45,class:'node-name'},this.shortName(state.name)));
      const dot = element('circle',{cx:width-13,cy:20,r:3,class:'node-dot'});
      const missing = element('text',{x:width-24,y:24,class:'node-missing','text-anchor':'end'},'Missing');
      const count = element('text',{x:12,y:63,class:'node-count'},state.kind==='hidden'?'No sprite':'10 frames');
      const nextRoll = element('text',{x:0,y:-12,class:'node-next-roll'},'Next roll · click to clear');
      g.append(dot,missing,count,nextRoll);
      const progress = element('g',{class:'node-progress'});
      const bar = element('rect',{x:0,y:73,width:0,height:3,class:'progress-fill'});
      progress.append(element('rect',{x:0,y:73,width,height:3,class:'progress-track'}),bar); g.append(progress);
      const select = () => this.onSelect(id);
      g.addEventListener('click',select);
      g.addEventListener('keydown',event => { if (event.key==='Enter'||event.key===' ') {event.preventDefault();select();} });
      g.addEventListener('pointermove',event => {
        const clip = this.clips?.[id];
        const force=this.controller?.defaultOverride?.to===id?'\nNext roll override. Click again to clear.':this.controller?.canForceDefault(id)?'\nClick to force the next default roll. Conditions still take priority.':'';
        const status=clip?.assetStatus==='empty-folder'?'empty animation folder':clip?.assetStatus==='unreadable'?'unreadable image':'animation folder missing';
        this.showTooltip(event,`${id.toUpperCase()} · ${state.name}${clip?`\n${clip.frameCount} frames${clip.placeholder?` · ${status}; pink placeholder`:''}`:''}${force}`);
      });
      g.addEventListener('pointerleave',() => { this.tooltip.hidden = true; });
      this.svg.append(g); Object.assign(node,{g,dot,missing,count,bar});
    }
  }

  shortName(name) {
    return ({'Take photo and deliver':'Photo & deliver','Showing photo idle':'Photo idle','Goodbye standing':'Goodbye','Hidden timeout':'Hidden / timeout','Standing idle':'Idle','Standing look':'Look','Standing wave':'Wave','Standing pet':'Pet','Sitting idle':'Idle','Sitting look':'Look','Sitting pet':'Pet'})[name] ?? name;
  }
  edgeDescription(edge) {
    const type = {default:'At clip completion',interrupt:'Interrupt immediately',afterClip:'After the current clip',recall:'Recall from hidden'}[edge.kind];
    let condition = edge.guard ?? 'Always';
    if (edge.kind==='default') {
      const sum = this.graph.transitions.filter(e => e.from===edge.from&&e.kind==='default').reduce((a,e) => a+e.weight,0);
      condition = `Weight ${edge.weight}; normalized probability ${pct(edge.weight/sum)}`;
    }
    return `${edge.from.toUpperCase()} → ${edge.to.toUpperCase()}\n${type}\n${condition}`;
  }

  route(edge,index) {
    const a=this.nodes.get(edge.from), b=this.nodes.get(edge.to), ac={x:a.x+a.width/2,y:a.y+38}, bc={x:b.x+b.width/2,y:b.y+38};
    if (edge.from===edge.to) {
      const sx=a.x+a.width*.7, sy=a.y;
      return {d:`M ${sx} ${sy} C ${sx+100} ${sy-80}, ${a.x+a.width+80} ${sy+22}, ${a.x+a.width} ${sy+25}`,x:sx+65,y:sy-25};
    }
    if ((a.x<600)!==(b.x<600)) {
      const lane=604 + index%3*9;
      if (a.x<600) {
        const topLane=22+index%3*10;
        return {d:`M ${ac.x} ${a.y} C ${ac.x} ${topLane}, ${lane} ${topLane}, ${lane} ${topLane} L ${lane} ${bc.y} Q ${lane} ${bc.y} ${lane+12} ${bc.y} L ${b.x} ${bc.y}`,x:lane-7,y:(topLane+bc.y)/2};
      }
      const topLane=24+index%3*10;
      return {d:`M ${a.x} ${ac.y} L ${lane} ${ac.y} L ${lane} ${topLane} C ${lane} ${topLane}, ${bc.x} ${topLane}, ${bc.x} ${b.y}`,x:lane+10,y:ac.y-9};
    }
    if (a.x<600 && Math.abs(ac.y-bc.y)>260) {
      const lane=16+index%3*8;
      return {d:`M ${a.x} ${ac.y} C ${lane} ${ac.y}, ${lane} ${bc.y}, ${b.x} ${bc.y}`,x:lane+6,y:(ac.y+bc.y)/2};
    }
    if (Math.abs(ac.x-bc.x)>Math.abs(ac.y-bc.y)) {
      const direction=bc.x>ac.x?1:-1, sx=direction>0?a.x+a.width:a.x, ex=direction>0?b.x:b.x+b.width;
      const bend=ac.y===bc.y?(direction>0?-22:22):0;
      return {d:`M ${sx} ${ac.y} C ${sx+direction*70} ${ac.y+bend}, ${ex-direction*70} ${bc.y+bend}, ${ex} ${bc.y}`,x:(sx+ex)/2,y:(ac.y+bc.y)/2+bend-5};
    }
    const direction=bc.y>ac.y?1:-1, sy=direction>0?a.y+76:a.y, ey=direction>0?b.y:b.y+76;
    const bend=ac.x===bc.x?(direction>0?-18:18):0;
    return {d:`M ${ac.x} ${sy} C ${ac.x+bend} ${sy+direction*50}, ${bc.x+bend} ${ey-direction*50}, ${bc.x} ${ey}`,x:(ac.x+bc.x)/2+bend+20,y:(sy+ey)/2};
  }

  update(controller,clips,progress,selected) {
    this.clips=clips;this.controller=controller;
    const now=Date.now(); const recent=controller.history.filter(h => now-h.time<1600);
    const taken=new Set(recent.map(h=>h.edge)); const skipped=new Set(recent.filter(h=>h.skipped).map(h=>h.from));
    for (const [id,node] of this.nodes) {
      const clip=clips[id];
      node.g.classList.toggle('current',id===controller.state);
      node.g.classList.toggle('selected',id===selected);
      node.g.classList.toggle('recent-skip',skipped.has(id));
      node.g.classList.toggle('missing',Boolean(clip?.placeholder));
      const forceOption=controller.canForceDefault(id),forcedNext=controller.defaultOverride?.to===id;
      node.g.classList.toggle('force-option',forceOption);
      node.g.classList.toggle('forced-next',forcedNext);
      node.g.setAttribute('aria-label',`${id.toUpperCase()}: ${node.state.name}. ${forcedNext?'Next roll override. Select to clear.':forceOption?'Select to force the next default roll.':'Select to inspect.'}`);
      node.missing.style.display=clip?.placeholder?'':'none';
      node.g.setAttribute('aria-pressed',id===selected?'true':'false');
      node.dot.setAttribute('fill',clip?.placeholder?'#d784b0':'#86c2ae');
      // Inline style overrides the placeholder dot's default CSS fill.
      node.dot.style.fill=clip?.placeholder?'#d784b0':'#86c2ae';
      node.dot.style.display=node.state.kind==='hidden'?'none':'';
      const countText=node.state.kind==='hidden'?'No sprite':clip?.placeholder?`${clip.assetStatus==='unreadable'?'Unreadable':'Pink square'} · 10 frames`:`${clip?.frameCount ?? 10} frames`;
      if(node.count.textContent!==countText)node.count.textContent=countText;
      node.bar.setAttribute('width',id===controller.state?node.width*Math.min(1,progress):0);
    }
    for (const edge of this.edges) {
      const path=this.paths.get(edge.id), caption=this.captions.get(edge.id);
      const outgoing=edge.from===controller.state;
      const eligible=outgoing&&edge.kind!=='default'&&evaluateGuard(edge.guard,controller.signals)&&controller.followGraph;
      const hidden=this.filter==='current'?!outgoing:this.filter==='defaults'&&edge.kind!=='default';
      const forced=edge.kind==='default'&&controller.defaultOverride?.from===edge.from;
      path.classList.toggle('forced-route',forced&&controller.defaultOverride.to===edge.to);
      path.classList.toggle('suppressed-route',forced&&controller.defaultOverride.to!==edge.to);
      if(edge.kind==='default') {
        const label=forced?String(controller.defaultWeight(edge)):edge.weight===1?'':String(edge.weight);
        if(caption.textContent!==label)caption.textContent=label;
      }
      path.classList.toggle('outgoing',outgoing); path.classList.toggle('eligible',eligible);
      path.classList.toggle('taken',taken.has(edge.id)); path.classList.toggle('hidden-edge',hidden);
      path.setAttribute('marker-end',`url(#arrow-${taken.has(edge.id)?'active':edge.kind})`);
      caption.classList.toggle('hidden-edge',hidden||!(edge.from===selected||outgoing));
    }
  }
}
