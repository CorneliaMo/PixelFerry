'use strict';

const PROFILE_ORDER = ['constrained', 'motion', 'balanced', 'detail'];
const CAPTURE_SWITCH_INTERVAL_MS = 10_000;
const PROFILE_FACTORS = Object.freeze({
  detail: { bitrate: 1, scale: 1 },
  balanced: { bitrate: 0.7, scale: 1 },
  motion: { bitrate: 0.6, scale: 0.75 },
  constrained: { bitrate: 0.35, fpsCap: 30, scale: 0.5 },
});

function profileSettings(name, baseBitrateBps, baseFps) {
  const factor = PROFILE_FACTORS[name];
  if (!factor) throw new Error(`Unknown quality profile: ${name}`);
  return {
    profile: name,
    scale: factor.scale,
    maxBitrateBps: Math.max(100_000, Math.round(baseBitrateBps * factor.bitrate)),
    maxFps: Math.max(1, Math.min(baseFps, factor.fpsCap || baseFps)),
  };
}

module.exports = { CAPTURE_SWITCH_INTERVAL_MS, PROFILE_ORDER, PROFILE_FACTORS, profileSettings };
