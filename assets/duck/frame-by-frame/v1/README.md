# Individually drawn duck — idle and pet preview

Start with `previews/idle-and-pet.mp4` or open `previews/index.html`.

- Eight-second video, 96 frames, exactly 12 fps.
- Idle: 24 complete drawings, two seconds, shown twice.
- Petting: 24 complete drawings, two seconds, shown twice.
- Full-frame still-image artwork; no video-generation model, parts rig, warping, morphing, or tweening.
- Watercolor is painted directly into the drawings. Technical processing is grid slicing, one common whole-cell scale, whole-frame foot registration, and cleanup of alpha0/1 background quantization.

Appearance reference: `duck-v1-nostrils`; source reference and generated-board paths/hashes are recorded in each clip manifest. The two source boards contain 24 whole-character cells each, four columns by six rows. Original cell resolution is 256 × 256; 512 × 512 output frames are a technical enlargement and registration canvas.

Validation passes for both sequences. Distinct hashes establish that frames are not exact duplicates; they do not establish smooth acting. Small shape/pigment drift and near-matching loop seams should be judged in the actual video.

These are review candidates. Wait for the user to see the video and explicitly continue before making shoo or peeking. Older layered assets under `assets/duck/v1/` are superseded and are not included in this preview pack.
