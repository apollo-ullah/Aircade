import { evaluateAstra } from './astra.mjs';
import { evaluateJev } from './jev.mjs';
import { canonicalState, decisionPlan, ProviderError, normalizeFailure, cadenceMs, deadlineMs } from './contract.mjs';

export class TacticalPlanner {
  constructor({ adapters = { astra: evaluateAstra, jev: evaluateJev }, now = () => performance.now(), maxCalls = 120, spacingMs = cadenceMs, timeoutMs = deadlineMs } = {}) {
    this.adapters = adapters; this.now = now; this.maxCalls = maxCalls; this.spacingMs = spacingMs; this.timeoutMs = timeoutMs;
    this.providers = new Map();
  }
  nextEligibleInMs(provider) {
    const current = this.providers.get(provider);
    if (!current) return 0;
    // Timers may wake early and performance.now() has fractional milliseconds.
    // The caller must recheck this clock after waiting, not round down a delay.
    return Math.max(0, Math.ceil(Math.max(current.lastStart + this.spacingMs, current.nextAllowed) - this.now()), current.inFlight ? this.spacingMs : 0);
  }
  async plan(body, { signal } = {}) {
    const adapter = this.adapters[body?.provider];
    if (!adapter) throw new ProviderError('invalid', { status: 400, source: 'local', requestSent: false });
    let state;
    try { state = canonicalState(body); }
    catch (error) {
      const failure = normalizeFailure(error);
      failure.source = 'local'; failure.requestSent = false; throw failure;
    }
    const current = this.providers.get(body.provider) || { lastStart: -Infinity, nextAllowed: -Infinity, calls: 0, inFlight: false };
    this.providers.set(body.provider, current);
    const now = this.now();
    const retryMs = Math.max(current.lastStart + this.spacingMs, current.nextAllowed) - now;
    if (current.inFlight || retryMs > 0) throw new ProviderError('rate_limit', { retryAfterMs: Math.max(1, retryMs, current.inFlight ? this.spacingMs : 0), source: 'local', requestSent: false });
    if (current.calls >= this.maxCalls) throw new ProviderError('budget', { source: 'local', requestSent: false });
    if (signal?.aborted) throw new ProviderError('cancelled', { source: 'local', requestSent: false });
    current.inFlight = true; current.lastStart = now; current.calls++;
    const timeout = AbortSignal.timeout(this.timeoutMs);
    const combined = signal ? AbortSignal.any([signal, timeout]) : timeout;
    const receivedAt = new Date().toISOString();
    let requestSent = false;
    try {
      const result = await adapter({ state, signal: combined, onRequestStart: () => { requestSent = true; } });
      if (combined.aborted) throw normalizeFailure({ metadata: result }, combined);
      const latencyMs = Math.round(this.now() - now);
      if (latencyMs > this.timeoutMs) throw new ProviderError('timeout', { metadata: result });
      return { ...decisionPlan({ body, state, result, latencyMs, receivedAt, completedAt: new Date().toISOString() }), requestSent };
    } catch (error) {
      const failure = normalizeFailure(error, combined);
      failure.requestSent = requestSent || failure.requestSent === true;
      failure.source ||= failure.requestSent ? (error instanceof ProviderError ? 'provider' : 'network') : 'local';
      if (failure.code === 'rate_limit') current.nextAllowed = this.now() + (failure.retryAfterMs || 1000);
      throw failure;
    } finally { current.inFlight = false; }
  }
}
