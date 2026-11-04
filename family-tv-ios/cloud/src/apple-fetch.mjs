// Apple's server library uses node-fetch v2's timeout and buffer() APIs for
// OCSP. Keep online certificate revocation checks active in the Worker runtime.
export const Headers = globalThis.Headers;
export default async function appleFetch(url, options = {}) {
 const {timeout = 30000, ...init} = options;
 const timeoutSignal = AbortSignal.timeout(timeout);
 const signal = init.signal ? AbortSignal.any([init.signal, timeoutSignal]) : timeoutSignal;
 const response = await fetch(url, {...init, signal});
 return {
  ok: response.ok, status: response.status, headers: response.headers,
  buffer: async () => Buffer.from(await response.arrayBuffer())
 };
}
