// Read-only preview of freshly built Web UI assets. No installed files change.
import http from 'node:http'
import { readFile } from 'node:fs/promises'
import { resolve, extname, sep } from 'node:path'
const root = resolve(process.env.SUNSHINE_ASSETS_DIR || 'build', 'assets/web')
const sample = process.argv.includes('--sample')
const samplePairingStarted = Date.now()
const sampleConfig = { platform:'windows', version:'介面預覽', sunshine_name:'Sunshine Lite 範例主機', locale:'zh_TW', setup_wizard_completed:true, adapters:[], display_devices:[], controller:'enabled', keyboard:'enabled', mouse:'enabled' }
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.ico': 'image/x-icon' }
http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', 'http://127.0.0.1:8080')
  res.setHeader('Access-Control-Allow-Headers', 'X-Log-Offset')
  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return }
  if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405); res.end('Read-only preview'); return }
  try {
    const url = new URL(req.url, 'http://127.0.0.1:8081')
    if (sample && url.pathname === '/connection-preview') {
      const base = new URL('../src_assets/common/sunshine-control-panel/', import.meta.url)
      const [shell, palette, style, markup, script] = await Promise.all([
        'src-tauri/error-404.html', 'src/renderer/shared/palette.css', 'src/renderer/shared/connection-screen.css',
        'src/renderer/shared/connection-screen.html', 'src/renderer/shared/connection-screen.js',
      ].map(path => readFile(new URL(path, base), 'utf8')))
      const controls = `<form id="preview-controls" style="padding:10px 18px;font:14px system-ui;display:flex;gap:16px;flex-wrap:wrap;background:#fff;color:#17212f">
        <label>配色 <select name="theme"><option value="light">淺色</option><option value="dark">深色</option></select></label>
        <label>語系 <select name="locale"><option value="zh_TW">繁體中文</option><option value="zh">简体中文</option><option value="en">English</option></select></label>
        <label>狀態 <select name="phase"><option value="waiting">搜尋中</option><option value="ready">已連線</option><option value="preparing">準備中</option><option value="offline">無法連線</option><option value="mismatch">版本不相容</option></select></label>
        <a href="/config">WebUI 預覽</a><span>僅供預覽，不連接實際主機</span></form>`
      const setup = `
        const params = new URLSearchParams(location.search);
        const controls = document.getElementById('preview-controls');
        for (const key of ['theme','locale','phase']) {
          const value = params.get(key); if (value && [...controls.elements[key].options].some(option => option.value === value)) controls.elements[key].value = value;
        }
        const panel = mountConnectionScreen(document.getElementById('connection-preview'), {autoStart:false,probe:async () => 'waiting',onReady:() => {},theme:controls.theme.value,locale:controls.locale.value,phase:controls.phase.value});
        controls.addEventListener('submit', event => event.preventDefault());
        controls.addEventListener('change', () => {
          panel.setTheme(controls.theme.value); panel.setLocale(controls.locale.value); panel.setState(controls.phase.value);
        });
      `
      const body = shell.replace('/* PALETTE_STYLE */', palette).replace('/* CONNECTION_STYLE */', style)
        .replace('<!-- CONNECTION_MARKUP -->', markup)
        .replace('data-connection-autostart', 'id="connection-preview"')
        .replace('<body>', '<body>' + controls)
        .replace('/* CONNECTION_SCRIPT */', script + setup)
      res.writeHead(200, { 'Content-Type':'text/html; charset=utf-8', 'Cache-Control':'no-store' })
      res.end(body)
      return
    }
    if (url.pathname.startsWith('/api/')) {
      if (sample) {
        const data = url.pathname === '/api/config' ? sampleConfig
          : url.pathname === '/api/configLocale' ? { locale:'zh_TW', has_account: !req.headers.referer?.includes('first-run=1') }
          : url.pathname === '/api/pairing/requests' ? { requests: req.headers.referer?.includes('pairing=waiting') ? [
            { id:'preview-request', name:'Moonlight 範例裝置', address:'192.168.1.20', received_at:samplePairingStarted, remaining_seconds:Math.max(0, 300 - Math.floor((Date.now() - samplePairingStarted) / 1000)) },
          ].filter(request => request.remaining_seconds > 0) : [] }
          : url.pathname === '/api/apps' ? { apps:[
            { name:'Desktop', cmd:'', 'image-path':'desktop' },
            { name:'沒有封面範例', cmd:'example.exe', 'image-path':'', elevated:true, 'auto-detach':true },
          ] }
          : url.pathname === '/api/clients/list' ? { named_certs:[] }
          : url.pathname === '/api/logs' ? '[2026-10-17 00:00:00.000]: Info: Preview sample only' : {}
        res.writeHead(200, { 'Content-Type': typeof data === 'string' ? 'text/plain' : 'application/json' })
        res.end(typeof data === 'string' ? data : JSON.stringify(data))
        return
      }
      const response = await fetch(`http://127.0.0.1:48081${url.pathname}${url.search}`, {
        headers: { 'X-Log-Offset': '0' }, signal: AbortSignal.timeout(5000),
      })
      res.writeHead(response.status, { 'Content-Type': response.headers.get('content-type') || 'text/plain' })
      res.end(Buffer.from(await response.arrayBuffer()))
      return
    }
    if (sample && url.pathname === '/boxart/desktop.png') {
      res.writeHead(200, { 'Content-Type':'image/png' })
      res.end(await readFile(new URL('../src_assets/common/assets/desktop.png', import.meta.url)))
      return
    }
    let path = decodeURIComponent(url.pathname)
    if (path === '/') path = '/index.html'
    else if (!extname(path)) path += '.html'
    const file = resolve(root, `.${path}`)
    if (!file.startsWith(root + sep)) { res.writeHead(403); res.end(); return }
    let body = await readFile(file)
    if (sample && extname(file) === '.html') body = Buffer.from(body.toString().replace('<head>', '<head><script>window.__FOUNDATION_PREVIEW_SAMPLE__ = true</script>'))
    res.writeHead(200, { 'Content-Type': types[extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' })
    res.end(body)
  } catch {
    res.writeHead(502); res.end('Preview asset or local host unavailable')
  }
}).listen(8081, '127.0.0.1', () => console.log('Read-only Web UI preview: http://127.0.0.1:8081'))
