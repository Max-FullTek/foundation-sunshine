import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { resolve } from 'node:path'
const panel = fileURLToPath(new URL('../src_assets/common/sunshine-control-panel/', import.meta.url))
const [command, ...args] = process.argv.slice(2)
const env = { ...process.env }
if (!env.SUNSHINE_WEBUI_OUT_DIR) env.SUNSHINE_WEBUI_OUT_DIR = resolve(process.env.SUNSHINE_ASSETS_DIR || 'build', 'assets/web')
const npmCli = process.env.npm_execpath
if (!npmCli) throw new Error('Run this entry through an npm script')
const result = spawnSync(process.execPath, [npmCli, 'run', command, '--', ...args], { cwd: panel, env, stdio: 'inherit' })
if (result.error) throw result.error
process.exit(result.status ?? 1)
