'use strict';

class QualityTransitionCoordinator {
  constructor(apply, options = {}) {
    this.apply = apply;
    this.onError = options.onError || console.error;
    this.now = options.now || (() => performance.now());
    this.wait = options.wait || ((milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)));
    this.minimumScaleIntervalMs = options.minimumScaleIntervalMs ?? 10_000;
    this.currentScale = options.initialScale ?? 1;
    this.lastScaleChangeAt = -Infinity;
    this.latestSequence = -1;
    this.pending = undefined;
    this.running = false;
    this.generation = 0;
    this.wakeWaiting = undefined;
  }

  enqueue(value) {
    if (Number.isSafeInteger(value.sequence)) {
      if (value.sequence <= this.latestSequence) return false;
      this.latestSequence = value.sequence;
    }
    this.pending = value;
    this.wakeWaiting?.();
    if (!this.running) void this.drain(this.generation);
    return true;
  }

  reset(scale = this.currentScale) {
    this.pending = undefined;
    this.generation += 1;
    this.latestSequence = -1;
    this.currentScale = scale;
    this.wakeWaiting?.();
  }

  async drain(generation) {
    this.running = true;
    while (generation === this.generation && this.pending !== undefined) {
      const value = this.pending;
      this.pending = undefined;
      const isStale = () => generation !== this.generation || this.pending !== undefined;
      try {
        const changesScale = value.scale !== undefined && value.scale !== this.currentScale;
        if (changesScale) {
          const remaining = this.minimumScaleIntervalMs - (this.now() - this.lastScaleChangeAt);
          if (remaining > 0) {
            await Promise.race([
              this.wait(remaining),
              new Promise((resolve) => { this.wakeWaiting = resolve; }),
            ]);
            this.wakeWaiting = undefined;
          }
        }
        if (isStale()) continue;
        const result = await this.apply(value, isStale);
        const appliedScale = result?.appliedScale;
        if (appliedScale !== undefined && appliedScale !== this.currentScale) {
          this.currentScale = appliedScale;
          this.lastScaleChangeAt = this.now();
        }
      } catch (error) { this.onError(error); }
    }
    this.running = false;
    if (this.pending !== undefined) void this.drain(this.generation);
  }
}

module.exports = { QualityTransitionCoordinator };
