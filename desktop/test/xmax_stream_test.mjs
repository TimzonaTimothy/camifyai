// Run with: node --test test/xmax_stream_test.mjs
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const dart = readFileSync(new URL('../lib/screens/playground/realtime_stream_screen.dart', import.meta.url), 'utf8');
const source = dart.split('<script type="module">')[1].split('</script>')[0]
  .replaceAll('$safeCredits', '1000')
  .replaceAll('$safeToken', 'uk-initial')
  .replaceAll('$safeModel', 'x2.1')
  .replaceAll('$_environment', 'global')
  .replaceAll('$_bridgeKey', 'test-bridge')
  .replaceAll('$faceDataUrl', 'data:image/jpeg;base64,YQ==');

function setup({ failCamera = false, autoStart = false } = {}) {
  const elements = new Map();
  const node = () => ({
    style: {}, dataset: {}, classList: { add() {}, remove() {} },
    value: 'Replace this character', disabled: false,
    appendChild() {}, replaceWith() {}, addEventListener() {}, pause() {},
  });
  const document = {
    getElementById(id) { if (!elements.has(id)) elements.set(id, node()); return elements.get(id); },
    createElement: node,
  };
  const calls = { generations: [], closed: 0, uploads: 0, fetch: [], timers: new Map() };
  let stateListener;
  let tracksListener;
  const manager = {
    async setStateListener(listener) { stateListener = listener; },
    setRemoteMediaTracksListener(listener) { tracksListener = listener; },
    async createLocalCameraStream(options) {
      assert.equal(options.useMicrophone, false);
      assert.equal(options.preset, '1920x1080');
      if (failCamera) throw new Error('Camera denied');
      return { videoTrack: 'local' };
    },
    async startGeneration(options) {
      calls.generations.push(options);
      tracksListener({ videoTrack: 'processed-video' });
      return { videoTrack: 'remote' };
    },
    async close() { calls.closed++; },
  };
  class View {
    element = node(); videoElement = node();
    detach() {}
    set track(track) {
      if (track === 'remote') stateListener({ connectionState: 'Generating' });
    }
  }
  const mockSdk = {
    XmaxClient: class {
      createRealtimeManager() { return manager; }
      createStorageService() { return { async uploadImage() { calls.uploads++; return { url: 'https://storage/ref.jpg' }; } }; }
    },
    XmaxConfiguration: class { constructor(options) { assert.match(options.apiKey, /^uk-/); } },
    RealtimeConfiguration: class { constructor(options) { assert.equal(options.model, 'x2.1'); } },
    RealtimeContext: class { constructor(options) { Object.assign(this, options); } },
    XmaxRealtimeVideoView: View,
    XmaxEnvironment: { global: 'global' },
    RealtimeConnectionState: { generating: 'Generating' },
    RealtimeCameraPreset: { resolution1920x1080: '1920x1080' }, CameraPosition: { front: 'front' },
  };
  const context = vm.createContext({
    document, mockSdk, console: { warn() {} },
    File: class { constructor() { this.name = 'face.jpg'; this.type = 'image/jpeg'; } },
    MediaStream: class { constructor(tracks) { this.tracks = tracks; } },
    atob: value => Buffer.from(value, 'base64').toString('binary'),
    setInterval() { return 1; }, clearInterval() {},
    setTimeout(fn, delay) { calls.timers.set(2, { fn, delay }); return 2; },
    clearTimeout(id) { calls.timers.delete(id); },
    async fetch(url, options) {
      calls.fetch.push({ url, options });
      return { ok: true, json: async () => ({token: 'uk-renewed', expires_at: new Date(Date.now() + 300000).toISOString()}) };
    },
  });
  context.window = context;
  context.addEventListener = () => {};
  const script = source.replace('window.startStream(); // Automatically connect with the selected face.',
    'loadSdk = async () => mockSdk; window.autoStartPromise = ' + (autoStart ? 'window.startStream();' : 'Promise.resolve();'));
  new vm.Script(script, { importModuleDynamically: () => Promise.reject(new Error('Use test SDK')) }).runInContext(context);
  vm.runInContext('loadSdk = async () => mockSdk', context);
  return { context, calls, document };
}

test('XMax reference upload, prompt updates, clear reference, OBS stream and cleanup', async () => {
  const { context, calls } = setup();
  await context.startStream();
  assert.equal(calls.uploads, 1);
  assert.equal(calls.generations[0].context.referencePath, 'https://storage/ref.jpg');
  assert.deepEqual(Array.from(context._remoteStream.tracks), ['processed-video']);
  await context.applyPrompt();
  assert.equal(calls.generations[1].context.referencePath, 'https://storage/ref.jpg');
  await context.clearFace();
  assert.equal(calls.generations[2].context.referencePath, undefined);
  await context.stopStream();
  assert.equal(calls.closed, 1);
  assert.equal(calls.timers.size, 0);
  await context.startStream();
  assert.equal(calls.fetch[0].url, '/api/token/refresh');
  assert.equal(calls.fetch[0].options.headers['X-Stream-Key'], 'test-bridge');
});

test('camera failure closes the XMax manager and permits retry', async () => {
  const { context, calls, document } = setup({ failCamera: true });
  await context.startStream();
  assert.equal(calls.closed, 1);
  assert.equal(calls.generations.length, 0);
  assert.equal(document.getElementById('startBtn').disabled, false);
  assert.match(document.getElementById('statusText').textContent, /Camera denied/);
});

test('permanent-key streaming has no key-expiry shutdown timer', async () => {
  const { context, calls } = setup();
  await context.startStream();
  assert.equal(calls.timers.size, 0);
  assert.equal(calls.closed, 0);
  assert.equal(calls.fetch.length, 0);
});

test('studio launches automatically with the reference in the first generation', async () => {
  const { context, calls } = setup({ autoStart: true });
  await context.autoStartPromise;
  assert.equal(calls.uploads, 1);
  assert.equal(calls.generations.length, 1);
  assert.equal(calls.generations[0].context.referencePath, 'https://storage/ref.jpg');
  assert.equal(dart.includes('onclick="applyFaceSwap()"'), false);
  await context.startStream();
  assert.equal(calls.generations.length, 1, 'starting twice must not open another session');
});

test('user-facing status replaces provider and model names', async () => {
  const { context, document } = setup();
  vm.runInContext("setStatus('XMax X2.1 is connecting')", context);
  assert.doesNotMatch(document.getElementById('statusText').textContent, /xmax|x2[.]1/i);
});
