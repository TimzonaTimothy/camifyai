import '../../widgets/responsive_layout.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/credit_display.dart';
import '../../widgets/shared_widgets.dart';
import '../../utils/error_handler.dart';

class RealtimeStreamScreen extends StatefulWidget {
  final String model;
  final String? prompt;
  final String? faceImageBase64;

  const RealtimeStreamScreen({
    super.key,
    required this.model,
    this.prompt,
    this.faceImageBase64,
  });

  @override
  State<RealtimeStreamScreen> createState() => _RealtimeStreamScreenState();
}

class _RealtimeStreamScreenState extends State<RealtimeStreamScreen> {
  bool _loading = true;
  bool _launched = false;
  String? _error;
  String? _streamToken;
  String? _expiresAt;
  String _environment = 'global';
  String _model = 'x2.1';
  double? _creditsRemaining;

  final String _bridgeKey =
      List.generate(32, (_) => Random.secure().nextInt(256))
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();

  HttpServer? _server;
  int? _port;
  String? _htmlContent;

  @override
  void initState() {
    super.initState();
    _fetchAndLaunch();
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  // ── Pick a free port ───────────────────────────────────────────────────────
  Future<int> _getFreePort() async {
    final rand = Random();
    for (int i = 0; i < 20; i++) {
      final port = 8700 + rand.nextInt(100);
      try {
        final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
        await s.close();
        return port;
      } catch (_) {}
    }
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  // ── Start local HTTP server ────────────────────────────────────────────────
  String? _popoutHtml;

  Future<void> _startServer(String html) async {
    await _server?.close(force: true);
    _port = await _getFreePort();
    _htmlContent = html;
    _popoutHtml = _buildPopoutHtml();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port!);
    _server!.listen((request) async {
      final path = request.uri.path;
      if (path.startsWith('/api/')) {
        if (request.method != 'POST' ||
            request.headers.value('X-Stream-Key') != _bridgeKey) {
          request.response
            ..statusCode = 403
            ..close();
          return;
        }
        try {
          final Map<String, dynamic> result;
          if (path == '/api/heartbeat') {
            result = await ApiService.instance.streamHeartbeat();
          } else if (path == '/api/token/refresh') {
            result = await ApiService.instance.refreshRealtimeToken();
          } else {
            request.response
              ..statusCode = 404
              ..close();
            return;
          }
          request.response
            ..statusCode = result['statusCode'] as int? ?? 502
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(result))
            ..close();
        } catch (_) {
          request.response
            ..statusCode = 502
            ..close();
        }
        return;
      }
      if (path == '/popout') {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write(_popoutHtml)
          ..close();
      } else {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.html
          ..write(_htmlContent)
          ..close();
      }
    });
  }

  // ── Main flow ──────────────────────────────────────────────────────────────
  Future<void> _fetchAndLaunch() async {
    setState(() {
      _loading = true;
      _error = null;
      _launched = false;
    });
    try {
      final result = await ApiService.instance.getRealtimeToken(widget.model);
      final statusCode = result['statusCode'];
      if (statusCode != null && statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _error = 'Could not prepare your studio. Please try again.';
          _loading = false;
        });
        return;
      }
      if (result['token'] == null) {
        if (!mounted) return;
        setState(() {
          _error = 'Could not prepare your studio. Please try again.';
          _loading = false;
        });
        return;
      }

      _streamToken = result['token'] as String;
      _expiresAt = result['expires_at']?.toString();
      _environment = result['environment'] as String? ?? 'global';
      _model = result['model'] as String? ?? 'x2.1';
      _creditsRemaining = (result['credits_remaining'] as num?)?.toDouble();

      if (_creditsRemaining != null && mounted) {
        context.read<AuthProvider>().updateCredits(_creditsRemaining!);
      }

      final html = _buildStreamingHtml();
      await _startServer(html);

      if (!mounted) return;
      setState(() => _loading = false);
      await _openInBrowser();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorHandler.sanitize(e);
        _loading = false;
      });
    }
  }

  Future<void> _openInBrowser() async {
    final url = Uri.parse('http://127.0.0.1:$_port');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      setState(() => _launched = true);
    } else {
      if (!mounted) return;
      setState(() => _error =
          'Could not open browser.\nOpen manually: http://127.0.0.1:$_port');
    }
  }

  Future<void> _refreshToken() async {
    await _server?.close(force: true);
    _server = null;
    await _fetchAndLaunch();
  }

  void _copyUrl() {
    if (_port == null) return;
    Clipboard.setData(ClipboardData(text: 'http://127.0.0.1:$_port'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('URL copied — paste it in your browser'),
        duration: Duration(seconds: 2),
        backgroundColor: AppColors.success,
      ),
    );
  }

  // ── Build the pop-out page (minimal, just the video — for OBS capture) ─────
  String _buildPopoutHtml() {
    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>AI Output — OBS Capture</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box;}
  html,body{width:100%;height:100%;overflow:hidden;background:#000;}
  video{width:100%;height:100%;object-fit:contain;display:block;background:#000;}
  .waiting{width:100%;height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px;color:#55556A;font-family:'Segoe UI',system-ui,sans-serif;font-size:14px;}
  .waiting .icon{font-size:3rem;}
  .waiting .hint{font-size:11px;color:#444;max-width:300px;text-align:center;line-height:1.5;}
</style>
</head>
<body>
  <div class="waiting" id="waitMsg">
    <div class="icon">🤖</div>
    <span>Waiting for AI stream…</span>
    <span class="hint">Point OBS Window Capture at this window. The stream will appear automatically once connected.</span>
  </div>
  <video id="popoutVideo" autoplay playsinline style="display:none"></video>
  <script>
    // Poll the opener window for the MediaStream (can't use postMessage for MediaStream)
    // Since both windows are same-origin (localhost), we can directly access opener properties
    const video = document.getElementById('popoutVideo');
    const msg   = document.getElementById('waitMsg');
    let attached = false;

    function attachStream() {
  try {
    if (window.opener && window.opener._remoteStream) {
      if (video.srcObject !== window.opener._remoteStream) {
        video.srcObject = window.opener._remoteStream;
        video.play && video.play().catch(()=>{});
      }
      video.style.display = 'block';
      if (msg) msg.style.display = 'none';
      attached = true;
      return true;
    }
  } catch(e) {}
  return false;
}

    function tryAttachStream() {
      if (attached) return;
      attachStream();
    }

    // Try immediately, then poll every 300ms until attached
    tryAttachStream();
const pollId = setInterval(function() {
  // Always try to re-attach — stream object can be replaced after reconnect
  attachStream();
  if (!window.opener || window.opener.closed) clearInterval(pollId);
}, 300);

    // Also listen for the opener to notify us directly
    window.addEventListener('message', function(e) {
      if (e.data === 'stream-updated') {
        // A (re)started stream is available on the opener — force a reattach
        // even if we were already attached to a previous (now stale) stream.
        attached = false;
        attachStream();
      }
      if (e.data === 'stream-paused') {
        // User clicked Stop — freeze on the last rendered AI frame instead of
        // reverting to the "waiting for AI stream" placeholder. OBS keeps
        // capturing whatever is currently on screen.
        try { video.pause(); } catch(err) {}
      }
      if (e.data === 'clear-stream') {
        video.srcObject = null;
        video.style.display = 'none';
        if (msg) msg.style.display = 'flex';
        attached = false;
      }
    });
  </script>
</body>
</html>''';
  }

  // ── Build the streaming HTML ───────────────────────────────────────────────
  String _buildStreamingHtml() {
    final safeToken = (_streamToken ?? '')
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll("'", "\\'");
    final safeModel = _model
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll("'", "\\'");
    final safePrompt = const HtmlEscape().convert(widget.prompt
                ?.trim()
                .isNotEmpty ==
            true
        ? widget.prompt!
        : widget.faceImageBase64 != null
            ? 'Replace the person in the video with the person in the reference image. Preserve their pose, expression, movement and background.'
            : 'Transform this scene');
    final faceBase64 = widget.faceImageBase64;
    final faceMime = faceBase64?.startsWith('iVBOR') == true
        ? 'image/png'
        : faceBase64?.startsWith('UklGR') == true
            ? 'image/webp'
            : 'image/jpeg';
    final faceDataUrl =
        faceBase64 != null ? 'data:$faceMime;base64,$faceBase64' : '';
    final hasFace = widget.faceImageBase64 != null;

    // Inject backend settings for heartbeat & token refresh
    final safeCredits = (_creditsRemaining ?? 0).toStringAsFixed(0);

    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>camifyai · Live studio</title>
<style>
  :root{color-scheme:dark;--bg:#101313;--surface:#191e1d;--border:#303936;--muted:#a0aca6;--ink:#f1f5ee;--accent:#c9ef9c;--danger:#f1a49c;}
  *,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
  body{background:radial-gradient(ellipse at 80% 0%,#25322855,transparent 55%),var(--bg);color:var(--ink);font:14px/1.5 -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;min-height:100vh;display:flex;flex-direction:column;}
  button,input{font:inherit}button{cursor:pointer}button:disabled{opacity:.4;cursor:not-allowed}
  button:focus-visible,input:focus-visible,summary:focus-visible{outline:2px solid var(--accent);outline-offset:4px}
  .topbar{display:flex;align-items:center;gap:24px;padding:20px 4vw;border-bottom:1px solid var(--border);flex-wrap:wrap}
  .logo{font-weight:750;font-size:23px;letter-spacing:-1.2px}.logo span{color:var(--accent)}
  .workspace-label{color:var(--muted);font-size:12px;border-left:1px solid var(--border);padding-left:24px}
  .top-actions{margin-left:auto;display:flex;gap:10px;align-items:center;flex-wrap:wrap}
  .time-meter{padding-right:18px;display:flex;align-items:baseline;gap:8px}.time-meter small{color:var(--muted);font-size:11px}
  #creditsBar{font-size:18px;font-weight:650;font-variant-numeric:tabular-nums}
  .btn{border:1px solid transparent;border-radius:9px;padding:10px 18px;font-weight:600;font-size:12px;transition:background .2s,transform .2s}
  .btn:hover:not(:disabled){transform:translateY(-1px)}.green,.violet{background:var(--accent);color:#162015}.red{background:#2b201f;color:var(--danger);border-color:#573735}.ghost{background:transparent;border-color:var(--border);color:var(--ink)}
  .studio-heading{padding:32px 4vw 24px;display:flex;justify-content:space-between;align-items:end;gap:20px;flex-wrap:wrap}
  .eyebrow{font-size:10px;text-transform:uppercase;letter-spacing:2px;color:var(--accent);margin-bottom:8px}
  h1{font-size:clamp(26px,3vw,38px);font-weight:550;letter-spacing:-1.3px;line-height:1.2}.subtitle{color:var(--muted);font-size:13px;margin-top:8px}
  .status-pill{display:flex;align-items:center;gap:9px;padding:9px 14px;background:var(--surface);border:1px solid var(--border);border-radius:30px;font-size:12px;max-width:100%}
  .dot{width:7px;height:7px;background:#d9ba78;border-radius:50%;flex-shrink:0}.dot.live{background:var(--accent);box-shadow:0 0 0 4px #c9ef9c14}.dot.error{background:var(--danger)}
  .video-grid{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1.8fr);gap:20px;padding:0 4vw;min-height:420px;flex:1}.video-grid.single{grid-template-columns:1fr}
  .video-box{background:#080b0a;border:1px solid var(--border);border-radius:16px;position:relative;overflow:hidden;min-height:400px}.video-box.output{border-color:#536247;box-shadow:0 16px 70px #0003}
  .vlabel{position:absolute;top:18px;left:18px;z-index:4;display:flex;align-items:center;gap:8px;background:#101513c9;backdrop-filter:blur(12px);border:1px solid #ffffff12;border-radius:7px;padding:6px 10px;color:#d8e2d9;font-size:11px;font-weight:500}
  .vlabel small{color:#8f9b94}.vcontrols{position:absolute;bottom:18px;right:18px;z-index:4;display:flex;gap:7px;flex-wrap:wrap}
  .vbtn{background:#141a17dd;color:var(--ink);border:1px solid #ffffff20;border-radius:7px;padding:8px 12px;font-size:11px;backdrop-filter:blur(10px)}.vbtn:hover{background:#344131}
  .rec{width:6px;height:6px;background:var(--accent);border-radius:50%}
  video{width:100%;height:100%;object-fit:contain;background:#080b0a;display:block}
  .no-video{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px;padding:24px;text-align:center;color:var(--muted);font-size:12px;z-index:2;background:radial-gradient(ellipse at center,#202b22,#0c100e 75%)}
  .no-video strong{color:var(--ink);font-size:16px;font-weight:500}.no-video .icon{width:48px;height:48px;border:1px solid #71836a66;border-radius:14px;display:grid;place-items:center;color:var(--accent);font-size:22px;margin-bottom:8px}
  .session-footer{margin:20px 4vw 28px;display:flex;align-items:center;justify-content:space-between;gap:20px;padding:18px 0;border-top:1px solid var(--border);flex-wrap:wrap}
  .ref-panel{display:flex;align-items:center;gap:12px;min-width:0}.ref-thumb{width:42px;height:42px;border-radius:10px;object-fit:cover;border:1px solid #ffffff20}.ref-info{font-size:11px;color:var(--muted)}.ref-info strong{font-size:12px;color:var(--ink);display:block;font-weight:550}.session-note{font-size:11px;color:var(--muted);max-width:300px}
  .popout-banner{display:none;align-items:center;gap:14px;padding:12px 4vw;margin-bottom:16px;background:#233021;font-size:12px;color:var(--accent)}.popout-banner.visible{display:flex}.popout-banner .info{flex:1}
  details{margin:0 4vw 24px;border:1px solid var(--border);border-radius:12px;background:var(--surface)}summary{padding:14px 18px;color:var(--muted);font-size:12px;cursor:pointer}.prompt-bar{display:flex;gap:10px;padding:0 18px 18px;flex-wrap:wrap}.prompt-bar input{flex:1;min-width:160px;background:#101613;color:var(--ink);border:1px solid var(--border);border-radius:8px;padding:10px 12px;font-size:12px}
  #log{display:none!important}.overlay{position:fixed;inset:0;background:#0b100ef5;z-index:9999;display:none;align-items:center;justify-content:center;text-align:center;flex-direction:column;gap:18px;padding:30px}.overlay h2{font-size:30px;letter-spacing:-1px;font-weight:550}.overlay p{color:var(--muted);max-width:360px}
  @media(min-width:1400px){.video-grid{min-height:520px}.video-box{min-height:500px}}
  @media(max-width:760px){.workspace-label{display:none}.topbar{gap:16px}.top-actions{width:100%;margin:0;justify-content:space-between}.time-meter{padding:0}.studio-heading{padding-top:24px}.video-grid{grid-template-columns:1fr;min-height:0}.video-box{min-height:240px}.video-box.output{min-height:360px}.session-note{max-width:none}.vcontrols{bottom:12px;right:12px}}
  @media(prefers-reduced-motion:reduce){*{transition:none!important}}
</style>
</head>
<body>

<header class="topbar">
  <div class="logo">camify<span>ai</span></div>
  <span class="workspace-label">YOUR LIVE WORKSPACE</span>
  <div class="top-actions">
    <div class="time-meter"><span id="creditsBar">--:--</span><small>remaining</small></div>
    <button class="btn ghost" id="startBtn" onclick="startStream()">Resume stream</button>
    <button class="btn red" id="stopBtn" onclick="stopStream()" disabled>End stream</button>
  </div>
</header>
<section class="studio-heading">
  <div><p class="eyebrow">CAMIFYAI STUDIO</p><h1>Your next look. Live.</h1><p class="subtitle">Move naturally. Your new look follows you.</p></div>
  <div class="status-pill" role="status" aria-live="polite"><span class="dot" id="dot"></span><span id="statusText">Preparing your studio…</span></div>
</section>
<div id="outOfCreditsOverlay" class="overlay">
  <p class="eyebrow">SESSION PAUSED</p><h2>A little more time?</h2>
  <p>Your streaming time has run out. Return to camifyai to add time and pick up where you left off.</p>
  <button class="btn green" onclick="window.close()">Return to the app</button>
</div>
<div class="popout-banner" id="popoutBanner">
  <span class="info">Your output is open in a separate window. Select it in OBS Window Capture.</span>
  <button class="btn ghost" id="dockBackBtn" onclick="dockAI()">Bring back</button>
</div>
<main class="video-grid" id="videoGrid">
  <section class="video-box" aria-label="Camera preview">
    <div class="vlabel">01 <small>/</small> Your camera</div>
    <div class="no-video" id="localPh"><div class="icon">◎</div><strong>Let’s get you in frame</strong><span>Allow camera access when your browser asks.</span></div>
    <video id="localVideo" autoplay muted playsinline style="display:none"></video>
  </section>
  <section class="video-box output" id="remoteBox" aria-label="Live AI output">
    <div class="vlabel"><div class="rec" id="recDot" style="display:none"></div>02 <small>/</small> Your live look</div>
    <div class="vcontrols">
      <button class="vbtn" onclick="popoutAI()" title="Open your output for OBS capture">↗ Open for OBS</button>
      <button class="vbtn" onclick="fullscreenAI()" title="View output fullscreen">⛶ Fullscreen</button>
    </div>
    <div class="no-video" id="remotePh"><div class="icon">✧</div><strong>Bringing your look to life</strong><span>Your face is applied automatically. No extra steps.</span></div>
    <video id="remoteVideo" autoplay playsinline style="display:none"></video>
  </section>
</main>
<footer class="session-footer">
  ${hasFace ? '''<div class="ref-panel"><img class="ref-thumb" src="$faceDataUrl" alt="Selected reference face"><div class="ref-info"><strong>Your selected look</strong>Applied automatically when the stream starts</div></div>''' : '<div class="ref-info"><strong>Creative session</strong>Your camera, transformed in real time</div>'}
  <p class="session-note">Keep the camifyai app open during your session. Your camera stops when you end the stream.</p>
</footer>
<details><summary>Fine-tune your look</summary><div class="prompt-bar">
  <input type="text" id="promptInput" aria-label="Describe your look" placeholder="Describe a change to your look…" value="$safePrompt">
  <button class="btn violet" onclick="applyPrompt()">Update look</button>
</div></details>
<div id="log" aria-hidden="true"></div>

<script type="module">
// ── SDK loading ───────────────────────────────────────────────────────────────
// Pinned version + fallback CDN. A static import of @latest meant a single CDN
// error (e.g. HTTP 500) killed this whole module, leaving startStream undefined.
const SDK_URLS = [
  'https://cdn.jsdelivr.net/npm/@xmaxai/web-sdk@1.1.3/dist/browser/index.js',
  'https://unpkg.com/@xmaxai/web-sdk@1.1.3/dist/browser/index.js',
];
let sdkPromise = null;

function loadSdk() {
  if (!sdkPromise) {
    sdkPromise = (async () => {
      for (const url of SDK_URLS) {
        try { return await import(url); }
        catch (e) { console.warn('SDK load failed from ' + url, e); }
      }
      throw new Error('Could not load streaming SDK. Check your internet connection and try again.');
    })();
    sdkPromise.catch(() => { sdkPromise = null; });  // allow retry on next click
  }
  return sdkPromise;
}
loadSdk().catch(() => {});  // preload in the background

let TOKEN      = '$safeToken';
const MODEL_ID = '$safeModel';
const ENVIRONMENT = '$_environment';
let tokenUsed = false;
const FACE_URL = '$faceDataUrl';
const BRIDGE_KEY = '$_bridgeKey';

// ── Time-based billing ────────────────────────────────────────────────────────
const CREDITS_PER_SECOND    = 2;           // 2 credits burned every second
const HEARTBEAT_INTERVAL_S  = 10;          // POST /heartbeat/ every 10s


let creditsRemaining = $safeCredits;       // server-confirmed value, updated on each heartbeat
let displayCredits   = $safeCredits;       // client-side value, ticks down every second in UI

let localStream     = null;
let rtClient        = null;
let xmaxClient      = null;
let localView       = null;
let remoteView      = null;
let referencePath;
let stopping = false;
let remoteStreamRef = null;
let isPopped        = false;
let popoutWin       = null;
let heartbeatTimer  = null;   // fires every 10s → POST /heartbeat/
let countdownTimer  = null;   // fires every 1s  → UI countdown display

// ── DOM refs ──────────────────────────────────────────────────────────────────
const dot          = document.getElementById('dot');
const statusText   = document.getElementById('statusText');
const startBtn     = document.getElementById('startBtn');
const stopBtn      = document.getElementById('stopBtn');
let localVideo   = document.getElementById('localVideo');
let remoteVideo  = document.getElementById('remoteVideo');
const localPh      = document.getElementById('localPh');
const remotePh     = document.getElementById('remotePh');
const promptInput  = document.getElementById('promptInput');
const recDot       = document.getElementById('recDot');
const logEl        = document.getElementById('log');
const videoGrid    = document.getElementById('videoGrid');
const remoteBox    = document.getElementById('remoteBox');
const popoutBanner = document.getElementById('popoutBanner');

// ── Helpers ───────────────────────────────────────────────────────────────────
function log(msg, type='info') {
  const s = document.createElement('span');
  s.className = type;
  s.textContent = '[' + new Date().toLocaleTimeString() + '] ' + msg.replace(/xmax|x2[.]1/gi, 'camifyai') + '\\n';
  logEl.appendChild(s);
  logEl.scrollTop = logEl.scrollHeight;
}

function setStatus(msg, state='') {
  statusText.textContent = msg.replace(/xmax|x2[.]1/gi, 'camifyai');
  dot.className = 'dot' + (state ? ' ' + state : '');
}

function setLive(live) {
  recDot.style.display = live ? 'inline-block' : 'none';
}

function showVid(v, ph, stream) { v.srcObject = stream; v.style.display = 'block'; ph.style.display = 'none'; }
function hideVid(v, ph)         { v.srcObject = null; v.style.display = 'none'; ph.style.display = 'flex'; }

window.toggleLog = function() {
  const show = logEl.style.display === 'none';
  logEl.style.display = show ? 'block' : 'none';

};

// ── Expose stream on window so popout can access it directly ──────────────────
// MediaStream can't be sent via postMessage — same-origin windows share JS objects
window._remoteStream = null;

function notifyPopout() {
  if (popoutWin && !popoutWin.closed) {
    try { popoutWin.postMessage('stream-updated', '*'); } catch(e) {}
  }
}

// Hidden sink so WebRTC tracks keep running when the main window is minimized
let keepAliveVideo = null;
function ensureKeepAlive(stream) {
  if (!stream) return;
  if (!keepAliveVideo) {
    keepAliveVideo = document.createElement('video');
    keepAliveVideo.muted = true;
    keepAliveVideo.playsInline = true;
    keepAliveVideo.autoplay = true;
    keepAliveVideo.style.cssText =
      'position:fixed;width:1px;height:1px;opacity:0;pointer-events:none;left:-10px;top:-10px;';
    document.body.appendChild(keepAliveVideo);
  }
  keepAliveVideo.srcObject = stream;
  keepAliveVideo.play().catch(() => {});
}

// ── Pop out AI output into a SEPARATE browser window (for OBS) ───────────────
window.popoutAI = function() {
  // Close existing popout if any
  if (popoutWin && !popoutWin.closed) popoutWin.close();

  isPopped = true;

  // Open a real separate browser window — OBS can capture just this window
  popoutWin = window.open(
    'http://127.0.0.1:' + location.port + '/popout',
    'ai_output_obs',
    'width=640,height=480,menubar=no,toolbar=no,location=no,status=no,resizable=yes'
  );

  // Hide the inline remote box, expand camera to full width
  remoteBox.style.display = 'none';
  videoGrid.classList.add('single');
  popoutBanner.classList.add('visible');

  // The popout page polls window.opener._remoteStream, so just notify it
  if (remoteStreamRef && popoutWin) {
    // Notify after a short delay to let the window load
    setTimeout(() => notifyPopout(), 500);
  }

  // Watch for the popout being closed manually
  const watchClose = setInterval(() => {
    if (popoutWin && popoutWin.closed) {
      clearInterval(watchClose);
      if (isPopped) dockAI();
    }
  }, 1000);

  log('AI output opened in separate window — point OBS Window Capture at "AI Output — OBS Capture"', 'ok');
};

// ── Dock AI back into the grid ────────────────────────────────────────────────
window.dockAI = function() {
  isPopped = false;
  popoutBanner.classList.remove('visible');

  // Close the popout window
  if (popoutWin && !popoutWin.closed) {
    try { popoutWin.postMessage('clear-stream', '*'); } catch(e) {}
    popoutWin.close();
  }
  popoutWin = null;

  remoteBox.style.display = '';
  videoGrid.classList.remove('single');

  // Restore stream to inline video
  if (remoteStreamRef) {
    remoteView.element.style.display = "block";
    remotePh.style.display = "none";
  }
  log('AI output docked back into grid.');
};

// ── Fullscreen inline AI output ───────────────────────────────────────────────
window.fullscreenAI = function() {
  if (remoteVideo.requestFullscreen) remoteVideo.requestFullscreen();
  else if (remoteVideo.webkitRequestFullscreen) remoteVideo.webkitRequestFullscreen();
};

// ── dataURL → File ────────────────────────────────────────────────────────────
function dataURLtoFile(url, name) {
  const [head, b64] = url.split(',');
  const mime = head.match(/:(.*?);/)[1];
  const bin  = atob(b64);
  const arr  = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
  const extension = mime === 'image/png' ? 'png' : mime === 'image/webp' ? 'webp' : 'jpg';
  return new File([arr], 'reference.' + extension, { type: mime });
}

// ── Credits display helpers ──────────────────────────────────────────────────
function formatTime(totalSeconds) {
  totalSeconds = Math.max(0, Math.floor(totalSeconds));
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const s = totalSeconds % 60;
  if (h > 0) return h + 'h ' + String(m).padStart(2,'0') + 'm ' + String(s).padStart(2,'0') + 's';
  if (m > 0) return m + 'm ' + String(s).padStart(2,'0') + 's';
  return s + 's';
}

function updateCreditsDisplay() {
  const el = document.getElementById('creditsBar');
  if (!el) return;
  const secs = displayCredits / CREDITS_PER_SECOND;
  el.textContent = formatTime(secs);
  // Colour: green → orange → red as credits deplete
  if (secs > 120)      el.style.color = '#00D68F';
  else if (secs > 30)  el.style.color = '#FFAA00';
  else                 el.style.color = '#FF4C6E';
}

// ── 1-second client-side countdown (visual only, not billed) ─────────────────
function startCountdownTimer() {
  stopCountdownTimer();
  countdownTimer = setInterval(() => {
    displayCredits = Math.max(0, displayCredits - CREDITS_PER_SECOND);
    updateCreditsDisplay();
    if (displayCredits <= 0) {
      stopCountdownTimer();
      // Heartbeat will formally stop the stream on next tick
    }
  }, 1000);
}

function stopCountdownTimer() {
  if (countdownTimer) { clearInterval(countdownTimer); countdownTimer = null; }
}

// ── Heartbeat — POST /heartbeat/ every 10s, deducts credits server-side ───────
async function sendHeartbeat() {
  if (!rtClient) { stopAllTimers(); return; }
  try {
    const res = await fetch('/api/heartbeat', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Stream-Key': BRIDGE_KEY,
      },
    });
    const data = await res.json();

    if (res.status === 402 || data.stop === true) {
      // Out of time — stop immediately
      log('⛔ Time exhausted — stream stopped.', 'err');
      setStatus('Out of time — stream stopped', 'error');
      stopAllTimers();
      displayCredits   = 0;
      creditsRemaining = 0;
      updateCreditsDisplay();
      stopStream();
      showOutOfCreditsOverlay();
      return;
    }

    if (data.credits_remaining !== undefined) {
      creditsRemaining = data.credits_remaining;
      // Sync display to server value to prevent drift
      displayCredits = creditsRemaining;
      updateCreditsDisplay();
    }
  } catch(e) {
    log('Heartbeat error: ' + e.message, 'warn');
    // Don't stop stream on network blip — just warn and retry next tick
  }
}

// Recheck application access and read the configured key before reconnecting.
async function refreshStreamToken() {
  const res = await fetch('/api/token/refresh', {
    method: 'POST',
    headers: {'Content-Type': 'application/json', 'X-Stream-Key': BRIDGE_KEY},
  });
  const data = await res.json();
  if (!res.ok || !data.token) throw new Error(data.error || 'Unable to renew streaming access.');
  TOKEN = data.token;
  if (data.credits_remaining !== undefined) creditsRemaining = data.credits_remaining;
}

// ── Timer management ─────────────────────────────────────────────────────────
function startAllTimers() {
  stopAllTimers();
  // Heartbeat every 10 seconds — deducts credits server-side
  heartbeatTimer = setInterval(sendHeartbeat, HEARTBEAT_INTERVAL_S * 1000);
  // Countdown every 1 second — UI only
  startCountdownTimer();

}

function stopAllTimers() {
  if (heartbeatTimer) { clearInterval(heartbeatTimer); heartbeatTimer = null; }
  stopCountdownTimer();
}

// ── Out of credits overlay ────────────────────────────────────────────────────
function showOutOfCreditsOverlay() {
  const el = document.getElementById('outOfCreditsOverlay');
  if (el) el.style.display = 'flex';
}

// ── Start stream ──────────────────────────────────────────────────────────────
window.startStream = async function() {
  if (stopping || rtClient || startBtn.disabled) return;
  if (!TOKEN) { setStatus('Please reopen the studio from the app.', 'error'); return; }
  startBtn.disabled = true;
  setStatus('Preparing your look…');
  try {
    if (tokenUsed) {
      await refreshStreamToken();
    }
    const sdk = await loadSdk();
    xmaxClient = new sdk.XmaxClient(new sdk.XmaxConfiguration({
      apiKey: TOKEN,
      environment: ENVIRONMENT === 'china' ? sdk.XmaxEnvironment.china : sdk.XmaxEnvironment.global,
    }));
    rtClient = xmaxClient.createRealtimeManager(new sdk.RealtimeConfiguration({model: MODEL_ID}));
    tokenUsed = true;
    stopping = false;
    const previousLocal = localView;
    const previousRemote = remoteView;
    localView = new sdk.XmaxRealtimeVideoView({isInteractionEnabled: false});
    remoteView = new sdk.XmaxRealtimeVideoView({isInteractionEnabled: false});
    for (const [view, previous, video] of [[localView, previousLocal, localVideo], [remoteView, previousRemote, remoteVideo]]) {
      view.element.style.cssText = 'width:100%;height:100%;position:absolute;inset:0';
      (previous ? previous.element : video).replaceWith(view.element);
      if (previous) previous.detach();
    }
    localVideo = localView.videoElement;
    remoteVideo = remoteView.videoElement;
    localVideo.muted = true;
    await rtClient.setStateListener(state => {
      log('XMax: ' + state.connectionState);
      
if (state.reason?.kind === 'failure') {
  const error = state.reason.error;
  const message = error?.message || 'Unknown WebRTC failure';

  console.error('XMax connection failure', {
    code: error?.code,
    message,
    connectionState: state.connectionState,
  });

  window.stopStream().then(() => {
    setStatus('Disconnected: ' + message, 'error');
  });
}
 else if (state.connectionState === sdk.RealtimeConnectionState.generating) {
        remotePh.style.display = 'none';
        setLive(true);
        setStatus('Live · Your look is ready', 'live');
        stopBtn.disabled = false;
        startAllTimers();
        displayCredits = creditsRemaining;
        updateCreditsDisplay();
      }
    });
    rtClient.setRemoteMediaTracksListener(tracks => {
  if (!tracks) return;
  remoteStreamRef = new MediaStream([
    tracks.videoTrack,
    ...(tracks.audioTrack ? [tracks.audioTrack] : []),
  ]);
  window._remoteStream = remoteStreamRef;
  ensureKeepAlive(remoteStreamRef);  // keep tracks alive when main window is minimized
  notifyPopout();
});
    setStatus('Requesting camera…');
    
localStream = await rtClient.createLocalCameraStream({
  videoFormat: new sdk.RealtimeVideoFormat({
    width: 1920,
    height: 1080,
    fps: 30,
  }),
  position: sdk.CameraPosition.front,
  useMicrophone: false,
  enableFrameValidation: true,
});

if (!localStream?.videoTrack) {
  throw new Error("Camera failed to provide a video track");
}

console.log("Camera track ready:", {
  state: localStream.videoTrack.readyState,
  settings: localStream.videoTrack.getSettings?.(),
});

    localView.track = localStream.videoTrack;
    localPh.style.display = 'none';
    referencePath = undefined;
    if (FACE_URL) {
      const file = dataURLtoFile(FACE_URL, 'face.jpg');
      const uploaded = await xmaxClient.createStorageService().uploadImage({data: file, fileName: file.name, contentType: file.type});
      referencePath = uploaded.url;
    }
    setStatus('Bringing your look to life…');
    const remote = await rtClient.startGeneration({
      localStream,
      context: new sdk.RealtimeContext({prompt: promptInput.value.trim() || 'Transform this scene', referencePath}),
    });
    remoteView.track = remote.videoTrack;
    stopBtn.disabled = false;
  } catch(err) {
    log('Error: ' + err.message, 'err');
    setStatus('Failed: ' + err.message, 'error');
    startBtn.disabled = false;
    await window.stopStream();
    setStatus('Failed: ' + err.message, 'error');
  }
};

// ── Stop stream ───────────────────────────────────────────────────────────────
window.stopStream = async function() {
  if (stopping) return;
  stopping = true;
  stopAllTimers();
  const manager = rtClient;
  rtClient = null;
  try { if (manager) await manager.close(); }
  catch (e) { log('Cleanup failed: ' + e.message, 'warn'); }
  localStream = null;
  hideVid(localVideo, localPh);

  if (remoteVideo.srcObject) { try { remoteVideo.pause(); } catch(e) {} }
  if (popoutWin && !popoutWin.closed) {
    try { popoutWin.postMessage('stream-paused', '*'); } catch(e) {}
  }

  setLive(false); rtClient = null;
  setStatus('Session ended · Resume whenever you’re ready');
  stopBtn.disabled = true; startBtn.disabled = false;
  log('XMax stream stopped.');
  stopping = false;
};

// ── Apply prompt ──────────────────────────────────────────────────────────────
window.applyPrompt = async function() {
  if (!rtClient) { log('Start stream first.', 'err'); return; }
  const p = promptInput.value.trim(); if (!p) return;
  try {
    const sdk = await loadSdk();
    await rtClient.startGeneration({localStream, context: new sdk.RealtimeContext({prompt:p, referencePath})});
    log('Prompt: "' + p + '"', 'ok');
  } catch(e) { log('Prompt failed: ' + e.message, 'err'); }
};

// ── Apply face swap ───────────────────────────────────────────────────────────
window.applyFaceSwap = async function() {
  if (!rtClient || !FACE_URL) return;
  try {
    const file = dataURLtoFile(FACE_URL, 'face.jpg');
    const p    = promptInput.value.trim() || 'Transform into this character';
    const sdk = await loadSdk();
    const uploaded = await xmaxClient.createStorageService().uploadImage({data:file, fileName:file.name, contentType:file.type});
    const nextPath = uploaded.url;
    await rtClient.startGeneration({localStream, context:new sdk.RealtimeContext({prompt:p, referencePath:nextPath})});
    referencePath = nextPath;
    log('Face swap applied!', 'ok'); setStatus('🟢 Face swap active!', 'live');
  } catch(e) { log('Face swap failed: ' + e.message, 'err'); }
};

// ── Clear face ────────────────────────────────────────────────────────────────
window.clearFace = async function() {
  if (!rtClient) return;
  try {
    const sdk = await loadSdk();
    await rtClient.startGeneration({localStream, context:new sdk.RealtimeContext({prompt:promptInput.value.trim() || 'Transform this scene'})});
    referencePath = undefined;
    log('Text-only mode.', 'ok');
  }
  catch(e) { log('Failed: ' + e.message, 'err'); }
};

window.addEventListener('pagehide', (e) => {
  // Don't kill the session just because the main window was minimized
  // while the OBS pop-out is still open.
  if (isPopped && popoutWin && !popoutWin.closed) return;
  stopAllTimers();
  if (rtClient) rtClient.close().catch(() => {});
});

document.getElementById('promptInput').addEventListener('keydown', e => { if (e.key==='Enter') window.applyPrompt(); });
window.startStream(); // Automatically connect with the selected face.
</script>
</body>
</html>''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
        title: const Text('Live studio',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          if (_creditsRemaining != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Time — prominent
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.timer_rounded,
                              color: AppColors.accent, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            CreditDisplay.toTime(_creditsRemaining!),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      // Credits — tiny secondary
                      Text(
                        '${_creditsRemaining!.toStringAsFixed(0)} cr',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Restart studio',
            onPressed: _loading ? null : _refreshToken,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
            SizedBox(height: 16),
            Text('Preparing your studio…',
                style: TextStyle(color: AppColors.textSecondary)),
            SizedBox(height: 6),
            Text('Your selected face will be applied automatically',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Container(
          padding: AppLayout.padding(context),
          margin: const EdgeInsets.all(48),
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.error.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.error, size: 48),
              const SizedBox(height: 16),
              const Text('Streaming Error',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(
                      color: AppColors.textSecondary, height: 1.6),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Try Again',
                icon: Icons.refresh_rounded,
                onPressed: _fetchAndLaunch,
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: AppLayout.padding(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: AppColors.successDim,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.open_in_browser_rounded,
                    color: AppColors.success, size: 48),
              ),
              const SizedBox(height: 24),
              const Text('Your studio is ready',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center),
              const SizedBox(height: 10),
              const Text(
                'Allow camera access in your browser. Your live look starts automatically.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 14, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              if (_port != null)
                GestureDetector(
                  onTap: _copyUrl,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.link_rounded,
                            size: 14, color: AppColors.accent),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text('http://127.0.0.1:$_port',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600))),
                        const SizedBox(width: 10),
                        const Text('Copy',
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _infoRow(
                        'Selected look',
                        widget.faceImageBase64 != null
                            ? 'Applied automatically'
                            : 'Creative mode'),
                    const SizedBox(height: 8),
                    _infoRow(
                        'Time remaining',
                        _creditsRemaining != null
                            ? CreditDisplay.toTime(_creditsRemaining!,
                                modelType: 'realtime')
                            : '–'),
                    if (_expiresAt != null) ...[
                      const SizedBox(height: 8),
                      _infoRow('Expires', _expiresAt!),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              AdaptiveRow(
                breakpoint: 520,
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openInBrowser,
                      icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                      label: const Text('Reopen Browser'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _refreshToken,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Restart studio'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => context.go('/dashboard'),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Return to dashboard'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.accentDim,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.accent.withOpacity(0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.tips_and_updates_rounded,
                        color: AppColors.accent, size: 16),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Keep camifyai open while you stream. '
                        'Your browser handles the camera and your live output.',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return AdaptiveRow(
      breakpoint: 400,
      children: [
        Text(label,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const Spacer(),
        Text(value,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace')),
      ],
    );
  }
}
