import { decodeMessage, encodeMessage } from './protocol.js';
import { QualityTransitionCoordinator } from './quality-transition-coordinator.js';
import { StatsSampler } from './webrtc-stats.js';

const query = new URLSearchParams(location.search);
const sourceId = query.get('sourceId');
const width = Number(query.get('width'));
const height = Number(query.get('height'));
const fps = Number(query.get('fps'));
const bitrate = Number(query.get('bitrate'));
let peer;
let stream;
let viewerId;
let statsTimer;
let statsPending = false;
let captureScale = 1;
const statsSampler = new StatsSampler('outbound');
const CAPTURE_TIMEOUT_MS = 8_000;

function stopStream(value) { value?.getTracks().forEach((track) => track.stop()); }

async function capture(scale = 1) {
  return navigator.mediaDevices.getUserMedia({ audio: false, video: { mandatory: {
    chromeMediaSource: 'desktop', chromeMediaSourceId: sourceId,
    minWidth: Math.max(2, Math.round(width * scale)), maxWidth: Math.max(2, Math.round(width * scale)),
    minHeight: Math.max(2, Math.round(height * scale)), maxHeight: Math.max(2, Math.round(height * scale)),
    minFrameRate: 15, maxFrameRate: fps
  } } });
}

async function captureWithTimeout(scale) {
  let timedOut = false;
  let timer;
  const task = capture(scale).then((value) => {
    if (timedOut) { stopStream(value); throw new Error('Capture completed after transition timeout'); }
    return value;
  });
  const timeout = new Promise((_, reject) => { timer = setTimeout(() => {
    timedOut = true; reject(new Error(`Timed out changing capture scale to ${scale}`));
  }, CAPTURE_TIMEOUT_MS); });
  try { return await Promise.race([task, timeout]); } finally { clearTimeout(timer); }
}

async function replaceQuality(scale, isStale = () => false) {
  if (stream && scale === captureScale) return true;
  const replacement = await captureWithTimeout(scale);
  if (isStale()) { stopStream(replacement); return false; }
  const oldTrack = stream?.getVideoTracks()[0]; const nextTrack = replacement.getVideoTracks()[0];
  if (!nextTrack) { stopStream(replacement); throw new Error('Replacement capture has no video track'); }
  if (!stream || !oldTrack) {
    stream = replacement; captureScale = scale; return true;
  }
  const currentPeer = peer; const currentStream = stream;
  try {
    const sender = videoSender();
    if (currentPeer && !sender) throw new Error('Video sender disappeared during track replacement');
    if (sender) await sender.replaceTrack(nextTrack);
    if (currentPeer !== peer || currentStream !== stream || isStale()) {
      if (sender && oldTrack.readyState === 'live') await sender.replaceTrack(oldTrack);
      stopStream(replacement); return false;
    }
    currentStream.removeTrack(oldTrack); currentStream.addTrack(nextTrack); oldTrack.stop();
    stream = currentStream; captureScale = scale;
    return true;
  } catch (error) {
    stopStream(replacement);
    throw error;
  }
}

function videoSender() { return peer?._pc?.getSenders().find((sender) => sender.track?.kind === 'video'); }

async function applyProfile(message, isStale) {
  const sender = videoSender(); if (!sender) throw new Error('Video sender is unavailable');
  const parameters = sender.getParameters();
  if (!parameters.encodings?.length) parameters.encodings = [{}];
  const previous = { maxBitrate: parameters.encodings[0].maxBitrate, maxFramerate: parameters.encodings[0].maxFramerate };
  parameters.encodings[0].maxBitrate = message.maxBitrateBps;
  parameters.encodings[0].maxFramerate = message.maxFps;
  await sender.setParameters(parameters);
  if (isStale()) return;
  try {
    if (!await replaceQuality(message.scale, isStale)) return;
  } catch (error) {
    const rollback = sender.getParameters();
    if (!rollback.encodings?.length) rollback.encodings = [{}];
    rollback.encodings[0].maxBitrate = previous.maxBitrate;
    rollback.encodings[0].maxFramerate = previous.maxFramerate;
    try { await sender.setParameters(rollback); } catch (rollbackError) { console.error('Quality rollback failed', rollbackError); }
    throw error;
  }
  const result = { appliedScale: captureScale };
  if (isStale() || sender !== videoSender()) return result;
  const settings = sender.track?.getSettings() || {}; const applied = sender.getParameters().encodings?.[0] || {};
  try {
    peer.send(encodeMessage({ type: 'quality-applied', sequence: message.sequence, profile: message.profile,
      scale: captureScale,
      trackWidth: settings.width || width, trackHeight: settings.height || height,
      maxFps: applied.maxFramerate || message.maxFps, maxBitrateBps: applied.maxBitrate || message.maxBitrateBps }));
  } catch (error) { console.error('Quality acknowledgement failed', error); }
  return result;
}

async function applyManual(scale, isStale) {
  if (!await replaceQuality(scale, isStale)) return;
  const sender = videoSender(); if (!sender) return;
  if (isStale()) return { appliedScale: captureScale };
  const parameters = sender.getParameters();
  if (!parameters.encodings?.length) parameters.encodings = [{}];
  parameters.encodings[0].maxBitrate = bitrate;
  parameters.encodings[0].maxFramerate = fps;
  await sender.setParameters(parameters);
  return { appliedScale: captureScale };
}

const qualityQueue = new QualityTransitionCoordinator(async (request, isStale) => {
  if (request.kind === 'manual') return applyManual(request.scale, isStale);
  else {
    try { return await applyProfile(request.message, isStale); }
    catch (error) {
      if (!isStale() && peer?.connected) {
        try {
          peer.send(encodeMessage({ type: 'quality-failed',
            sequence: request.message.sequence, profile: request.message.profile,
            reason: String(error?.message || error).slice(0, 256) || 'quality transition failed' }));
        } catch (acknowledgementError) { console.error('Quality failure acknowledgement failed', acknowledgementError); }
      }
      throw error;
    }
  }
});

async function sendStats() {
  if (!peer?.connected || !peer._pc || statsPending) return;
  statsPending = true;
  try {
    const connection = peer._pc; const reports = await connection.getStats();
    if (peer?._pc !== connection) return;
    const sample = statsSampler.sample(reports);
    if (sample && peer.connected) peer.send(encodeMessage({ type: 'host-stats', sample }));
  } finally { statsPending = false; }
}

async function rebuild(id) {
  qualityQueue.reset(captureScale); peer?.destroy(); clearInterval(statsTimer); statsPending = false; statsSampler.reset(); viewerId = id;
  if (!stream) stream = await capture(1);
  const candidate = new window.SimplePeer({ initiator: true, trickle: true, stream, config: { iceServers: [] } });
  peer = candidate;
  candidate.on('signal', (signal) => window.streamHost.signal({ viewerId: id, signal }));
  candidate.on('connect', () => { statsTimer = setInterval(() => sendStats().catch(console.error), 500); });
  candidate.on('data', (bytes) => {
    const legacy = (() => { try { return JSON.parse(new TextDecoder().decode(bytes)); } catch { return null; } })();
    if (legacy?.type === 'quality' && [0.5, 1].includes(legacy.scale)) qualityQueue.enqueue({ kind: 'manual', scale: legacy.scale });
    const message = decodeMessage(bytes);
    if (message?.type === 'quality-command') {
      qualityQueue.enqueue({ kind: 'profile', sequence: message.sequence, scale: message.scale, message });
    }
  });
  candidate.on('error', (error) => console.error('WebRTC host error', error));
}

window.streamHost.onViewerConnected((id) => rebuild(id).catch(console.error));
window.streamHost.onViewerDisconnected((id) => { if (id === viewerId) { qualityQueue.reset(); clearInterval(statsTimer); peer?.destroy(); peer = undefined; } });
window.streamHost.onViewerSignal(({ viewerId: id, signal }) => { if (id === viewerId) peer?.signal(signal); });
window.streamHost.ready();
