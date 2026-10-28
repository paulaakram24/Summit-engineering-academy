// OFFLINE PROTOTYPE ONLY. This neither fetches Storage objects nor establishes
// their identity, generation, safety, validation, attachment or delivery rights.
import { createHash } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { setImmediate as yieldTurn } from 'node:timers/promises';

export const MAX_BYTES = 20 * 1024 * 1024;
export const MAX_CHUNKS = 65_536;
const fields = new Set(['source', 'expectedByteLength', 'signal', 'timeoutMs', 'maxBytes']);
const STOP = Symbol('stopped');
const ERROR = Symbol('source error');

function result(outcome, extra = {}) {
  return Object.freeze({ outcome, eligible: false, generationVerified: false,
    scanner: 'not_run', ...extra });
}

function options(input) {
  if (input === null || typeof input !== 'object' ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(input))) return null;
  const descriptors = Object.getOwnPropertyDescriptors(input);
  if (Reflect.ownKeys(descriptors).some(key => !fields.has(key) ||
      !Object.hasOwn(descriptors[key], 'value'))) return null;
  const value = Object.fromEntries(Object.entries(descriptors).map(([key, d]) => [key, d.value]));
  const { source, expectedByteLength, signal, timeoutMs = 20_000, maxBytes = MAX_BYTES } = value;
  if (typeof source !== 'function' || !Number.isInteger(maxBytes) || maxBytes < 1 || maxBytes > MAX_BYTES ||
      !Number.isInteger(expectedByteLength) || expectedByteLength < 1 || expectedByteLength > maxBytes ||
      !Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 20_000 ||
      (signal !== undefined && !(signal instanceof AbortSignal))) return null;
  return { source, expectedByteLength, signal, timeoutMs, maxBytes };
}

/** Observe a bounded stream from a trusted, cooperative in-process adapter.
 * Hostile bytes are allowed; hostile executable adapter code is NOT sandboxed.
 * No source bytes or errors escape. A digest is local observation, not proof.
 */
export async function observeBytes(input) {
  let config;
  try { config = options(input); } catch { return result('invalid_input'); }
  if (!config) return result('invalid_input');
  const { source, expectedByteLength, signal, timeoutMs, maxBytes } = config;
  if (signal?.aborted) return result('cancelled');

  const controller = new AbortController();
  const started = performance.now();
  let stopCode = null, interrupt = null, iterator = null;
  let timer;
  function stop(code) {
    if (stopCode !== null) return;
    stopCode = code;
    // First settle the caller even if adapter cleanup is slow or uncooperative.
    interrupt?.();
    controller.abort();
  }
  function check() {
    if (stopCode === null && performance.now() - started >= timeoutMs) stop('timeout');
    return stopCode !== null;
  }
  const cancelled = () => stop('cancelled');
  function next() {
    if (check()) return Promise.resolve(STOP);
    return new Promise(resolve => {
      let pending = true;
      const settle = value => {
        if (!pending) return;
        pending = false;
        interrupt = null;
        resolve(value);
      };
      interrupt = () => settle(STOP);
      // Observe late errors; never start a subsequent pull after termination.
      Promise.resolve().then(() => {
        if (check()) return STOP;
        const pull = iterator.next;
        // A trusted adapter getter can synchronously cancel its caller.
        if (check()) return STOP;
        if (typeof pull !== 'function') return ERROR;
        return pull.call(iterator);
      }).then(
        value => settle(value), () => settle(ERROR));
    });
  }

  try {
    signal?.addEventListener('abort', cancelled, { once: true });
    if (signal?.aborted) stop('cancelled');
    timer = setTimeout(() => stop('timeout'), timeoutMs);
    if (check()) return result(stopCode);
    const iterable = source(controller.signal);
    if (check()) return result(stopCode);
    if (typeof iterable?.[Symbol.asyncIterator] !== 'function') return result('source_error');
    iterator = iterable[Symbol.asyncIterator]();
    if (!iterator || typeof iterator.next !== 'function') return result('source_error');
    const hash = createHash('sha256');
    let byteLength = 0, chunks = 0;
    while (true) {
      const step = await next();
      if (check() || step === STOP) return result(stopCode ?? 'timeout');
      if (step === ERROR || step === null || typeof step !== 'object' || typeof step.done !== 'boolean') {
        return result('source_error');
      }
      if (step.done) {
        if (byteLength !== expectedByteLength) return result('size_mismatch');
        const sha256 = hash.digest('hex');
        if (check()) return result(stopCode);
        return result('observed', { byteLength, sha256 });
      }
      if (++chunks > MAX_CHUNKS) return result('chunk_limit');
      const chunk = step.value;
      if (!(chunk instanceof Uint8Array) ||
          (typeof SharedArrayBuffer !== 'undefined' && chunk.buffer instanceof SharedArrayBuffer) ||
          chunk.buffer.resizable === true) return result('unsupported_chunk');
      if (chunk.byteLength > maxBytes - byteLength) return result('too_large');
      if (chunk.byteLength > expectedByteLength - byteLength) return result('size_mismatch');
      // Copy the current chunk before hashing; no borrowed view survives a pull.
      const owned = Buffer.from(chunk);
      hash.update(owned);
      byteLength += owned.byteLength;
      if (check()) return result(stopCode);
      // Promise-only/empty streams must not starve deadlines or external aborts.
      if (chunks % 64 === 0) await yieldTurn();
    }
  } catch {
    return result(stopCode ?? 'source_error');
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener('abort', cancelled);
    interrupt = null;
    controller.abort();
    // Iterator cleanup is requested once, but cannot hold the observation open.
    // This does not prove that an underlying syscall or remote writer stopped.
    try {
      const close = iterator?.return;
      if (typeof close === 'function') Promise.resolve(close.call(iterator)).catch(() => {});
    } catch { /* Cleanup lookup/call errors must not override the safe result. */ }
  }
}
