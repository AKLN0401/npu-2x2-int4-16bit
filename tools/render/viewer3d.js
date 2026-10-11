// GDS 3D viewer: WebGL2, no libraries. initGds3D(root, meta, opts) builds the canvas + control panel inside root.
// meta.layers[i] = {name, z0, z1, color, count, data}: data = base64(gzip(byte planes of 6 uint16 fields)),
// see gen3d.py encode(). Each trapezoid is drawn as an instanced prism.
function initGds3D(root, META, opts) {
  "use strict";
  opts = opts || {};
  const css = `
  .g3d { position: relative; background: #0d1016; overflow: hidden; color: #e6e8ee;
    font: 12.5px/1.35 "Inter Tight", system-ui, -apple-system, "Segoe UI", sans-serif; }
  .g3d canvas { display: block; width: 100%; height: 100%; }
  .g3d.active canvas { touch-action: none; cursor: grab; }
  .g3d.active canvas:active { cursor: grabbing; }
  .g3d .pnl { position: absolute; top: 10px; left: 10px; background: rgba(16,19,27,.86); border: 1px solid #2a3040;
    border-radius: 8px; padding: 10px 12px; width: 214px; backdrop-filter: blur(6px); }
  .g3d .pnl.min .bd { display: none; }
  .g3d .hd { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; font-weight: 600; }
  .g3d .meta { color: #9aa3b5; font-size: 11.5px; margin: 2px 0 6px; }
  .g3d .ly { display: grid; grid-template-columns: 1fr 1fr; gap: 1px 8px; margin: 4px 0 8px; }
  .g3d .ly label { display: flex; align-items: center; gap: 5px; cursor: pointer; white-space: nowrap; }
  .g3d .ly input { margin: 0; }
  .g3d .sw { width: 9px; height: 9px; border-radius: 2px; flex: none; }
  .g3d .r { display: flex; gap: 5px; flex-wrap: wrap; margin: 5px 0; }
  .g3d button { background: #1d2331; color: #e6e8ee; border: 1px solid #343c50; border-radius: 5px;
    padding: 3px 8px; font: inherit; cursor: pointer; }
  .g3d button:hover { background: #283044; }
  .g3d .lnk { background: none; border: 0; color: #9aa3b5; padding: 0 2px; font-size: 14px; }
  .g3d input[type=range] { width: 100%; margin: 2px 0 0; }
  .g3d .hint { color: #7f889b; font-size: 11px; margin-top: 6px; }
  .g3d .gate { position: absolute; inset: 0; display: flex; align-items: flex-end; justify-content: center;
    padding-bottom: 18px; pointer-events: none; }
  .g3d .gate span { background: rgba(16,19,27,.8); border: 1px solid #343c50; border-radius: 999px; padding: 5px 14px; }
  .g3d.active .gate { display: none; }
  .g3d .msg { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
    color: #c8ccd6; text-align: center; padding: 20px; }
  .g3d .msg img { max-width: 100%; max-height: 100%; }
  .g3d:fullscreen { width: 100vw !important; height: 100vh !important; }`;
  if (!document.getElementById("g3d-css")) {
    const st = document.createElement("style"); st.id = "g3d-css"; st.textContent = css; document.head.appendChild(st);
  }
  root.classList.add("g3d");
  const W = META.w_um, H = META.h_um;
  const canvas = document.createElement("canvas");
  root.appendChild(canvas);
  const gl = canvas.getContext("webgl2", { antialias: true, preserveDrawingBuffer: true });
  if (!gl) {
    const m = document.createElement("div"); m.className = "msg";
    m.innerHTML = opts.poster ? `<img src="${opts.poster}" alt="3D view of the layout">` : "WebGL2 is not available in this browser.";
    root.appendChild(m); return;
  }

  // ---------- shaders ----------
  const VS = `#version 300 es
  in vec3 corner; in vec2 iy; in vec4 ix;
  uniform float grid, z0, z1, zs; uniform mat4 mvp;
  out vec3 wpos; out vec3 cc;
  void main() {
    float y = mix(iy.x, iy.y, corner.y);
    float x = mix(mix(ix.x, ix.y, corner.x), mix(ix.z, ix.w, corner.x), corner.y);
    wpos = vec3(x * grid, y * grid, mix(z0, z1, corner.z) * zs); cc = corner;
    gl_Position = mvp * vec4(wpos, 1.0);
  }`;
  const FS = `#version 300 es
  precision highp float;
  in vec3 wpos; in vec3 cc;
  uniform vec3 color, eye; uniform float outline;
  out vec4 frag;
  void main() {
    vec3 n = normalize(cross(dFdx(wpos), dFdy(wpos)));
    vec3 v = normalize(eye - wpos);
    if (dot(n, v) < 0.0) n = -n;
    vec3 L = normalize(vec3(-0.45, -0.6, 1.0));
    float spec = pow(max(dot(reflect(-L, n), v), 0.0), 24.0);
    vec3 c = color * (0.28 + 0.52 * max(dot(n, L), 0.0) + 0.25 * max(dot(n, v), 0.0)) + vec3(0.18) * spec;
    vec3 fw = fwidth(cc), d = min(cc, 1.0 - cc);
    vec3 px = vec3(fw.x > 1e-6 ? d.x / fw.x : 1e9, fw.y > 1e-6 ? d.y / fw.y : 1e9, fw.z > 1e-6 ? d.z / fw.z : 1e9);
    c *= 1.0 - outline * 0.45 * (1.0 - smoothstep(0.0, 1.2, min(px.x, min(px.y, px.z))));
    frag = vec4(pow(c, vec3(1.0 / 1.15)), 1.0);
  }`;
  function sh(type, src) {
    const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
    return s;
  }
  const prog = gl.createProgram();
  gl.attachShader(prog, sh(gl.VERTEX_SHADER, VS)); gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, FS));
  gl.linkProgram(prog);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog));
  const U = {};
  for (const n of ["grid", "z0", "z1", "zs", "mvp", "color", "eye", "outline"]) U[n] = gl.getUniformLocation(prog, n);
  const A = { corner: gl.getAttribLocation(prog, "corner"), iy: gl.getAttribLocation(prog, "iy"), ix: gl.getAttribLocation(prog, "ix") };
  const cornerBuf = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, cornerBuf);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([0,0,0, 1,0,0, 1,1,0, 0,1,0, 0,0,1, 1,0,1, 1,1,1, 0,1,1]), gl.STATIC_DRAW);
  const idxBuf = gl.createBuffer();
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, idxBuf);
  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint8Array([
    0,2,1, 0,3,2, 4,5,6, 4,6,7, 0,1,5, 0,5,4, 1,2,6, 1,6,5, 2,3,7, 2,7,6, 3,0,4, 3,4,7]), gl.STATIC_DRAW);

  // ---------- data ----------
  async function inflate(b64) {
    const s = new Blob([unb64(b64)]).stream().pipeThrough(new DecompressionStream("gzip"));
    return new Uint8Array(await new Response(s).arrayBuffer());
  }
  function decode(b, n) {   // byte planes -> interleaved y1, y2, xbl, xbr, xtl, xtr
    const f = (k, i) => b[2 * k * n + i] | (b[2 * k * n + n + i] << 8);
    const sg = v => (v >= 32768 ? v - 65536 : v);
    const out = new Uint16Array(6 * n);
    let y1 = 0, xbl = 0;
    for (let i = 0; i < n; i++) {
      const d0 = f(0, i), same = i > 0 && d0 === 0;
      y1 = i === 0 ? d0 : y1 + d0;
      xbl = same ? xbl + f(2, i) : f(2, i);
      const xbr = xbl + f(3, i);
      out.set([y1, y1 + f(1, i), xbl, xbr, xbl + sg(f(4, i)), xbr + sg(f(5, i))], 6 * i);
    }
    return out;
  }
  function hex(c) { return [1, 3, 5].map(i => Math.pow(parseInt(c.substr(i, 2), 16) / 255, 1.15)); }
  const layers = META.layers.map(L => ({ ...L, rgb: hex(L.color), on: true, vao: null }));
  function upload(L, arr) {
    const vao = gl.createVertexArray(); gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, cornerBuf);
    gl.enableVertexAttribArray(A.corner); gl.vertexAttribPointer(A.corner, 3, gl.FLOAT, false, 0, 0);
    const ib = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, ib); gl.bufferData(gl.ARRAY_BUFFER, arr, gl.STATIC_DRAW);
    gl.enableVertexAttribArray(A.iy); gl.vertexAttribPointer(A.iy, 2, gl.UNSIGNED_SHORT, false, 12, 0); gl.vertexAttribDivisor(A.iy, 1);
    gl.enableVertexAttribArray(A.ix); gl.vertexAttribPointer(A.ix, 4, gl.UNSIGNED_SHORT, false, 12, 4); gl.vertexAttribDivisor(A.ix, 1);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, idxBuf);
    gl.bindVertexArray(null);
    L.vao = vao;
  }
  function unb64(b64) {
    const bin = atob(b64), u = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
    return u;
  }
  async function load() {
    for (const L of layers) {
      // META.raw: planes not gzipped (screenshot builds: everything is drawn before the load event)
      upload(L, decode(META.raw ? unb64(L.data) : await inflate(L.data), L.count));
      if (!META.raw) redraw();
    }
  }

  // ---------- camera ----------
  const cam = { yaw: 0, pitch: 0, dist: 0, tx: 0, ty: 0, tz: 0 };
  let zs = opts.z || 4, outline = 1;
  const VIEWS = {
    iso:   () => Object.assign(cam, { yaw: -0.55, pitch: 0.66, dist: 1.55 * Math.max(W, H), tx: W / 2, ty: H * 0.47, tz: 0 }),
    top:   () => Object.assign(cam, { yaw: 0, pitch: Math.PI / 2 - 0.001, dist: 1.45 * Math.max(W, H * 1.6), tx: W / 2, ty: H / 2, tz: 0 }),
    close: () => Object.assign(cam, { yaw: -0.7, pitch: 0.62, dist: 0.32 * Math.max(W, H), tx: W * 0.36, ty: H * 0.42, tz: 1 }),
  };
  function mul(a, b) {
    const r = new Float32Array(16);
    for (let i = 0; i < 4; i++) for (let j = 0; j < 4; j++) {
      let s = 0; for (let k = 0; k < 4; k++) s += a[k * 4 + j] * b[i * 4 + k]; r[i * 4 + j] = s;
    }
    return r;
  }
  function eyePos() {
    const cp = Math.cos(cam.pitch);
    return [cam.tx + cam.dist * cp * Math.sin(cam.yaw), cam.ty - cam.dist * cp * Math.cos(cam.yaw), cam.tz + cam.dist * Math.sin(cam.pitch)];
  }
  function view(e) {
    let f = [cam.tx - e[0], cam.ty - e[1], cam.tz - e[2]]; const fl = Math.hypot(...f); f = f.map(v => v / fl);
    let s = [f[1], -f[0], 0]; const sl = Math.hypot(...s) || 1; s = s.map(v => v / sl);   // f × (0,0,1)
    const u = [s[1] * f[2] - s[2] * f[1], s[2] * f[0] - s[0] * f[2], s[0] * f[1] - s[1] * f[0]];
    return new Float32Array([s[0], u[0], -f[0], 0, s[1], u[1], -f[1], 0, s[2], u[2], -f[2], 0,
      -(s[0] * e[0] + s[1] * e[1] + s[2] * e[2]), -(u[0] * e[0] + u[1] * e[1] + u[2] * e[2]), f[0] * e[0] + f[1] * e[1] + f[2] * e[2], 1]);
  }
  function proj(aspect) {
    const t = 1 / Math.tan(20 * Math.PI / 180), n = Math.max(cam.dist * 0.02, 0.05), f = cam.dist * 4 + 400;
    return new Float32Array([t / aspect, 0, 0, 0, 0, t, 0, 0, 0, 0, (f + n) / (n - f), -1, 0, 0, 2 * f * n / (n - f), 0]);
  }

  // ---------- draw ----------
  let pending = false;
  function draw() {
    pending = false;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const w = Math.max(1, Math.round(canvas.clientWidth * dpr)), h = Math.max(1, Math.round(canvas.clientHeight * dpr));
    if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
    gl.viewport(0, 0, w, h);
    gl.clearColor(0.051, 0.063, 0.086, 1); gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    gl.enable(gl.DEPTH_TEST);
    const e = eyePos();
    gl.useProgram(prog);
    gl.uniformMatrix4fv(U.mvp, false, mul(proj(w / h), view(e)));
    gl.uniform3fv(U.eye, e);
    gl.uniform1f(U.grid, META.grid_um); gl.uniform1f(U.zs, zs); gl.uniform1f(U.outline, outline);
    for (const L of layers) {
      if (!L.on || !L.vao) continue;
      gl.uniform1f(U.z0, L.z0); gl.uniform1f(U.z1, L.z1); gl.uniform3fv(U.color, L.rgb);
      gl.bindVertexArray(L.vao);
      gl.drawElementsInstanced(gl.TRIANGLES, 36, gl.UNSIGNED_BYTE, 0, L.count);
    }
    gl.bindVertexArray(null);
    // screenshot builds: a pixel read-back makes headless Firefox present the frame before its capture
    if (META.raw) gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array(4));
  }
  function redraw() { if (!pending) { pending = true; requestAnimationFrame(draw); } }
  new ResizeObserver(redraw).observe(canvas);

  // ---------- input (page scroll stays normal until the viewer is clicked) ----------
  let active = !!opts.active;
  const setActive = a => { active = a; root.classList.toggle("active", a); };
  setActive(active);
  const ptrs = new Map(); let last = null;
  function pan(dx, dy) {
    const k = cam.dist * 0.0016, c = Math.cos(cam.yaw), s = Math.sin(cam.yaw), sp = Math.max(Math.sin(cam.pitch), 0.25);
    cam.tx -= k * (dx * c + dy * s / sp); cam.ty -= k * (dx * s - dy * c / sp);
  }
  canvas.addEventListener("contextmenu", e => { if (active) e.preventDefault(); });
  canvas.addEventListener("pointerdown", e => {
    if (!active) { setActive(true); return; }
    canvas.setPointerCapture(e.pointerId);
    ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY, btn: e.button, shift: e.shiftKey }); last = null;
  });
  canvas.addEventListener("pointermove", e => {
    if (!ptrs.has(e.pointerId)) return;
    const p = ptrs.get(e.pointerId), dx = e.clientX - p.x, dy = e.clientY - p.y;
    if (ptrs.size === 1) {
      if (p.btn === 2 || p.shift || e.shiftKey) pan(dx, dy);
      else { cam.yaw -= dx * 0.006; cam.pitch = Math.min(Math.PI / 2 - 0.001, Math.max(0.03, cam.pitch + dy * 0.006)); }
    }
    p.x = e.clientX; p.y = e.clientY;
    if (ptrs.size === 2) {
      const [a, b] = [...ptrs.values()];
      const cur = { d: Math.hypot(a.x - b.x, a.y - b.y), x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
      if (last) { cam.dist = Math.min(2000, Math.max(2, cam.dist * last.d / Math.max(cur.d, 1))); pan(cur.x - last.x, cur.y - last.y); }
      last = cur;
    }
    redraw();
  });
  const up = e => { ptrs.delete(e.pointerId); last = null; };
  canvas.addEventListener("pointerup", up); canvas.addEventListener("pointercancel", up);
  canvas.addEventListener("wheel", e => {
    if (!active) return;
    e.preventDefault();
    cam.dist = Math.min(2000, Math.max(2, cam.dist * Math.exp(e.deltaY * 0.0012))); redraw();
  }, { passive: false });
  document.addEventListener("pointerdown", e => { if (active && !opts.active && !root.contains(e.target)) setActive(false); });

  // ---------- panel ----------
  const pnl = document.createElement("div"); pnl.className = "pnl";
  const shapes = layers.reduce((s, L) => s + L.count, 0);
  pnl.innerHTML = `<div class="hd"><span>${META.title}</span><span>
      <button class="lnk" data-a="fs" title="Full screen">⤢</button><button class="lnk" data-a="min" title="Hide controls">–</button></span></div>
    <div class="bd"><div class="meta">${W.toFixed(1)} × ${H.toFixed(2)} µm · ${shapes.toLocaleString()} shapes · height ×<span class="zv"></span></div>
    <div class="ly"></div>
    <div class="r"><button data-p="all">All</button><button data-p="metal">Metal</button><button data-p="cells">Cells</button></div>
    <div class="r"><button data-v="iso">Iso</button><button data-v="top">Top</button><button data-v="close">Close-up</button></div>
    <input type="range" min="1" max="16" step="0.5" class="zr" aria-label="Height exaggeration">
    <label style="display:flex;gap:5px;align-items:center;margin-top:3px"><input type="checkbox" class="ol" checked> Outlines</label>
    <div class="hint">Drag: rotate · right/shift-drag, two fingers: pan · wheel/pinch: zoom</div></div>`;
  root.appendChild(pnl);
  const gate = document.createElement("div"); gate.className = "gate"; gate.innerHTML = "<span>Click to interact</span>";
  root.appendChild(gate);
  const lyBox = pnl.querySelector(".ly");
  for (const L of layers) {
    const lab = document.createElement("label");
    lab.innerHTML = `<input type="checkbox" checked><span class="sw" style="background:${L.color}"></span>${L.name}`;
    L.cb = lab.querySelector("input");
    L.cb.addEventListener("change", () => { L.on = L.cb.checked; redraw(); });
    lyBox.appendChild(lab);
  }
  const PRESETS = { all: () => true, metal: n => /^(met|via)/.test(n), cells: n => ["diff", "tap", "poly", "licon", "li1", "mcon"].includes(n) };
  const preset = p => { for (const L of layers) { L.on = PRESETS[p](L.name); L.cb.checked = L.on; } redraw(); };
  pnl.querySelectorAll("[data-p]").forEach(b => b.addEventListener("click", () => preset(b.dataset.p)));
  pnl.querySelectorAll("[data-v]").forEach(b => b.addEventListener("click", () => { VIEWS[b.dataset.v](); redraw(); }));
  const zr = pnl.querySelector(".zr"), zv = pnl.querySelector(".zv");
  zr.addEventListener("input", () => { zs = +zr.value; zv.textContent = zs; redraw(); });
  pnl.querySelector(".ol").addEventListener("change", e => { outline = e.target.checked ? 1 : 0; redraw(); });
  pnl.querySelector('[data-a="min"]').addEventListener("click", e => {
    pnl.classList.toggle("min"); e.target.textContent = pnl.classList.contains("min") ? "+" : "–";
  });
  pnl.querySelector('[data-a="fs"]').addEventListener("click", () => {
    if (document.fullscreenElement) document.exitFullscreen(); else if (root.requestFullscreen) { root.requestFullscreen(); setActive(true); }
  });
  document.addEventListener("fullscreenchange", redraw);

  VIEWS[opts.view in VIEWS ? opts.view : "iso"]();
  if (opts.layers in PRESETS) preset(opts.layers);
  if (opts.panel === false) pnl.style.display = "none";
  zr.value = zs; zv.textContent = zs;
  if (META.raw) { load(); draw(); } else { redraw(); load(); }
}
