#!/usr/bin/env python3
"""Bundle authored final frames verbatim; registration stays clip-wide at render time."""
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / 'assets/duck/final-v1'
target = ROOT / 'Sources/PetAssets/Resources/FinalDuck'
graph = json.loads((ROOT / 'docs/sombrero-v1-state-graph.json').read_text())
scales = json.loads((source / 'animation-scales.json').read_text())

def natural(path):
    return [int(p) if p.isdigit() else p.lower() for p in re.split(r'(\d+)', path.name)]

def bundle(folder):
    files = sorted(folder.glob('*.png'), key=natural)
    result = []
    for frame in files:
        destination = target / folder.name / frame.name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(frame, destination)
        result.append({'resource': f'{folder.name}/{frame.name}'})
    return result

# Validate inputs before replacing the generated resource directory.
assert len(list((source / 'speech_small').glob('*.png'))) == 5, 'Expected five speech drawings'
for state in graph['states']:
    if state['kind'] == 'hidden':
        continue
    frames = list((source / state['id']).glob('*.png'))
    if frames:
        assert scales['animations'][state['id']]['status'] == 'calibrated', state['id']
if target.exists():
    shutil.rmtree(target)
target.mkdir(parents=True)
manifest = {'schemaVersion': 2, 'drawingFPS': graph['cadence']['drawingFPS'],
            'canvasWidth': scales['canvas']['width'], 'canvasHeight': scales['canvas']['height'], 'clips': []}
for state in graph['states']:
    if state['kind'] == 'hidden':
        continue
    key = state['id']
    calibration = scales['animations'][key]
    frames = bundle(source / key)
    manifest['clips'].append({'state': key, 'frames': frames, **{
        k: calibration[k] for k in ('scale', 'offsetX', 'offsetY')}})
    print(f'{key}: {len(frames)} drawings' if frames else f'{key}: pink placeholder (10 drawing holds)')
manifest['speechFrames'] = bundle(source / 'speech_small')
(target / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
