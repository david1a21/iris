/* Iris iOS 外壳适配层：只在 WKWebView 里注入，页面本身不动
   - 把「造 a 标签 + click」的导出接成原生存档（iOS 上 blob 下载会静默失败）
   - 补安全区（页面用了 viewport-fit=cover 但没有 env()）
   - 放宽系统选择器对 .cube / .heic 的过滤
   - 三道闸，避免页面初始化时的临时图片被当成用户导出写进相册            */
(function () {
  if (window.__irisIOSBridge) return;
  window.__irisIOSBridge = true;

  var H = (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.iris) || null;
  if (!H) return;

  /* ---------- 1) 手势闸 ---------- */
  var BOOT_AT = Date.now();
  var BOOT_GRACE = 2500;
  var LAST_GESTURE = -1e9;

  function mark(ev) {
    if (ev && ev.isTrusted === false) return;
    LAST_GESTURE = Date.now();
  }
  ['pointerdown', 'touchstart', 'mousedown', 'keydown'].forEach(function (t) {
    window.addEventListener(t, mark, true);
  });

  /* ---------- 2) 记录页面造过的 Blob ---------- */
  var blobs = new Map();
  var _create = URL.createObjectURL;
  URL.createObjectURL = function (obj) {
    var u = _create.apply(URL, arguments);
    try { if (obj instanceof Blob) blobs.set(u, obj); } catch (e) {}
    return u;
  };
  var _revoke = URL.revokeObjectURL;
  URL.revokeObjectURL = function (u) {
    try { setTimeout(function () { blobs.delete(u); }, 8000); } catch (e) {}
    return _revoke.apply(URL, arguments);
  };

  var OK_EXT = {
    png: 1, jpg: 1, jpeg: 1, webp: 1, gif: 1, heic: 1,
    mp4: 1, m4v: 1, mov: 1, zip: 1, json: 1, cube: 1
  };

  function extOf(name) {
    var m = /\.([a-z0-9]{2,5})(?=$|\?)/i.exec(name || '');
    return m ? m[1].toLowerCase() : '';
  }

  function allowed(name, blob) {
    if (Date.now() - LAST_GESTURE > 1500) return false;
    if (!blob || blob.size < 64) return false;
    var e = extOf(name);
    if (e && !OK_EXT[e]) return false;
    var t = blob.type || '';
    if (t && !/^(image\/|video\/|application\/zip|application\/json|text\/plain)/.test(t)) return false;
    return true;
  }

  function send(obj) {
    try { H.postMessage(obj); } catch (e) {}
  }

  /* ---------- 3) 分块传原生：32KB 一块 ---------- */
  function save(name, blob) {
    return new Promise(function (resolve) {
      send({ op: 'begin', name: String(name || ''), mime: blob.type || 'application/octet-stream' });
      var STEP = 32768;
      var pos = 0;
      var dead = false;

      function next() {
        if (dead) return;
        if (pos >= blob.size) {
          send({ op: 'end', name: String(name || '') });
          resolve(true);
          return;
        }
        var end = Math.min(pos + STEP, blob.size);
        var reader = new FileReader();
        reader.onload = function () {
          var s = String(reader.result || '');
          var i = s.indexOf(',');
          send({ op: 'chunk', b64: i >= 0 ? s.slice(i + 1) : s });
          pos = end;
          next();
        };
        reader.onerror = function () { dead = true; resolve(false); };
        reader.readAsDataURL(blob.slice(pos, end));
      }
      next();
    });
  }

  function intercept(link) {
    if (Date.now() - BOOT_AT < BOOT_GRACE) return false;

    var href = link.href || '';
    var name = link.getAttribute('download') || link.download || ('Iris_' + Date.now() + '.png');

    var blob = blobs.get(href);
    if (blob) {
      if (!allowed(name, blob)) return false;
      save(name, blob);
      return true;
    }
    if (href.indexOf('blob:') === 0) {
      fetch(href).then(function (r) { return r.blob(); })
        .then(function (b) { if (allowed(name, b)) save(name, b); })
        .catch(function () {});
      return true;
    }
    return false;
  }

  var _click = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    try {
      if (this.hasAttribute('download') && intercept(this)) return;
    } catch (e) {}
    return _click.apply(this, arguments);
  };

  window.addEventListener('click', function (ev) {
    var el = ev.target;
    while (el && el.tagName !== 'A') el = el.parentElement;
    if (!el || !el.hasAttribute('download')) return;
    if (intercept(el)) ev.preventDefault();
  }, true);

  /* ---------- 4) 界面补丁：安全区 / 选择器 ---------- */
  function patchUI() {
    try {
      var s = document.createElement('style');
      s.id = 'iris-ios-patch';
      s.textContent = [
        '.topbar{padding-top:calc(env(safe-area-inset-top,0px) + 9px) !important}',
        '.dock{padding-bottom:env(safe-area-inset-bottom,0px) !important}',
        'html,body{overscroll-behavior:none}',
        'img{-webkit-user-drag:none}'
      ].join('');
      (document.head || document.documentElement).appendChild(s);

      var photo = document.getElementById('file');
      if (photo) photo.setAttribute('accept', 'image/*,video/*');
      var cube = document.getElementById('cubeFile');
      if (cube) cube.setAttribute('accept', '*/*');
      var json = document.getElementById('jsonFile');
      if (json) json.setAttribute('accept', '.json,application/json,text/plain,*/*');
    } catch (e) {}
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', patchUI);
  } else {
    patchUI();
  }
})();
