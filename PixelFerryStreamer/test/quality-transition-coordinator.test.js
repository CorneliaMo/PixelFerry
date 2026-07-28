'use strict';
const test = require('node:test'); const assert = require('node:assert/strict');
const { QualityTransitionCoordinator } = require('../src/quality-transition-coordinator');

function deferred() {
  let resolve;
  return { promise: new Promise((done) => { resolve = done; }), resolve };
}

test('rejects stale sequences and coalesces pending work to the newest request', async () => {
  const gate = deferred(); const started = []; const finished = deferred();
  const coordinator = new QualityTransitionCoordinator(async (value) => {
    started.push(value.sequence);
    if (value.sequence === 1) await gate.promise;
    if (value.sequence === 3) finished.resolve();
    return { appliedScale: value.scale };
  });
  assert.equal(coordinator.enqueue({ sequence: 1, scale: 1 }), true);
  assert.equal(coordinator.enqueue({ sequence: 1, scale: 1 }), false);
  coordinator.enqueue({ sequence: 2, scale: 1 }); coordinator.enqueue({ sequence: 3, scale: 1 });
  gate.resolve(); await finished.promise;
  assert.deepEqual(started, [1, 3]);
});

test('enforces scale-change interval while same-scale parameter updates bypass it', async () => {
  let now = 20_000; const waits = []; const applied = [];
  const coordinator = new QualityTransitionCoordinator(async (value) => {
    applied.push(value.sequence); return { appliedScale: value.scale };
  }, {
    now: () => now,
    wait: async (milliseconds) => { waits.push(milliseconds); now += milliseconds; },
    minimumScaleIntervalMs: 10_000,
  });
  coordinator.enqueue({ sequence: 1, scale: 0.75 });
  await new Promise(setImmediate);
  now += 1_000; coordinator.enqueue({ sequence: 2, scale: 0.75 });
  await new Promise(setImmediate);
  coordinator.enqueue({ sequence: 3, scale: 0.5 });
  await new Promise(setImmediate);
  assert.deepEqual(applied, [1, 2, 3]);
  assert.deepEqual(waits, [9_000]);
});

test('wakes a waiting scale transition for a newer same-scale parameter update', async () => {
  let now = 20_000; const waiting = deferred(); const applied = []; const finished = deferred();
  const coordinator = new QualityTransitionCoordinator(async (value) => {
    applied.push(value.sequence); if (value.sequence === 3) finished.resolve();
    return { appliedScale: value.scale };
  }, {
    now: () => now,
    wait: async () => waiting.promise,
    minimumScaleIntervalMs: 10_000,
  });
  coordinator.enqueue({ sequence: 1, scale: 0.75 });
  await new Promise(setImmediate);
  now += 1_000; coordinator.enqueue({ sequence: 2, scale: 0.5 });
  await new Promise(setImmediate);
  coordinator.enqueue({ sequence: 3, scale: 0.75 });
  await finished.promise;
  assert.deepEqual(applied, [1, 3]);
});

test('reset preserves the last physical scale-change interval', async () => {
  let now = 20_000; const waits = [];
  const coordinator = new QualityTransitionCoordinator(async (value) => ({ appliedScale: value.scale }), {
    now: () => now,
    wait: async (milliseconds) => { waits.push(milliseconds); now += milliseconds; },
  });
  coordinator.enqueue({ sequence: 1, scale: 0.75 });
  await new Promise(setImmediate);
  now += 1_000; coordinator.reset(0.75);
  coordinator.enqueue({ sequence: 1, scale: 0.5 });
  await new Promise(setImmediate);
  assert.deepEqual(waits, [9_000]);
});
