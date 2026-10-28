import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { setTimeout as delay, setImmediate as turn } from 'node:timers/promises';

import { MAX_BYTES, MAX_CHUNKS, observeBytes } from './observation.mjs';

const base = {
  eligible: false,
  generationVerified: false,
  scanner: 'not_run',
};
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const bytes = (...values) => Uint8Array.from(values);
const never = () => new Promise(() => {});

function failure(actual, outcome) {
  assert.deepEqual(actual, { outcome, ...base });
  assert.equal(Object.isFrozen(actual), true);
  assert.deepEqual(Reflect.ownKeys(actual).sort(), [
    'eligible', 'generationVerified', 'outcome', 'scanner',
  ]);
}

function observed(actual, original) {
  assert.deepEqual(actual, {
    outcome: 'observed',
    ...base,
    byteLength: original.byteLength,
    sha256: sha256(original),
  });
  assert.equal(Object.isFrozen(actual), true);
}

// Custom iterators make next/return/abort observable, including after done.
function tracked(chunks = [bytes(97, 98, 99)], options = {}) {
  const state = {
    calls: 0,
    nextCalls: 0,
    returns: 0,
    aborts: 0,
    signal: undefined,
  };
  const source = (signal) => {
    ++state.calls;
    state.signal = signal;
    signal.addEventListener('abort', () => ++state.aborts, { once: true });
    return {
      [Symbol.asyncIterator]() { return this; },
      next() {
        const index = state.nextCalls++;
        return options.next
          ? options.next(index, signal)
          : Promise.resolve(index < chunks.length
            ? { done: false, value: chunks[index] }
            : { done: true });
      },
      return() {
        ++state.returns;
        return options.cleanup ? options.cleanup() : Promise.resolve({ done: true });
      },
    };
  };
  return { source, state };
}

function cleaned(state) {
  assert.equal(state.signal instanceof AbortSignal, true);
  assert.equal(state.signal.aborted, true);
  assert.equal(state.aborts, 1);
  assert.equal(state.returns, 1);
}

function spin(milliseconds) {
  const until = performance.now() + milliseconds;
  while (performance.now() < until) { /* Exercise a blocked timer queue. */ }
}

test('exports operational byte and chunk limits', () => {
  assert.equal(MAX_BYTES, 20 * 1024 * 1024);
  assert.equal(MAX_CHUNKS, 65536);
});

test('option getters are rejected without invocation or source calls', async () => {
  let calls = 0;
  const input = { source() { ++calls; }, expectedByteLength: 1 };
  Object.defineProperty(input, 'timeoutMs', { get() { ++calls; throw new Error('PRIVATE_GETTER'); } });
  failure(await observeBytes(input), 'invalid_input');
  assert.equal(calls, 0);
});

test('null-prototype option data is accepted', async () => {
  const { source } = tracked([bytes(65)]);
  observed(await observeBytes(Object.assign(Object.create(null), {
    source, expectedByteLength: 1,
  })), bytes(65));
});

for (const backing of [new SharedArrayBuffer(1), new ArrayBuffer(1, { maxByteLength: 2 })]) {
  test(`mutable backing store ${backing.constructor.name} is rejected`, async () => {
    const { source, state } = tracked([new Uint8Array(backing)]);
    failure(await observeBytes({ source, expectedByteLength: 1 }), 'unsupported_chunk');
    cleaned(state);
  });
}

test('complete abc has the independently known SHA-256 and no acceptance claims', async () => {
  const { source, state } = tracked([bytes(97), bytes(98, 99)]);
  const result = await observeBytes({ source, expectedByteLength: 3 });
  observed(result, bytes(97, 98, 99));
  assert.equal(result.sha256, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  cleaned(state);
});

test('arbitrary malformed PDF/TXT bytes are observed without format/scanner validation', async () => {
  const original = bytes(0, 255, 37, 80, 68, 70, 45, 0);
  const { source, state } = tracked([original]);
  observed(await observeBytes({ source, expectedByteLength: original.length }), original);
  cleaned(state);
});

test('hash uses complete original bytes including CR/LF and BOM without normalization', async () => {
  const original = bytes(239, 187, 191, 65, 13, 10, 66, 10);
  const { source } = tracked([original.subarray(0, 4), original.subarray(4)]);
  observed(await observeBytes({ source, expectedByteLength: original.length }), original);
});

test('hash respects Uint8Array view boundaries', async () => {
  const backing = bytes(255, 97, 98, 99, 254);
  const { source } = tracked([backing.subarray(1, 4)]);
  observed(await observeBytes({ source, expectedByteLength: 3 }), bytes(97, 98, 99));
});

test('reused mutable chunks are snapshotted before the next producer call', async () => {
  const chunk = bytes(97);
  const { source, state } = tracked([], {
    next(index) {
      if (index === 0) return Promise.resolve({ done: false, value: chunk });
      if (index === 1) {
        chunk[0] = 98;
        return Promise.resolve({ done: false, value: chunk });
      }
      chunk[0] = 255;
      return Promise.resolve({ done: true });
    },
  });
  observed(await observeBytes({ source, expectedByteLength: 2 }), bytes(97, 98));
  cleaned(state);
});

test('Buffer chunks are Uint8Array and preserve their exact bytes', async () => {
  const original = Buffer.from('in-memory synthetic fixture\n');
  const { source } = tracked([original]);
  observed(await observeBytes({ source, expectedByteLength: original.length }), original);
});

test('configured exact byte boundary succeeds', async () => {
  const { source, state } = tracked([bytes(1, 2), bytes(3, 4)]);
  observed(await observeBytes({ source, expectedByteLength: 4, maxBytes: 4 }), bytes(1, 2, 3, 4));
  cleaned(state);
});

test('full MAX_BYTES boundary succeeds', async () => {
  const original = new Uint8Array(MAX_BYTES).fill(65);
  const { source, state } = tracked([original]);
  observed(await observeBytes({ source, expectedByteLength: MAX_BYTES }), original);
  cleaned(state);
});

test('single overflowing chunk is too_large with no partial observation', async () => {
  const { source, state } = tracked([bytes(1, 2, 3, 4, 5)]);
  failure(await observeBytes({ source, expectedByteLength: 4, maxBytes: 4 }), 'too_large');
  cleaned(state);
});

test('cumulative overflow is too_large and stops reading', async () => {
  const { source, state } = tracked([bytes(1, 2, 3), bytes(4, 5), bytes(6)]);
  failure(await observeBytes({ source, expectedByteLength: 4, maxBytes: 4 }), 'too_large');
  assert.equal(state.nextCalls, 2);
  cleaned(state);
});

for (const [label, chunks, expected] of [
  ['truncation', [bytes(1, 2)], 3],
  ['extra bytes below maximum', [bytes(1, 2, 3)], 2],
  ['zero bytes', [], 1],
  ['empty chunks then EOF', [bytes(), bytes()], 1],
]) {
  test(`${label} is size_mismatch without a digest`, async () => {
    const { source, state } = tracked(chunks);
    failure(await observeBytes({ source, expectedByteLength: expected }), 'size_mismatch');
    cleaned(state);
  });
}

const invalidCases = [
  ['null input', () => null],
  ['missing input', () => undefined],
  ['array input', () => []],
  ['missing source', () => ({ expectedByteLength: 1 })],
  ['nonfactory source', () => ({ source: {}, expectedByteLength: 1 })],
  ['missing expected length', (source) => ({ source })],
  ...[0, -1, 1.5, NaN, Infinity, '1', null, MAX_BYTES + 1].map((value) => [
    `expectedByteLength ${String(value)}`,
    (source) => ({ source, expectedByteLength: value }),
  ]),
  ...[0, -1, 1.5, NaN, Infinity, '20', null, 20001].map((value) => [
    `timeoutMs ${String(value)}`,
    (source) => ({ source, expectedByteLength: 1, timeoutMs: value }),
  ]),
  ...[0, -1, 1.5, NaN, Infinity, '1', null, MAX_BYTES + 1].map((value) => [
    `maxBytes ${String(value)}`,
    (source) => ({ source, expectedByteLength: 1, maxBytes: value }),
  ]),
  ['length greater than configured cap', (source) => ({ source, expectedByteLength: 2, maxBytes: 1 })],
  ['unknown field', (source) => ({ source, expectedByteLength: 1, clean: true })],
  ['unknown symbol field', (source) => ({ source, expectedByteLength: 1, [Symbol('private')]: true })],
  ['unknown nonenumerable field', (source) => Object.defineProperty(
    { source, expectedByteLength: 1 }, 'private', { value: true },
  )],
  ['invalid signal', (source) => ({ source, expectedByteLength: 1, signal: {} })],
  ['null signal', (source) => ({ source, expectedByteLength: 1, signal: null })],
];

for (const [label, input] of invalidCases) {
  test(`invalid input: ${label} is rejected before source factory`, async () => {
    let calls = 0;
    const source = () => { ++calls; throw new Error('PRIVATE_FACTORY'); };
    failure(await observeBytes(input(source)), 'invalid_input');
    assert.equal(calls, 0);
  });
}

test('already aborted caller cancels before factory and hides abort reason', async () => {
  const controller = new AbortController();
  controller.abort(new Error('PRIVATE_ABORT_REASON'));
  const { source, state } = tracked();
  failure(await observeBytes({ source, expectedByteLength: 3, signal: controller.signal }), 'cancelled');
  assert.equal(state.calls, 0);
});

test('factory gets internal signal and success never aborts caller-owned signal', async () => {
  const controller = new AbortController();
  const { source, state } = tracked();
  observed(await observeBytes({ source, expectedByteLength: 3, signal: controller.signal }), bytes(97, 98, 99));
  assert.notEqual(state.signal, controller.signal);
  assert.equal(controller.signal.aborted, false);
  cleaned(state);
});

for (const value of ['private text', [1], new ArrayBuffer(1), new Uint16Array([1]), null, undefined]) {
  test(`unsupported chunk ${Object.prototype.toString.call(value)} is sanitized`, async () => {
    const { source, state } = tracked([value]);
    failure(await observeBytes({ source, expectedByteLength: 1 }), 'unsupported_chunk');
    cleaned(state);
  });
}

test('MAX_CHUNKS including empty chunks is permitted exactly', async () => {
  const { source, state } = tracked([], {
    next(index) {
      return Promise.resolve(index === MAX_CHUNKS
        ? { done: true }
        : { done: false, value: index === MAX_CHUNKS - 1 ? bytes(65) : bytes() });
    },
  });
  observed(await observeBytes({ source, expectedByteLength: 1 }), bytes(65));
  cleaned(state);
});

test('endless immediately available empty chunks hit chunk_limit', async () => {
  const { source, state } = tracked([], {
    next: () => Promise.resolve({ done: false, value: bytes() }),
  });
  failure(await observeBytes({ source, expectedByteLength: 1 }), 'chunk_limit');
  assert.ok(state.nextCalls <= MAX_CHUNKS + 1);
  cleaned(state);
});

for (const empty of [false, true]) {
  test(`${empty ? 'empty' : 'nonempty'} dribbling chunks cannot extend absolute timeout`, async () => {
    const { source, state } = tracked([], {
      next: async () => {
        await delay(8);
        return { done: false, value: empty ? bytes() : bytes(65) };
      },
    });
    failure(await observeBytes({ source, expectedByteLength: MAX_BYTES, timeoutMs: 100 }), 'timeout');
    cleaned(state);
    await delay(12); // Observe an in-flight late next() resolution.
  });
}

test('stalled next times out even if return cleanup never settles', { timeout: 5000 }, async () => {
  const { source, state } = tracked([], { next: never, cleanup: never });
  failure(await observeBytes({ source, expectedByteLength: 1, timeoutMs: 40 }), 'timeout');
  cleaned(state);
});

test('caller abort during stalled read does not await dangling return cleanup', { timeout: 5000 }, async () => {
  const controller = new AbortController();
  const { source, state } = tracked([], { next: never, cleanup: never });
  const observing = observeBytes({ source, expectedByteLength: 1, signal: controller.signal });
  await turn();
  controller.abort('PRIVATE_REASON');
  failure(await observing, 'cancelled');
  cleaned(state);
});

test('yield during immediately resolving empty chunks lets caller cancellation run', async () => {
  const controller = new AbortController();
  const { source, state } = tracked([], {
    next: () => Promise.resolve({ done: false, value: bytes() }),
  });
  const cancelling = turn().then(() => controller.abort());
  failure(await observeBytes({ source, expectedByteLength: 1, signal: controller.signal }), 'cancelled');
  await cancelling;
  assert.ok(state.nextCalls < MAX_CHUNKS);
  cleaned(state);
});

test('performance deadline rejects synchronous next even before timer can fire', async () => {
  const { source, state } = tracked([], {
    next() {
      spin(15);
      return Promise.resolve({ done: false, value: bytes(65) });
    },
  });
  failure(await observeBytes({ source, expectedByteLength: 1, timeoutMs: 1 }), 'timeout');
  cleaned(state);
});

test('source throw after partial bytes exposes neither private error nor partial digest', async () => {
  const { source, state } = tracked([], {
    next(index) {
      if (index === 0) return Promise.resolve({ done: false, value: bytes(65) });
      return Promise.reject(new Error('PRIVATE_TOKEN_PATH_BODY'));
    },
  });
  failure(await observeBytes({ source, expectedByteLength: 2 }), 'source_error');
  cleaned(state);
});

test('synchronous source factory errors are safe source_error results', async () => {
  let internal;
  failure(await observeBytes({
    expectedByteLength: 1,
    source(signal) { internal = signal; throw new Error('PRIVATE_FACTORY_ERROR'); },
  }), 'source_error');
  assert.equal(internal.aborted, true);
});

for (const value of [null, {}, { [Symbol.asyncIterator]: () => ({}) }]) {
  test(`malformed iterable ${value === null ? 'null' : Reflect.ownKeys(value).length} fails safely`, async () => {
    let internal;
    failure(await observeBytes({
      expectedByteLength: 1,
      source(signal) { internal = signal; return value; },
    }), 'source_error');
    assert.equal(internal.aborted, true);
  });
}

for (const cleanup of [
  () => { throw new Error('PRIVATE_SYNC_CLEANUP'); },
  () => Promise.reject(new Error('PRIVATE_ASYNC_CLEANUP')),
  never,
]) {
  test(`successful observation is not held or contaminated by ${cleanup.name || 'failing'} cleanup`, { timeout: 5000 }, async () => {
    const { source, state } = tracked([bytes(65)], { cleanup });
    observed(await observeBytes({ source, expectedByteLength: 1 }), bytes(65));
    cleaned(state);
    await turn();
    await turn();
  });
}

test('late rejected next after timeout is observed without an unhandled rejection', async () => {
  let rejectNext;
  const { source, state } = tracked([], {
    next: () => new Promise((_, reject) => { rejectNext = reject; }),
    cleanup: () => Promise.reject(new Error('PRIVATE_LATE_CLEANUP')),
  });
  failure(await observeBytes({ source, expectedByteLength: 1, timeoutMs: 40 }), 'timeout');
  cleaned(state);
  rejectNext(new Error('PRIVATE_LATE_NEXT'));
  await turn();
  await turn();
});

for (const cancelled of [false, true]) {
  test(`throwing return getter preserves safe ${cancelled ? 'cancelled' : 'observed'} result`, { timeout: 5000 }, async () => {
    const controller = new AbortController();
    const fixture = tracked([bytes(65)], cancelled ? { next: never } : {});
    let lookups = 0;
    const source = (signal) => {
      const iterator = fixture.source(signal);
      Object.defineProperty(iterator, 'return', {
        get() {
          ++lookups;
          throw new Error('PRIVATE_RETURN_GETTER_TOKEN_PATH_BODY');
        },
      });
      return iterator;
    };
    const observing = observeBytes({ source, expectedByteLength: 1, signal: controller.signal });
    if (cancelled) {
      await turn();
      assert.equal(fixture.state.nextCalls, 1);
      controller.abort('PRIVATE_ABORT_REASON');
      failure(await observing, 'cancelled');
    } else {
      observed(await observing, bytes(65));
      assert.equal(controller.signal.aborted, false);
    }
    assert.equal(lookups, 1);
    assert.equal(fixture.state.returns, 0);
    assert.equal(fixture.state.signal.aborted, true);
    assert.equal(fixture.state.aborts, 1);
    await turn();
    await turn();
  });
}

test('later independent observation works after cancelled source cleanup remains pending', async () => {
  const stalled = tracked([], { next: never, cleanup: never });
  failure(await observeBytes({ source: stalled.source, expectedByteLength: 1, timeoutMs: 40 }), 'timeout');
  const fresh = tracked([bytes(66)]);
  observed(await observeBytes({ source: fresh.source, expectedByteLength: 1 }), bytes(66));
  cleaned(stalled.state);
  cleaned(fresh.state);
});

const malformedSteps = [
  ['null', null],
  ['undefined', undefined],
  ['number', 7],
  ['string', 'PRIVATE_STEP_BODY'],
  ['array without done', []],
  ['missing done', { value: bytes(65) }],
  ['undefined done', { done: undefined, value: bytes(65) }],
  ['null done', { done: null, value: bytes(65) }],
  ['numeric done', { done: 0, value: bytes(65) }],
  ['string done', { done: 'false', value: bytes(65) }],
  ['boxed boolean done', { done: new Boolean(false), value: bytes(65) }],
];

for (const afterPartial of [false, true]) {
  for (const [label, step] of malformedSteps) {
    test(`malformed ${label} step ${afterPartial ? 'after partial bytes' : 'on first pull'} is sanitized without another pull`, async () => {
      const { source, state } = tracked([], {
        next(index) {
          if (afterPartial && index === 0) return Promise.resolve({ done: false, value: bytes(65) });
          return Promise.resolve(step);
        },
      });
      failure(await observeBytes({ source, expectedByteLength: 2 }), 'source_error');
      const pulls = afterPartial ? 2 : 1;
      assert.equal(state.nextCalls, pulls);
      cleaned(state);
      await turn();
      assert.equal(state.nextCalls, pulls);
    });
  }
}

for (const throwOn of [1, 2]) {
  test(`throwing asyncIterator getter on lookup ${throwOn} returns safe source_error`, async () => {
    let internal, lookups = 0, acquisitions = 0, pulls = 0;
    const source = (signal) => {
      internal = signal;
      return Object.defineProperty({}, Symbol.asyncIterator, {
        get() {
          if (++lookups === throwOn) throw new Error('PRIVATE_ASYNC_ITERATOR_GETTER');
          return () => {
            ++acquisitions;
            return { next() { ++pulls; return never(); } };
          };
        },
      });
    };
    failure(await observeBytes({ source, expectedByteLength: 1 }), 'source_error');
    assert.equal(lookups, throwOn);
    assert.equal(acquisitions, 0);
    assert.equal(pulls, 0);
    assert.equal(internal.aborted, true);
  });
}

for (const throwOn of [1, 2, 3]) {
  test(`throwing next getter on lookup ${throwOn} is sanitized and closes acquired iterator`, async () => {
    const fixture = tracked([bytes(65)]);
    let lookups = 0;
    const source = (signal) => {
      const iterator = fixture.source(signal);
      const pull = iterator.next;
      Object.defineProperty(iterator, 'next', {
        get() {
          if (++lookups === throwOn) throw new Error('PRIVATE_NEXT_GETTER');
          return pull;
        },
      });
      return iterator;
    };
    failure(await observeBytes({ source, expectedByteLength: 2 }), 'source_error');
    assert.equal(lookups, throwOn);
    assert.equal(fixture.state.nextCalls, throwOn === 3 ? 1 : 0);
    cleaned(fixture.state);
  });
}

for (const property of ['done', 'value']) {
  for (const afterPartial of [false, true]) {
    test(`throwing step ${property} getter ${afterPartial ? 'after partial bytes' : 'on first pull'} exposes no details or digest`, async () => {
      let lookups = 0;
      const step = Object.defineProperty({ done: false }, property, {
        get() {
          ++lookups;
          throw new Error('PRIVATE_STEP_GETTER_BODY_PATH');
        },
      });
      const fixture = tracked([], {
        next(index) {
          if (afterPartial && index === 0) return Promise.resolve({ done: false, value: bytes(65) });
          return Promise.resolve(step);
        },
      });
      failure(await observeBytes({ source: fixture.source, expectedByteLength: 2 }), 'source_error');
      assert.equal(lookups, 1);
      assert.equal(fixture.state.nextCalls, afterPartial ? 2 : 1);
      cleaned(fixture.state);
    });
  }
}

test('done EOF does not evaluate an irrelevant throwing value getter', async () => {
  let lookups = 0;
  const eof = Object.defineProperty({ done: true }, 'value', {
    get() { ++lookups; throw new Error('PRIVATE_UNUSED_EOF_VALUE'); },
  });
  const fixture = tracked([], {
    next: (index) => Promise.resolve(index === 0 ? { done: false, value: bytes(65) } : eof),
  });
  observed(await observeBytes({ source: fixture.source, expectedByteLength: 1 }), bytes(65));
  assert.equal(lookups, 0);
  cleaned(fixture.state);
});

for (const throws of [false, true]) {
  test(`caller abort inside source factory ${throws ? 'followed by throw' : 'before iterable return'} prevents iterator acquisition and all pulls`, async () => {
    const caller = new AbortController();
    let internal, calls = 0, acquisitions = 0, pulls = 0;
    const source = (signal) => {
      ++calls;
      internal = signal;
      caller.abort('PRIVATE_FACTORY_ABORT');
      if (throws) throw new Error('PRIVATE_FACTORY_AFTER_ABORT');
      return {
        [Symbol.asyncIterator]() {
          ++acquisitions;
          return { next() { ++pulls; return never(); } };
        },
      };
    };
    failure(await observeBytes({ source, expectedByteLength: 1, signal: caller.signal }), 'cancelled');
    assert.equal(calls, 1);
    assert.equal(acquisitions, 0);
    assert.equal(pulls, 0);
    assert.equal(internal.aborted, true);
    await turn();
    assert.equal(pulls, 0);
  });
}

test('factory-scheduled caller abort before first pull closes acquired iterator without pulling', async () => {
  const caller = new AbortController();
  const fixture = tracked();
  const source = (signal) => {
    const iterator = fixture.source(signal);
    queueMicrotask(() => caller.abort('PRIVATE_FACTORY_MICROTASK_ABORT'));
    return iterator;
  };
  failure(await observeBytes({ source, expectedByteLength: 3, signal: caller.signal }), 'cancelled');
  assert.equal(fixture.state.nextCalls, 0);
  cleaned(fixture.state);
  await turn();
  assert.equal(fixture.state.nextCalls, 0);
});

test('caller abort within first next prevents a second pull or observed result', async () => {
  const caller = new AbortController();
  const fixture = tracked([], {
    next() {
      caller.abort('PRIVATE_PULL_ABORT');
      return Promise.resolve({ done: false, value: bytes(65) });
    },
  });
  failure(await observeBytes({ source: fixture.source, expectedByteLength: 1, signal: caller.signal }), 'cancelled');
  assert.equal(fixture.state.nextCalls, 1);
  cleaned(fixture.state);
  await turn();
  assert.equal(fixture.state.nextCalls, 1);
});

for (const rejects of [false, true]) {
  test(`late next ${rejects ? 'rejection' : 'resolution'} after caller abort is observed without another pull`, async () => {
    const caller = new AbortController();
    let settle;
    const fixture = tracked([], {
      next: () => new Promise((resolve, reject) => { settle = rejects ? reject : resolve; }),
    });
    const observing = observeBytes({ source: fixture.source, expectedByteLength: 1, signal: caller.signal });
    await turn();
    assert.equal(fixture.state.nextCalls, 1);
    caller.abort('PRIVATE_EXTERNAL_ABORT');
    failure(await observing, 'cancelled');
    cleaned(fixture.state);
    settle(rejects ? new Error('PRIVATE_LATE_NEXT_ERROR') : { done: false, value: bytes(65) });
    await turn();
    await turn();
    assert.equal(fixture.state.nextCalls, 1);
  });
}

test('caller abort from next lookup prevents calling the returned pull function', async () => {
  const caller = new AbortController();
  const fixture = tracked([bytes(65)]);
  let lookups = 0;
  const source = (signal) => {
    const iterator = fixture.source(signal);
    const pull = iterator.next;
    Object.defineProperty(iterator, 'next', {
      get() {
        if (++lookups === 2) caller.abort('PRIVATE_NEXT_LOOKUP_ABORT');
        return pull;
      },
    });
    return iterator;
  };
  failure(await observeBytes({ source, expectedByteLength: 1, signal: caller.signal }), 'cancelled');
  assert.equal(fixture.state.nextCalls, 0, 'pull function must not run after its getter synchronously aborts the caller');
  cleaned(fixture.state);
  await turn();
  assert.equal(fixture.state.nextCalls, 0);
});
