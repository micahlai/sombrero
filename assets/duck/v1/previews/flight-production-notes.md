# Flight and edge animation handoff

Source: assets/duck/v1/source/master.json. All body frames reuse the shared watercolor layers and fixed head/face. Runtime clip timing is exactly 12 fps through integer frame holds. GIFs are review proxies whose centisecond timestamps cannot exactly represent every 1/12-second hold.

Flight root travel is intentionally separate from pose art, using a curved host-driven path and an edge clip. Peek frames are intentionally unmasked; apply the manifest edge mask and entry/exit progress in the application. The default side is left; right-side mirroring remains subject to visual validation.

The head/bill/nostrils remain a rigid group. Small torso and wing bends provide loose acting while preserving the master proportions. No independently generated character frames, external image integrations, or mouth motion are included.
