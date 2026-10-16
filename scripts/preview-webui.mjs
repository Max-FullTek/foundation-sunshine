// Read-only preview of freshly built Web UI assets. No installed files change.
import http from 'node:http'
import { readFile } from 'node:fs/promises'
import { resolve, extname, sep } from 'node:path'
const root = resolve('build/assets/web')
const sample = process.argv.includes('--sample')
const sampleConfig = { platform:'windows', version:'介面預覽', sunshine_name:'Sunshine Lite 範例主機', locale:'zh_TW', setup_wizard_completed:true, adapters:[], display_devices:[], controller:'enabled', keyboard:'enabled', mouse:'enabled' }
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.webp': 'image/webp', '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.ico': 'image/x-icon' }
http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', 'http://127.0.0.1:8080')
  res.setHeader('Access-Control-Allow-Headers', 'X-Log-Offset')
  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return }
  if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405); res.end('Read-only preview'); return }
  try {
    const url = new URL(req.url, 'http://127.0.0.1:8081')
    if (url.pathname.startsWith('/api/')) {
      if (sample) {
        const data = url.pathname === '/api/config' ? sampleConfig
          : url.pathname === '/api/configLocale' ? { locale:'zh_TW' }
          : url.pathname === '/api/apps' ? { apps:[{ name:'Desktop', cmd:'', 'image-path':'' }] }
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
