const { app, BrowserWindow, shell } = require('electron');
const http = require('http');
const path = require('path');
const fs = require('fs');

const WEB_ROOT = path.resolve(__dirname, '..', 'build', 'web');

// Osiris (OSINT) site. When the app navigates the window here the whole
// browser content swaps to this external origin, so we inject a floating
// "back to Waflo" button in the top-left corner to get home again.
const OSIRIS_URL_PREFIX = 'https://osirisai.live';

// Fixed port so the app always runs on the SAME origin (127.0.0.1:57127).
// Supabase stores its anonymous session in browser storage keyed by origin,
// so a stable port means the signed-in anonymous user (and therefore the
// chat history) survives relaunches. Falls back to an ephemeral port if the
// fixed one is busy.
const FIXED_PORT = 57127;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.webp': 'image/webp',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.wasm': 'application/wasm',
  '.map': 'application/json',
  '.txt': 'text/plain; charset=utf-8',
};

function serve(filePath, res) {
  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end('Not found');
      return;
    }
    const ext = path.extname(filePath).toLowerCase();
    res.writeHead(200, {
      'Content-Type': MIME[ext] || 'application/octet-stream',
      'Cache-Control': 'no-cache',
    });
    res.end(data);
  });
}

function startServer() {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      try {
        const url = new URL(req.url, 'http://127.0.0.1');
        let pathname = decodeURIComponent(url.pathname);
        if (pathname.endsWith('/')) {
          pathname += 'index.html';
        }
        let filePath = path.normalize(path.join(WEB_ROOT, pathname));
        if (!filePath.startsWith(WEB_ROOT)) {
          res.writeHead(403);
          res.end('Forbidden');
          return;
        }
        fs.stat(filePath, (err, stat) => {
          if (!err && stat.isFile()) {
            serve(filePath, res);
          } else {
            serve(path.join(WEB_ROOT, 'index.html'), res);
          }
        });
      } catch (e) {
        res.writeHead(500);
        res.end('Internal error');
      }
    });
    server.once('error', (err) => {
      if (err.code === 'EADDRINUSE') {
        server.listen(0, '127.0.0.1', () => resolve(server));
      } else {
        resolve(server);
      }
    });
    server.listen(FIXED_PORT, '127.0.0.1', () => resolve(server));
  });
}

let win = null;

function grantPermissions(w) {
  w.webContents.session.setPermissionRequestHandler((webContents, permission, callback) => {
    const allowed = [
      'clipboard-read',
      'clipboard-write',
      'clipboard-sanitized-write',
      'media',
      'notifications',
    ];
    callback(allowed.includes(permission));
  });
}

function createWindow(entryUrl) {
  win = new BrowserWindow({
    width: 1280,
    height: 840,
    minWidth: 1000,
    minHeight: 700,
    backgroundColor: '#191A1A',
    title: 'Waflo',
    show: false,
    autoHideMenuBar: true,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      spellcheck: false,
    },
  });
  win.setMenuBarVisibility(false);
  win.setTitle('Waflo');
  grantPermissions(win);
  win.once('ready-to-show', () => win.show());
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      shell.openExternal(url);
    }
    return { action: 'deny' };
  });

  // When the window navigates to the external Osiris / OSINT site, inject a
  // top-left "back to Waflo" button since the Flutter UI is no longer present.
  // Re-injected on every in-page navigation (the site is a SPA). Left on the
  // bare protocol prefix (no path) so both http/https and any path match.
  const onNavigate = () => {
    const currentUrl = win.webContents.getURL();
    if (currentUrl.startsWith(OSIRIS_URL_PREFIX)) {
      win.webContents.executeJavaScript(
        `(function () {
          var existing = document.getElementById('waflo-back-button');
          if (existing) return;
          var btn = document.createElement('button');
          btn.id = 'waflo-back-button';
          btn.textContent = '\u2190  Waflo';
          btn.style.cssText = 'position:fixed;top:16px;left:16px;z-index:2147483647;' +
            'padding:10px 18px;border:none;border-radius:10px;cursor:pointer;' +
            'background:#191A1A;color:#ffffff;font:600 14px/1 "Segoe UI",system-ui,sans-serif;' +
            'box-shadow:0 4px 18px rgba(0,0,0,0.45);display:flex;align-items:center;gap:8px;';
          var arr = document.createElement('span');
          arr.textContent = '\u25C0';
          arr.style.fontSize = '11px';
          btn.prepend(arr);
          btn.addEventListener('click', function () {
            window.location.href = '${entryUrl}';
          });
          document.documentElement.appendChild(btn);
        })();`,
        true
      );
    }
  };
  win.webContents.on('did-navigate', onNavigate);
  win.webContents.on('did-navigate-in-page', onNavigate);

  win.loadURL(entryUrl);
  win.on('closed', () => {
    win = null;
  });
}

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.setName('Waflo');
  app.on('second-instance', () => {
    if (win) {
      if (win.isMinimized()) win.restore();
      win.show();
      win.focus();
    }
  });
  app.whenReady().then(async () => {
    const server = await startServer();
    const port = server.address().port;
    const entryUrl = `http://127.0.0.1:${port}/`;
    createWindow(entryUrl);
    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) {
        createWindow(entryUrl);
      }
    });
  });
}

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});