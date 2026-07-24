/**
 * Carte 3D texturee (WebGL, sans librairie).
 *
 * Construit une plaque en volume : face avant = la photo prise, face arriere =
 * une fiche generee au vol (espece, etat, entretien), tranches en couleur.
 * On la fait tourner au doigt / a la souris, avec inertie et rotation lente
 * quand on ne touche a rien.
 *
 * Utilisation : PlantCard3D.mount(canvas, photoDataUrl, data)  -> handle.destroy()
 */
(function (global) {
  'use strict';

  /* ---------------- petites maths 4x4 (colonnes, comme WebGL) ---------------- */

  function identity() {
    return new Float32Array([1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]);
  }

  function multiply(a, b) {
    const out = new Float32Array(16);
    for (let c = 0; c < 4; c++) {
      for (let r = 0; r < 4; r++) {
        out[c * 4 + r] =
          a[0 * 4 + r] * b[c * 4 + 0] +
          a[1 * 4 + r] * b[c * 4 + 1] +
          a[2 * 4 + r] * b[c * 4 + 2] +
          a[3 * 4 + r] * b[c * 4 + 3];
      }
    }
    return out;
  }

  function perspective(fovyRad, aspect, near, far) {
    const f = 1 / Math.tan(fovyRad / 2);
    const out = new Float32Array(16);
    out[0] = f / aspect;
    out[5] = f;
    out[10] = (far + near) / (near - far);
    out[11] = -1;
    out[14] = (2 * far * near) / (near - far);
    return out;
  }

  function translation(x, y, z) {
    const m = identity();
    m[12] = x; m[13] = y; m[14] = z;
    return m;
  }

  function rotationX(a) {
    const m = identity(), c = Math.cos(a), s = Math.sin(a);
    m[5] = c; m[6] = s; m[9] = -s; m[10] = c;
    return m;
  }

  function rotationY(a) {
    const m = identity(), c = Math.cos(a), s = Math.sin(a);
    m[0] = c; m[2] = -s; m[8] = s; m[10] = c;
    return m;
  }

  /* ---------------- shaders ---------------- */

  const VERT = [
    'attribute vec3 a_pos;',
    'attribute vec2 a_uv;',
    'attribute vec3 a_normal;',
    'uniform mat4 u_mvp;',
    'uniform mat4 u_model;',
    'varying vec2 v_uv;',
    'varying vec3 v_normal;',
    'void main() {',
    '  v_uv = a_uv;',
    '  v_normal = mat3(u_model) * a_normal;',
    '  gl_Position = u_mvp * vec4(a_pos, 1.0);',
    '}',
  ].join('\n');

  const FRAG = [
    'precision mediump float;',
    'uniform sampler2D u_tex;',
    'uniform float u_useTex;',
    'uniform vec3 u_color;',
    'varying vec2 v_uv;',
    'varying vec3 v_normal;',
    'void main() {',
    '  vec3 base = mix(u_color, texture2D(u_tex, v_uv).rgb, u_useTex);',
    '  vec3 light = normalize(vec3(0.35, 0.55, 0.85));',
    '  vec3 n = normalize(v_normal);',
    '  float diff = max(dot(n, light), 0.0);',
    '  float spec = pow(diff, 26.0) * 0.22;',
    '  gl_FragColor = vec4(base * (0.58 + 0.52 * diff) + spec, 1.0);',
    '}',
  ].join('\n');

  function compile(gl, type, src) {
    const sh = gl.createShader(type);
    gl.shaderSource(sh, src);
    gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
      throw new Error('shader: ' + gl.getShaderInfoLog(sh));
    }
    return sh;
  }

  /* ---------------- fiche du dos, dessinee en 2D puis plaquee ---------------- */

  const SANTE_COULEUR = {
    bonne: '#4ade80',
    moyenne: '#fbbf24',
    mauvaise: '#f87171',
    inconnu: '#8fae9c',
  };

  function buildInfoTexture(data, aspect) {
    const W = 700;
    const H = Math.max(420, Math.min(1400, Math.round(W / aspect)));
    const cv = document.createElement('canvas');
    cv.width = W;
    cv.height = H;
    const ctx = cv.getContext('2d');

    const grad = ctx.createLinearGradient(0, 0, 0, H);
    grad.addColorStop(0, '#1b3325');
    grad.addColorStop(1, '#0d1912');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, W, H);

    const pad = Math.round(W * 0.075);
    const accent = SANTE_COULEUR[data.etat_sante] || SANTE_COULEUR.inconnu;

    ctx.fillStyle = accent;
    ctx.fillRect(0, 0, W, 10);

    let y = pad + 46;
    ctx.fillStyle = '#e6f2e9';
    ctx.font = 'bold 46px -apple-system, "Segoe UI", Roboto, sans-serif';
    y = wrap(ctx, data.espece || 'Inconnue', pad, y, W - pad * 2, 52, 2);

    ctx.fillStyle = '#8fae9c';
    ctx.font = 'italic 27px -apple-system, "Segoe UI", Roboto, sans-serif';
    y = wrap(ctx, data.nom_latin || '', pad, y + 34, W - pad * 2, 32, 1);

    // pastille etat de sante
    y += 40;
    const label = 'Santé : ' + (data.etat_sante || 'inconnu');
    ctx.font = 'bold 26px -apple-system, "Segoe UI", Roboto, sans-serif';
    const pw = ctx.measureText(label).width + 34;
    roundRect(ctx, pad, y - 28, pw, 42, 21);
    ctx.fillStyle = accent;
    ctx.fill();
    ctx.fillStyle = '#05210f';
    ctx.fillText(label, pad + 17, y);

    const conf = (data.confiance != null ? data.confiance : '?') + '%';
    ctx.font = '24px -apple-system, "Segoe UI", Roboto, sans-serif';
    ctx.fillStyle = '#8fae9c';
    ctx.fillText('confiance ' + conf, pad + pw + 18, y);

    // lignes d'entretien
    const e = data.entretien || {};
    const lignes = [
      ['Lumière', e.lumiere],
      ['Arrosage', e.arrosage],
      ['Sol', e.sol],
      ['Température', e.temperature],
    ];

    y += 54;
    lignes.forEach((ligne) => {
      if (!ligne[1] || y > H - pad) return;
      ctx.fillStyle = '#5d7a68';
      ctx.font = 'bold 21px -apple-system, "Segoe UI", Roboto, sans-serif';
      ctx.fillText(ligne[0].toUpperCase(), pad, y);
      ctx.fillStyle = '#c5d9cc';
      ctx.font = '25px -apple-system, "Segoe UI", Roboto, sans-serif';
      y = wrap(ctx, ligne[1], pad, y + 30, W - pad * 2, 30, 2) + 22;
    });

    const nb = (data.problemes || []).length;
    if (y < H - pad - 20) {
      ctx.fillStyle = nb ? accent : '#4ade80';
      ctx.font = 'bold 24px -apple-system, "Segoe UI", Roboto, sans-serif';
      ctx.fillText(nb ? nb + ' problème' + (nb > 1 ? 's' : '') + ' détecté' + (nb > 1 ? 's' : '') : 'Aucun problème détecté', pad, H - pad);
    }

    return cv;
  }

  function wrap(ctx, text, x, y, maxWidth, lineHeight, maxLines) {
    const mots = String(text).split(' ');
    let ligne = '';
    let lignes = 0;
    for (let i = 0; i < mots.length; i++) {
      const test = ligne ? ligne + ' ' + mots[i] : mots[i];
      if (ctx.measureText(test).width > maxWidth && ligne) {
        ctx.fillText(ligne, x, y);
        y += lineHeight;
        lignes++;
        ligne = mots[i];
        if (lignes >= maxLines) {
          ctx.fillText(ligne.length > 3 ? ligne.slice(0, 3) + '…' : '…', x, y);
          return y;
        }
      } else {
        ligne = test;
      }
    }
    if (ligne) ctx.fillText(ligne, x, y);
    return y;
  }

  function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }

  /* ---------------- geometrie de la plaque ---------------- */

  function buildBox(halfW, halfH, t) {
    const v = [];
    const idx = [];

    function quad(p0, p1, p2, p3, uv, n) {
      const base = v.length / 8;
      [p0, p1, p2, p3].forEach((p, i) => {
        v.push(p[0], p[1], p[2], uv[i][0], uv[i][1], n[0], n[1], n[2]);
      });
      idx.push(base, base + 1, base + 2, base, base + 2, base + 3);
    }

    const full = [[0, 0], [1, 0], [1, 1], [0, 1]];

    // face avant (photo)
    quad([-halfW, -halfH, t], [halfW, -halfH, t], [halfW, halfH, t], [-halfW, halfH, t], full, [0, 0, 1]);
    const frontCount = 6;

    // face arriere (fiche) : les sommets partent de +halfW pour que la fiche
    // se lise a l'endroit une fois la carte retournee, sinon texte en miroir
    quad([halfW, -halfH, -t], [-halfW, -halfH, -t], [-halfW, halfH, -t], [halfW, halfH, -t], full, [0, 0, -1]);
    const backCount = 6;

    // tranches
    quad([halfW, -halfH, t], [halfW, -halfH, -t], [halfW, halfH, -t], [halfW, halfH, t], full, [1, 0, 0]);
    quad([-halfW, -halfH, -t], [-halfW, -halfH, t], [-halfW, halfH, t], [-halfW, halfH, -t], full, [-1, 0, 0]);
    quad([-halfW, halfH, t], [halfW, halfH, t], [halfW, halfH, -t], [-halfW, halfH, -t], full, [0, 1, 0]);
    quad([-halfW, -halfH, -t], [halfW, -halfH, -t], [halfW, -halfH, t], [-halfW, -halfH, t], full, [0, -1, 0]);

    return {
      vertices: new Float32Array(v),
      indices: new Uint16Array(idx),
      frontOffset: 0,
      frontCount: frontCount,
      backOffset: frontCount,
      backCount: backCount,
      sideOffset: frontCount + backCount,
      sideCount: idx.length - frontCount - backCount,
    };
  }

  /* ---------------- montage ---------------- */

  function mount(canvas, photoUrl, data) {
    const gl =
      canvas.getContext('webgl', { antialias: true, alpha: true }) ||
      canvas.getContext('experimental-webgl', { antialias: true, alpha: true });

    if (!gl) return null;

    const prog = gl.createProgram();
    gl.attachShader(prog, compile(gl, gl.VERTEX_SHADER, VERT));
    gl.attachShader(prog, compile(gl, gl.FRAGMENT_SHADER, FRAG));
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
      throw new Error('link: ' + gl.getProgramInfoLog(prog));
    }
    gl.useProgram(prog);

    const loc = {
      pos: gl.getAttribLocation(prog, 'a_pos'),
      uv: gl.getAttribLocation(prog, 'a_uv'),
      normal: gl.getAttribLocation(prog, 'a_normal'),
      mvp: gl.getUniformLocation(prog, 'u_mvp'),
      model: gl.getUniformLocation(prog, 'u_model'),
      tex: gl.getUniformLocation(prog, 'u_tex'),
      useTex: gl.getUniformLocation(prog, 'u_useTex'),
      color: gl.getUniformLocation(prog, 'u_color'),
    };

    function makeTexture(source) {
      const tex = gl.createTexture();
      gl.bindTexture(gl.TEXTURE_2D, tex);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, source);
      // textures non puissance de 2 -> pas de mipmap, bords clampes
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      return tex;
    }

    let geo = null;
    let vbo = null;
    let ibo = null;
    let photoTex = null;
    let infoTex = null;
    let raf = 0;
    let alive = true;

    // etat de rotation
    let rotY = -0.45;
    let rotX = 0.18;
    let velY = 0;
    let velX = 0;
    let dragging = false;
    let lastX = 0;
    let lastY = 0;
    let lastMove = 0;

    const img = new Image();
    img.onload = () => {
      if (!alive) return;
      const aspect = img.width / img.height;
      const halfH = aspect >= 1 ? 0.85 / aspect : 0.85;
      const halfW = aspect >= 1 ? 0.85 : 0.85 * aspect;

      geo = buildBox(halfW, halfH, 0.035);

      vbo = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
      gl.bufferData(gl.ARRAY_BUFFER, geo.vertices, gl.STATIC_DRAW);

      ibo = gl.createBuffer();
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo);
      gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, geo.indices, gl.STATIC_DRAW);

      photoTex = makeTexture(img);
      infoTex = makeTexture(buildInfoTexture(data, aspect));

      gl.enable(gl.DEPTH_TEST);
      gl.clearColor(0, 0, 0, 0);

      raf = requestAnimationFrame(frame);
    };
    img.onerror = () => { /* pas de carte 3D si la photo ne charge pas */ };
    img.src = photoUrl;

    function resize() {
      const dpr = Math.min(global.devicePixelRatio || 1, 2);
      const w = Math.round(canvas.clientWidth * dpr);
      const h = Math.round(canvas.clientHeight * dpr);
      if (canvas.width !== w || canvas.height !== h) {
        canvas.width = w;
        canvas.height = h;
      }
      gl.viewport(0, 0, canvas.width, canvas.height);
    }

    function drawRange(offset, count, tex, color) {
      if (tex) {
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.uniform1i(loc.tex, 0);
        gl.uniform1f(loc.useTex, 1);
      } else {
        gl.uniform1f(loc.useTex, 0);
        gl.uniform3fv(loc.color, color);
      }
      gl.drawElements(gl.TRIANGLES, count, gl.UNSIGNED_SHORT, offset * 2);
    }

    function frame() {
      if (!alive) return;
      resize();

      if (!dragging) {
        // inertie puis rotation d'attente
        velY *= 0.95;
        velX *= 0.9;
        rotY += velY + 0.0035;
        rotX += velX;
        rotX += (0.12 - rotX) * 0.02;
      }
      rotX = Math.max(-1.1, Math.min(1.1, rotX));

      const model = multiply(rotationY(rotY), rotationX(rotX));
      const view = translation(0, 0, -2.75);
      const proj = perspective(
        (38 * Math.PI) / 180,
        canvas.width / Math.max(1, canvas.height),
        0.1,
        50
      );
      const mvp = multiply(proj, multiply(view, model));

      gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
      gl.useProgram(prog);
      gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo);

      const stride = 8 * 4;
      gl.enableVertexAttribArray(loc.pos);
      gl.vertexAttribPointer(loc.pos, 3, gl.FLOAT, false, stride, 0);
      gl.enableVertexAttribArray(loc.uv);
      gl.vertexAttribPointer(loc.uv, 2, gl.FLOAT, false, stride, 12);
      gl.enableVertexAttribArray(loc.normal);
      gl.vertexAttribPointer(loc.normal, 3, gl.FLOAT, false, stride, 20);

      gl.uniformMatrix4fv(loc.mvp, false, mvp);
      gl.uniformMatrix4fv(loc.model, false, model);

      drawRange(geo.sideOffset, geo.sideCount, null, [0.18, 0.32, 0.23]);
      drawRange(geo.frontOffset, geo.frontCount, photoTex, null);
      drawRange(geo.backOffset, geo.backCount, infoTex, null);

      raf = requestAnimationFrame(frame);
    }

    /* -------- interaction -------- */

    function down(e) {
      dragging = true;
      lastX = e.clientX;
      lastY = e.clientY;
      lastMove = Date.now();
      canvas.setPointerCapture && canvas.setPointerCapture(e.pointerId);
    }

    function move(e) {
      if (!dragging) return;
      e.preventDefault();
      const dx = (e.clientX - lastX) / 160;
      const dy = (e.clientY - lastY) / 200;
      rotY += dx;
      rotX += dy;
      velY = dx;
      velX = dy;
      lastX = e.clientX;
      lastY = e.clientY;
      lastMove = Date.now();
    }

    function up() {
      if (!dragging) return;
      dragging = false;
      // relachement immobile -> pas d'inertie parasite
      if (Date.now() - lastMove > 120) { velY = 0; velX = 0; }
    }

    canvas.addEventListener('pointerdown', down);
    canvas.addEventListener('pointermove', move, { passive: false });
    canvas.addEventListener('pointerup', up);
    canvas.addEventListener('pointercancel', up);
    canvas.addEventListener('pointerleave', up);

    return {
      flip: function () { rotY += Math.PI; velY = 0; },
      destroy: function () {
        alive = false;
        cancelAnimationFrame(raf);
        canvas.removeEventListener('pointerdown', down);
        canvas.removeEventListener('pointermove', move);
        canvas.removeEventListener('pointerup', up);
        canvas.removeEventListener('pointercancel', up);
        canvas.removeEventListener('pointerleave', up);
        [photoTex, infoTex].forEach((t) => t && gl.deleteTexture(t));
        vbo && gl.deleteBuffer(vbo);
        ibo && gl.deleteBuffer(ibo);
        gl.deleteProgram(prog);
      },
    };
  }

  global.PlantCard3D = { mount: mount };
})(window);
