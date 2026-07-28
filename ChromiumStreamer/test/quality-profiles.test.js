'use strict';
const test = require('node:test'); const assert = require('node:assert/strict');
const { CAPTURE_SWITCH_INTERVAL_MS, profileSettings } = require('../src/quality-profiles');
test('keeps capture track switches at least ten seconds apart', () => assert.ok(CAPTURE_SWITCH_INTERVAL_MS >= 10_000));
test('only reduces capture resolution after bitrate-only profiles are exhausted', () => {
  assert.equal(profileSettings('detail', 100_000_000, 60).scale, 1);
  assert.equal(profileSettings('balanced', 100_000_000, 60).scale, 1);
  assert.equal(profileSettings('motion', 100_000_000, 60).scale, 0.75);
  assert.equal(profileSettings('constrained', 100_000_000, 60).scale, 0.5);
});
test('limits constrained bitrate and frame rate', () => assert.deepEqual(profileSettings('constrained', 100_000_000, 60), { profile:'constrained',scale:0.5,maxBitrateBps:35_000_000,maxFps:30 }));
test('does not halve an already-low configured frame rate', () => assert.equal(profileSettings('constrained', 100_000_000, 24).maxFps, 24));
