// Clip-level source-to-world transforms. No per-frame fitting or pixel edits.
export function validateCalibration(value) {
  if (value === null || value === undefined) return null;
  const positive = n => Number.isFinite(n) && n > 0;
  if (value.schemaVersion !== 1 || !positive(value.canvas?.width) || !positive(value.canvas?.height) ||
      !value.animations || typeof value.animations !== 'object' || Array.isArray(value.animations)) {
    throw new Error('Invalid animation-scales.json: expected schemaVersion 1, canvas, and animations.');
  }
  if (value.canvas.anchor && (!Number.isFinite(value.canvas.anchor.x) || !Number.isFinite(value.canvas.anchor.y))) {
    throw new Error('Invalid shared canvas anchor in animation-scales.json.');
  }
  for (const [id,entry] of Object.entries(value.animations)) {
    if (!entry || !positive(entry.scale) || !Number.isFinite(entry.offsetX) || !Number.isFinite(entry.offsetY)) {
      throw new Error(`Invalid scale/position for ${id} in animation-scales.json.`);
    }
  }
  return value;
}

export function calibratedEntry(calibration, id) {
  const entry = calibration?.animations?.[id.toLowerCase()];
  return entry?.status === 'calibrated' ? entry : null;
}

export function framePlacement(image, clipSize, calibration, id, viewport, zoom=1) {
  const entry = calibratedEntry(calibration,id);
  if (entry) {
    const scale = Math.min((viewport.width-60)/calibration.canvas.width,
      (viewport.height-50)/calibration.canvas.height);
    const left=(viewport.width-calibration.canvas.width*scale)/2;
    const top=(viewport.height-calibration.canvas.height*scale)/2;
    const anchor=calibration.canvas.anchor??{x:calibration.canvas.width/2,y:calibration.canvas.height*.85};
    const anchorX=left+anchor.x*scale,anchorY=top+anchor.y*scale;
    return {x:anchorX+(entry.offsetX-anchor.x)*scale*zoom,
      y:anchorY+(entry.offsetY-anchor.y)*scale*zoom,
      width:image.naturalWidth*entry.scale*scale*zoom,height:image.naturalHeight*entry.scale*scale*zoom};
  }
  const scale = Math.min((viewport.width-60)/clipSize.width,(viewport.height-50)/clipSize.height);
  const width=image.naturalWidth*scale,height=image.naturalHeight*scale;
  return {x:(viewport.width-width)/2,
    y:(viewport.height-clipSize.height*scale)/2+clipSize.height*scale-height,width,height};
}
