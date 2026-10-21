// VR / cinema player for the phone page.
//
// One full-screen shader does all projections: for each pixel it builds the
// view ray (camera rotation from the gyroscope or finger drag), then looks up
// the video either on a sphere (VR180 / VR360, equirectangular) or on a flat
// virtual screen (cinema). In headset mode the canvas is drawn twice, once per
// eye, each sampling its own half of a side-by-side / top-bottom video.
(() => {
  'use strict';

  const VERT = `
attribute vec2 pos;
varying vec2 ndc;
void main() { ndc = pos; gl_Position = vec4(pos, 0.0, 1.0); }`;

  const FRAG = `
precision highp float;
varying vec2 ndc;
uniform sampler2D tex;
uniform mat3 rot;        // world-from-camera
uniform mat3 screenInv;  // screen-from-world (cinema)
uniform vec2 tanHalf;    // tan(fov / 2) horizontally, vertically
uniform float shiftX;    // off-axis shift (eye spacing), in NDC
uniform int proj;        // 0 = 360, 1 = 180, 2 = cinema, 3 = fisheye
uniform vec4 eye;        // this eye's rect in the texture: x, y, w, h (y down)
uniform vec3 screen;     // cinema: half width, half height, distance
uniform float fishHalf;  // fisheye: half the lens angle, radians
uniform vec2 lensK;      // lens correction coefficients k1, k2 (0 = off)
uniform float aspect;    // viewport width / height, keeps the correction circular
const float PI = 3.14159265;

vec4 sampleEye(vec2 uv) { return texture2D(tex, eye.xy + clamp(uv, 0.0, 1.0) * eye.zw); }

void main() {
  // Headset lenses stretch the edges (pincushion); pre-squeeze them (barrel) so lines stay straight
  vec2 n = vec2(ndc.x - shiftX, ndc.y);
  vec2 pr = vec2(n.x * aspect, n.y);
  float r2 = dot(pr, pr) / (aspect * aspect + 1.0);
  n *= 1.0 + lensK.x * r2 + lensK.y * r2 * r2;
  vec3 d = rot * normalize(vec3(n.x * tanHalf.x, n.y * tanHalf.y, -1.0));
  if (proj == 2) {
    vec3 s = screenInv * d;
    if (s.z < -0.001) {
      vec2 p = s.xy * (screen.z / -s.z);
      if (abs(p.x) <= screen.x && abs(p.y) <= screen.y) {
        gl_FragColor = sampleEye(vec2(p.x / screen.x * 0.5 + 0.5, 0.5 - p.y / screen.y * 0.5));
        return;
      }
    }
    // Dark room with a faint floor
    gl_FragColor = vec4(vec3(0.02 + 0.04 * max(0.0, -d.y)), 1.0);
    return;
  }
  if (proj == 3) {
    // Equidistant fisheye: distance from the image centre grows with the angle off forward
    float theta = acos(clamp(-d.z, -1.0, 1.0));
    if (theta > fishHalf) { gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0); return; }
    float len = length(d.xy);
    vec2 dir = len > 1e-5 ? d.xy / len : vec2(0.0);
    float r = 0.5 * theta / fishHalf;
    gl_FragColor = sampleEye(vec2(0.5 + r * dir.x, 0.5 - r * dir.y));
    return;
  }
  float lon = atan(d.x, -d.z);
  float lat = asin(clamp(d.y, -1.0, 1.0));
  float u;
  if (proj == 1) {
    if (abs(lon) > PI * 0.5) { gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0); return; }
    u = lon / PI + 0.5;
  } else {
    u = lon / (2.0 * PI) + 0.5;
  }
  gl_FragColor = sampleEye(vec2(u, 0.5 - lat / PI));
}`;

  // ─── Quaternion / matrix helpers ([x, y, z, w]) ────────────────────────────
  const qMul = (a, b) => [
    a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
    a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
    a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
    a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2],
  ];
  const qAxis = (x, y, z, angle) => { const s = Math.sin(angle / 2); return [x * s, y * s, z * s, Math.cos(angle / 2)]; };
  const qInv = q => [-q[0], -q[1], -q[2], q[3]];
  // Euler 'YXZ' (same as three.js)
  const qEulerYXZ = (x, y, z) => {
    const c1 = Math.cos(x / 2), c2 = Math.cos(y / 2), c3 = Math.cos(z / 2);
    const s1 = Math.sin(x / 2), s2 = Math.sin(y / 2), s3 = Math.sin(z / 2);
    return [
      s1 * c2 * c3 + c1 * s2 * s3,
      c1 * s2 * c3 - s1 * c2 * s3,
      c1 * c2 * s3 - s1 * s2 * c3,
      c1 * c2 * c3 + s1 * s2 * s3,
    ];
  };
  // Column-major mat3 for uniformMatrix3fv
  const qMat3 = ([x, y, z, w]) => new Float32Array([
    1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w),
    2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w),
    2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y),
  ]);
  const qRotate = (q, v) => {
    const m = qMat3(q);
    return [m[0] * v[0] + m[3] * v[1] + m[6] * v[2], m[1] * v[0] + m[4] * v[1] + m[7] * v[2], m[2] * v[0] + m[5] * v[1] + m[8] * v[2]];
  };
  const yawOf = q => { const f = qRotate(q, [0, 0, -1]); return Math.atan2(-f[0], -f[2]); };
  const DEG = Math.PI / 180;
  // Camera looks out of the back of the phone (three.js DeviceOrientationControls)
  const Q_BACK = [-Math.sqrt(0.5), 0, 0, Math.sqrt(0.5)];

  const fmt = s => {
    if (!isFinite(s)) return '--:--';
    s = Math.floor(s);
    const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60;
    return (h ? h + ':' + String(m).padStart(2, '0') : m) + ':' + String(sec).padStart(2, '0');
  };

  const CSS = `
#vrp { position:fixed; z-index:50; background:#000; overflow:hidden; touch-action:none; user-select:none; -webkit-user-select:none; }
#vrp canvas { position:absolute; inset:0; width:100%; height:100%; display:block; }
#vrp .ov { position:absolute; inset:0; display:flex; flex-direction:column; justify-content:space-between; pointer-events:none; transition:opacity .25s; }
#vrp .ov.hide { opacity:0; }
#vrp .ov.hide * { pointer-events:none !important; }
#vrp .row { display:flex; align-items:center; gap:6px; padding:10px 12px; pointer-events:auto; background:linear-gradient(rgba(0,0,0,.75), rgba(0,0,0,0)); }
#vrp .row.bottom { background:linear-gradient(rgba(0,0,0,0), rgba(0,0,0,.8)); }
#vrp button, #vrp select { background:rgba(40,40,40,.9); color:#eee; border:0; border-radius:8px; padding:8px 10px; font:13px -apple-system, system-ui, sans-serif; }
#vrp button.on { background:#a78bfa; color:#111; }
#vrp .t { flex:1; color:#ccc; font:13px -apple-system, system-ui, sans-serif; overflow:hidden; white-space:nowrap; text-overflow:ellipsis; }
#vrp .time { color:#ccc; font:12px ui-monospace, monospace; min-width:92px; text-align:right; }
#vrp input[type=range] { flex:1; accent-color:#a78bfa; }
#vrp .panel { position:absolute; right:12px; top:56px; background:rgba(20,20,20,.95); border-radius:12px; padding:12px; color:#ddd; font:13px -apple-system, system-ui, sans-serif; display:flex; flex-direction:column; gap:10px; min-width:240px; pointer-events:auto; }
#vrp .panel label { display:flex; flex-direction:column; gap:4px; }
#vrp .panel .chk { flex-direction:row; align-items:center; gap:8px; }
#vrp .msg { position:absolute; left:50%; top:50%; transform:translate(-50%,-50%); background:rgba(20,20,20,.95); color:#ddd; padding:16px; border-radius:12px; text-align:center; font:14px -apple-system, system-ui, sans-serif; max-width:80%; pointer-events:auto; display:flex; flex-direction:column; gap:10px; align-items:center; }
#vrp .hint { color:#999; font-size:12px; }
`;

  const LAYOUTS = { mono: 'Mono', sbs: 'Side-by-side', tb: 'Top-bottom' };
  const PROJS = { 180: 'VR 180°', 360: 'VR 360°', f180: 'Fisheye 180°', f190: 'Fisheye 190°', f200: 'Fisheye 200°', cinema: 'Cinema' };
  // 180 / 360 are numbers; cinema and fisheye ('f190') are strings
  const parseProj = v => (v === 'cinema' || String(v).startsWith('f')) ? String(v) : Number(v);
  const CALIB_SIZE = 100; // calibration screen width, degrees
  const prefs = Object.assign({ fov: 95, singleFov: 80, shift: 0, lens: 0, screenSize: 80, follow: false, headset: true },
    JSON.parse(localStorage.getItem('pml_vr_prefs') || '{}'));
  const savePrefs = () => localStorage.setItem('pml_vr_prefs', JSON.stringify(prefs));

  let P = null; // the open player

  function open(opts) {
    close();
    if (!document.getElementById('vrp-css')) {
      const st = document.createElement('style'); st.id = 'vrp-css'; st.textContent = CSS; document.head.appendChild(st);
    }
    const root = document.createElement('div'); root.id = 'vrp';
    root.innerHTML = `
      <canvas></canvas>
      <div class="ov">
        <div class="row top">
          <button data-a="close">✕</button>
          <div class="t"></div>
          <button data-a="prev">‹</button><button data-a="next">›</button>
          <button data-a="eyes"></button>
          <button data-a="rotate" title="Rotate">⟳</button>
          <button data-a="center" title="Recenter">◎</button>
          <button data-a="settings">⚙</button>
        </div>
        <div class="row bottom">
          <button data-a="back">−10</button>
          <button data-a="play">▶</button>
          <button data-a="fwd">+10</button>
          <input type="range" min="0" max="1000" value="0" class="seek">
          <div class="time">0:00 / --:--</div>
        </div>
        <div class="panel hidden-panel" style="display:none">
          <label>Projection <select data-k="proj"></select></label>
          <label>Layout <select data-k="layout"></select></label>
          <label>Field of view <input type="range" min="60" max="120" data-k="fov"></label>
          <label>Eye spacing <input type="range" min="-30" max="30" data-k="shift"></label>
          <label>Lens correction <input type="range" min="0" max="100" data-k="lens"></label>
          <label>Screen size (cinema) <input type="range" min="30" max="130" data-k="screenSize"></label>
          <label class="chk"><input type="checkbox" data-k="follow"> Screen follows head (cinema)</label>
          <button data-a="calib">🎯 Calibrate headset</button>
          <div class="hint" data-k="tracking"></div>
        </div>
      </div>`;
    document.body.appendChild(root);

    const video = document.createElement('video');
    video.playsInline = true; video.setAttribute('playsinline', ''); video.preload = 'auto';
    video.style.cssText = 'position:absolute;width:1px;height:1px;opacity:0;pointer-events:none';
    root.appendChild(video);

    P = {
      opts, root, video,
      canvas: root.querySelector('canvas'),
      ov: root.querySelector('.ov'),
      panel: root.querySelector('.panel'),
      proj: opts.proj, layout: opts.layout,
      rotate: 0,                 // CSS rotation of the player: 0, 90, -90
      orient: null,              // latest deviceorientation reading
      offset: [0, 0, 0, 1],      // recenter rotation
      dragYaw: 0, dragPitch: 0,  // finger look-around when there is no gyro
      needCenter: true,
      raf: 0, hideTimer: 0,
    };
    P.rotate = innerHeight > innerWidth ? 90 : 0;
    root.querySelector('.t').textContent = opts.title || '';

    setupGL();
    bindUI();
    layout();
    startTracking();
    if (opts.calibrate) setCalib(true);
    if (opts.url) {
      video.src = opts.url;
      if (!opts.calibrate) video.play().catch(() => {});
    }
    showOverlay();
    P.raf = requestAnimationFrame(frame);
  }

  function close() {
    if (!P) return;
    cancelAnimationFrame(P.raf);
    clearTimeout(P.hideTimer);
    removeEventListener('deviceorientation', onOrient);
    removeEventListener('resize', layout);
    P.video.pause(); P.video.removeAttribute('src'); P.video.load();
    P.gl?.getExtension('WEBGL_lose_context')?.loseContext();
    P.root.remove();
    const cb = P.opts.onClose; P = null;
    cb?.();
  }

  // ─── WebGL ─────────────────────────────────────────────────────────────────

  function setupGL() {
    const gl = P.canvas.getContext('webgl', { antialias: false, alpha: false, preserveDrawingBuffer: false });
    if (!gl) { message('WebGL is not available on this device.'); return; }
    const sh = (type, src) => {
      const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
      return s;
    };
    const prog = gl.createProgram();
    gl.attachShader(prog, sh(gl.VERTEX_SHADER, VERT));
    gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, FRAG));
    gl.linkProgram(prog);
    gl.useProgram(prog);
    const buf = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(prog, 'pos');
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    // Video sizes are not powers of two: no mipmaps, clamp
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, 1, 1, 0, gl.RGB, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 0]));
    const u = {};
    for (const n of ['tex', 'rot', 'screenInv', 'tanHalf', 'shiftX', 'proj', 'eye', 'screen', 'fishHalf', 'lensK', 'aspect']) u[n] = gl.getUniformLocation(prog, n);
    gl.uniform1i(u.tex, 0);
    Object.assign(P, { gl, u });
  }

  function frame() {
    P.raf = requestAnimationFrame(frame);
    const { gl, u, video, canvas } = P;
    if (!gl) return;
    if (P.calib) {
      if (!P.calibUploaded) {
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, gl.RGB, gl.UNSIGNED_BYTE, P.calibCanvas ||= calibPattern());
        P.calibUploaded = true;
      }
    } else if (video.readyState >= 2) {
      try { gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, gl.RGB, gl.UNSIGNED_BYTE, video); } catch (_) {}
    }
    updateTime();

    const q = cameraQuat();
    gl.uniformMatrix3fv(u.rot, false, qMat3(q));
    const pj = P.proj;
    const proj = pj === 360 ? 0 : pj === 180 ? 1 : pj === 'cinema' ? 2 : 3;
    gl.uniform1i(u.proj, proj);
    if (proj === 3) gl.uniform1f(u.fishHalf, Number(String(pj).slice(1)) * DEG / 2);

    if (proj === 2) {
      // Screen fixed ahead (after recenter), or glued to the view
      // The calibration grid stays fixed in the room so turning your head tests the FOV
      const follow = prefs.follow && !P.calib;
      gl.uniformMatrix3fv(u.screenInv, false, qMat3(follow ? qInv(q) : [0, 0, 0, 1]));
      const dist = 2;
      const halfW = dist * Math.tan((P.calib ? CALIB_SIZE : prefs.screenSize) * DEG / 2);
      gl.uniform3f(u.screen, halfW, halfW / screenAspect(), dist);
    }

    const W = canvas.width, H = canvas.height;
    const rects = eyeRects();
    if (prefs.headset) {
      const vw = Math.floor(W / 2), aspect = vw / H;
      const tx = Math.tan(prefs.fov * DEG / 2);
      gl.uniform2f(u.tanHalf, tx, tx / aspect);
      const k1 = prefs.lens / 100 * 0.6;
      gl.uniform2f(u.lensK, k1, k1 * 0.5);
      gl.uniform1f(u.aspect, aspect);
      for (let i = 0; i < 2; i++) {
        gl.viewport(i * vw, 0, vw, H);
        // Positive spacing pushes each eye's centre outwards
        gl.uniform1f(u.shiftX, (i === 0 ? 1 : -1) * prefs.shift / 100);
        gl.uniform4fv(u.eye, rects[i]);
        gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
      }
    } else {
      gl.viewport(0, 0, W, H);
      gl.uniform2f(u.lensK, 0, 0);
      gl.uniform1f(u.aspect, W / H);
      const ty = Math.tan(prefs.singleFov * DEG / 2);
      gl.uniform2f(u.tanHalf, ty * W / H, ty);
      gl.uniform1f(u.shiftX, 0);
      gl.uniform4fv(u.eye, rects[0]);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    }
  }

  function eyeRects() {
    if (P.layout === 'sbs') return [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1]];
    if (P.layout === 'tb') return [[0, 0, 1, 0.5], [0, 0.5, 1, 0.5]];
    return [[0, 0, 1, 1], [0, 0, 1, 1]];
  }

  /// Width/height of one eye's picture, for the cinema screen.
  function screenAspect() {
    if (P.calib) return 16 / 9;
    const v = P.video, a = v.videoWidth && v.videoHeight ? v.videoWidth / v.videoHeight : 16 / 9;
    if (P.layout === 'sbs') return a >= 3 ? a / 2 : 16 / 9;   // full-width vs half-width 3D
    if (P.layout === 'tb') return a <= 1 ? a * 2 : 16 / 9;
    return a;
  }

  // ─── Orientation ───────────────────────────────────────────────────────────

  function startTracking() {
    addEventListener('resize', layout);
    const DOE = window.DeviceOrientationEvent;
    if (!DOE) return trackingHint('No motion sensor: drag to look around.');
    if (!window.isSecureContext) return trackingHint('Head tracking needs the secure page. Drag to look around for now.');
    if (typeof DOE.requestPermission === 'function') {
      // iOS: must be asked from a tap
      const ask = () => DOE.requestPermission().then(r => {
        if (r === 'granted') { addEventListener('deviceorientation', onOrient); trackingHint('Head tracking on.'); }
        else trackingHint('Motion access denied: drag to look around. (Allow it in Safari settings.)');
      }).catch(() => trackingHint('Motion access failed: drag to look around.'));
      message('Allow motion access for head tracking?', [['Enable', ask], ['Not now', () => trackingHint('Drag to look around.')]]);
    } else {
      addEventListener('deviceorientation', onOrient);
      trackingHint('Head tracking on.');
    }
  }

  function onOrient(e) {
    if (!P || e.alpha == null) return;
    P.orient = e;
  }

  function screenAngle() {
    if (P.rotate) return P.rotate;
    const a = screen.orientation?.angle ?? window.orientation ?? 0;
    return a > 180 ? a - 360 : a;
  }

  function headQuat() {
    const o = P.orient;
    if (!o) return null;
    let q = qEulerYXZ(o.beta * DEG, o.alpha * DEG, -o.gamma * DEG);
    q = qMul(q, Q_BACK);
    return qMul(q, qAxis(0, 0, 1, -screenAngle() * DEG));
  }

  function cameraQuat() {
    const head = headQuat();
    if (!head) return qMul(qAxis(0, 1, 0, P.dragYaw), qAxis(1, 0, 0, P.dragPitch));
    if (P.needCenter) { P.offset = qAxis(0, 1, 0, -yawOf(head)); P.needCenter = false; }
    return qMul(P.offset, head);
  }

  function recenter() {
    P.needCenter = true;
    P.dragYaw = 0; P.dragPitch = 0;
  }

  // ─── Layout & UI ───────────────────────────────────────────────────────────

  /// Sizes the player to the screen, rotated 90° when forced to landscape
  /// (for phones with rotation lock on).
  function layout() {
    if (!P) return;
    const r = P.root.style, W = innerWidth, H = innerHeight;
    r.left = '0'; r.top = '0'; r.transformOrigin = 'top left';
    if (P.rotate === 0) { r.width = W + 'px'; r.height = H + 'px'; r.transform = 'none'; }
    else {
      r.width = H + 'px'; r.height = W + 'px';
      r.transform = P.rotate === 90 ? 'rotate(90deg) translateY(-100%)' : 'rotate(-90deg) translateX(-100%)';
    }
    // Keep the controls clear of the status bar / Dynamic Island and the home
    // indicator. Those sit on the physical top/bottom edges, which become the
    // player's left/right edges when it is rotated.
    const inset = safeInsets(), ov = P.ov.style;
    const side = { 0: ['top', 'bottom'], 90: ['left', 'right'], '-90': ['right', 'left'] }[P.rotate];
    for (const k of ['top', 'right', 'bottom', 'left']) ov['padding' + k[0].toUpperCase() + k.slice(1)] = '0px';
    ov['padding' + side[0][0].toUpperCase() + side[0].slice(1)] = inset.top + 'px';
    ov['padding' + side[1][0].toUpperCase() + side[1].slice(1)] = inset.bottom + 'px';
    if (P.rotate === 0) { ov.paddingLeft = inset.left + 'px'; ov.paddingRight = inset.right + 'px'; }
    ov.boxSizing = 'border-box';

    const dpr = Math.min(devicePixelRatio || 1, 2);
    const cw = P.rotate ? H : W, ch = P.rotate ? W : H;
    P.canvas.width = Math.round(cw * dpr); P.canvas.height = Math.round(ch * dpr);
    P.root.querySelector('[data-a=eyes]').textContent = prefs.headset ? '👓 2 eyes' : '📱 1 view';
    P.root.querySelector('[data-a=rotate]').classList.toggle('on', P.rotate !== 0);
  }

  /// Calibration: a fixed grid with a centre cross and fine text instead of the
  /// video, shown as a cinema screen so focus, lens distance and FOV can be judged.
  function setCalib(on) {
    const r = P.root;
    if (on) {
      P.saved = { proj: P.proj, layout: P.layout };
      P.video.pause();
      P.proj = 'cinema'; P.layout = 'mono';
      P.calibUploaded = false;
      recenter();
    } else if (P.saved) {
      Object.assign(P, P.saved);
      P.calibUploaded = false;
    }
    P.calib = on;
    r.querySelector('.row.bottom').style.visibility = on ? 'hidden' : '';
    r.querySelector('[data-a=calib]').textContent = on ? '✓ Done calibrating' : '🎯 Calibrate headset';
    r.querySelector('.t').textContent = on ? 'Calibration' : (P.opts.title || '');
    r.querySelector('[data-k=proj]').value = String(P.proj);
    r.querySelector('[data-k=layout]').value = P.layout;
  }

  /// Sized so it shows at roughly 1:1 on a phone in the headset (a bigger texture
  /// gets scaled down and thin lines shimmer).
  function calibPattern() {
    const W = 1600, H = 900, cx = W / 2, cy = H / 2, step = 80;
    const c = document.createElement('canvas'); c.width = W; c.height = H;
    const g = c.getContext('2d');
    g.fillStyle = '#141414'; g.fillRect(0, 0, W, H);
    // Grid aligned to the centre: bold and bright enough to judge sharpness
    g.strokeStyle = '#9a9a9a'; g.lineWidth = 3;
    for (let x = cx % step; x <= W; x += step) { g.beginPath(); g.moveTo(x, 0); g.lineTo(x, H); g.stroke(); }
    for (let y = cy % step; y <= H; y += step) { g.beginPath(); g.moveTo(0, y); g.lineTo(W, y); g.stroke(); }
    // Centre cross and rings
    g.strokeStyle = '#a78bfa'; g.lineWidth = 5;
    g.beginPath(); g.moveTo(cx, 0); g.lineTo(cx, H); g.moveTo(0, cy); g.lineTo(W, cy); g.stroke();
    g.lineWidth = 4;
    for (const rad of [60, 160, 280]) { g.beginPath(); g.arc(cx, cy, rad, 0, Math.PI * 2); g.stroke(); }
    g.textAlign = 'center'; g.textBaseline = 'middle';
    const line = (text, size, y, color = '#fff') => {
      g.font = `600 ${size}px -apple-system, system-ui, sans-serif`;
      const w = g.measureText(text).width;
      g.fillStyle = 'rgba(0,0,0,.8)'; g.fillRect(cx - w / 2 - 10, y - size * 0.7, w + 20, size * 1.4);
      g.fillStyle = color; g.fillText(text, cx, y);
    };
    line('HEADSET CALIBRATION', 42, 90, '#c4b5fd');
    line('1. Focus: close one eye, turn that eye\'s knob until this text is sharp. Then the other eye.', 22, 150);
    line('2. Lens distance: both eyes open, turn the top wheel until you see ONE sharp purple cross.', 22, 188);
    line('3. Lines at the sides bend or swim? Raise Lens correction (⚙) until they stay straight.', 22, 682);
    line('4. Turn your head slowly: the grid must stay still. If it slides, change Field of view (⚙).', 22, 720);
    line('5. Still doubled or straining? Adjust Eye spacing (⚙). Tap ◎ to re-centre.', 22, 758);
    line('The quick brown fox jumps over the lazy dog 0123456789', 20, 812, '#ddd');
    line('The quick brown fox jumps over the lazy dog 0123456789', 15, 846, '#bbb');
    return c;
  }

  /// The screen's safe-area insets in CSS pixels (env() is CSS-only, so measure it).
  function safeInsets() {
    const probe = document.createElement('div');
    probe.style.cssText = 'position:fixed;visibility:hidden;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
    document.body.appendChild(probe);
    const cs = getComputedStyle(probe);
    const r = { top: parseFloat(cs.paddingTop) || 0, right: parseFloat(cs.paddingRight) || 0, bottom: parseFloat(cs.paddingBottom) || 0, left: parseFloat(cs.paddingLeft) || 0 };
    probe.remove();
    return r;
  }

  function bindUI() {
    const { root, video, panel } = P;
    const $ = s => root.querySelector(s);
    const act = {
      close,
      prev: () => P.opts.onPrev?.(),
      next: () => P.opts.onNext?.(),
      play: () => (video.paused ? video.play() : video.pause()),
      back: () => { video.currentTime = Math.max(0, video.currentTime - 10); },
      fwd: () => { video.currentTime = Math.min(video.duration || 1e9, video.currentTime + 10); },
      center: recenter,
      eyes: () => { prefs.headset = !prefs.headset; savePrefs(); layout(); },
      rotate: () => { P.rotate = P.rotate === 0 ? 90 : P.rotate === 90 ? -90 : 0; layout(); recenter(); },
      settings: () => { panel.style.display = panel.style.display === 'none' ? 'flex' : 'none'; },
      calib: () => { setCalib(!P.calib); panel.style.display = 'none'; },
    };
    root.querySelectorAll('[data-a]').forEach(b => b.addEventListener('click', e => {
      e.stopPropagation(); act[b.dataset.a](); showOverlay();
    }));
    video.addEventListener('play', () => { $('[data-a=play]').textContent = '❚❚'; showOverlay(); });
    video.addEventListener('pause', () => { $('[data-a=play]').textContent = '▶'; showOverlay(true); });
    video.addEventListener('error', () => message('This video can\'t be played on the phone (format not supported by Safari).'));

    const seek = $('.seek');
    let seeking = false;
    seek.addEventListener('input', () => { seeking = true; showOverlay(); });
    seek.addEventListener('change', () => {
      if (video.duration) video.currentTime = seek.value / 1000 * video.duration;
      seeking = false;
    });
    P.updateSeek = () => { if (!seeking && video.duration) seek.value = Math.round(video.currentTime / video.duration * 1000); };

    // Settings panel
    const fill = (sel, obj, val) => { sel.innerHTML = Object.entries(obj).map(([k, v]) => `<option value="${k}">${v}</option>`).join(''); sel.value = String(val); };
    fill($('[data-k=proj]'), PROJS, P.proj);
    fill($('[data-k=layout]'), LAYOUTS, P.layout);
    $('[data-k=proj]').onchange = e => { P.proj = parseProj(e.target.value); recenter(); };
    $('[data-k=layout]').onchange = e => { P.layout = e.target.value; };
    for (const k of ['fov', 'shift', 'lens', 'screenSize']) {
      const inp = $(`[data-k=${k}]`); inp.value = prefs[k];
      inp.oninput = () => { prefs[k] = Number(inp.value); savePrefs(); };
    }
    const follow = $('[data-k=follow]'); follow.checked = prefs.follow;
    follow.onchange = () => { prefs.follow = follow.checked; savePrefs(); };
    panel.addEventListener('click', e => e.stopPropagation());

    // Tap toggles the controls; drag looks around when there is no gyro
    let start = null;
    root.addEventListener('pointerdown', e => {
      // Only the picture itself; sliders and buttons keep their own gestures
      start = e.target === P.canvas ? { x: e.clientX, y: e.clientY, moved: false } : null;
    });
    root.addEventListener('pointermove', e => {
      if (!start) return;
      let dx = e.clientX - start.x, dy = e.clientY - start.y;
      if (Math.abs(dx) + Math.abs(dy) > 6) start.moved = true;
      if (!start.moved || P.orient) return;
      // Undo the CSS rotation so dragging follows the finger
      if (P.rotate === 90) [dx, dy] = [dy, -dx];
      else if (P.rotate === -90) [dx, dy] = [-dy, dx];
      const k = (prefs.headset ? prefs.fov : prefs.singleFov) * DEG / P.canvas.clientWidth;
      P.dragYaw += dx * k; P.dragPitch = Math.max(-1.5, Math.min(1.5, P.dragPitch + dy * k));
      start.x = e.clientX; start.y = e.clientY;
    });
    root.addEventListener('pointerup', e => {
      if (start && !start.moved) toggleOverlay();
      start = null;
    });
  }

  function updateTime() {
    const v = P.video;
    P.root.querySelector('.time').textContent = fmt(v.currentTime) + ' / ' + fmt(v.duration);
    P.updateSeek?.();
  }

  function showOverlay(stay) {
    P.ov.classList.remove('hide');
    clearTimeout(P.hideTimer);
    if (!stay && !P.video.paused) P.hideTimer = setTimeout(() => {
      if (P && P.panel.style.display === 'none') P.ov.classList.add('hide');
    }, 3000);
  }
  function toggleOverlay() {
    if (P.ov.classList.contains('hide')) showOverlay();
    else { P.ov.classList.add('hide'); P.panel.style.display = 'none'; }
  }

  function trackingHint(text) {
    const el = P?.root.querySelector('[data-k=tracking]');
    if (el) el.textContent = text;
  }

  function message(text, buttons = [['OK', null]]) {
    const box = document.createElement('div'); box.className = 'msg';
    const t = document.createElement('div'); t.textContent = text; box.appendChild(t);
    for (const [label, fn] of buttons) {
      const b = document.createElement('button'); b.textContent = label;
      b.onclick = e => { e.stopPropagation(); box.remove(); fn?.(); };
      box.appendChild(b);
    }
    P.root.appendChild(box);
  }

  window.VRPlayer = { open, close, get isOpen() { return !!P; } };
})();
