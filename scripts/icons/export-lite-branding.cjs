// Re-export the approved E1 PNG masters into the existing platform entry points.
// Requires sharp (or SHARP_MODULE pointing to its installed module).
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require(process.env.SHARP_MODULE || 'sharp');
const root = path.resolve(__dirname, '../..');
const panel = path.join(root, 'src_assets/common/sunshine-control-panel');
const masters = path.join(panel, 'assets/branding/e1');
const images = path.join(panel, 'webui/public/images');

async function png(source, size) {
  return sharp(path.join(masters, `${source}.png`))
    .resize(size, size, { fit: 'contain', background: '#00000000' }).png().toBuffer();
}
async function save(file, bytes) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file, bytes);
}
function svgImage(bytes, size = 256) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}"><image width="${size}" height="${size}" href="data:image/png;base64,${bytes.toString('base64')}"/></svg>\n`;
}
async function icns() {
  const frames = [];
  for (const [type, size] of [['ic07', 128], ['ic08', 256], ['ic09', 512], ['ic10', 1024]]) {
    const image = await png('symbol', size);
    const header = Buffer.alloc(8);
    header.write(type); header.writeUInt32BE(image.length + 8, 4);
    frames.push(header, image);
  }
  const header = Buffer.alloc(8);
  header.write('icns'); header.writeUInt32BE(8 + frames.reduce((total, frame) => total + frame.length, 0), 4);
  return Buffer.concat([header, ...frames]);
}
async function bitmap(file, width, height, background) {
  const logo = await sharp(path.join(masters, 'symbol.png')).resize(width, height, { fit: 'contain', background }).flatten({ background }).removeAlpha().raw().toBuffer();
  const stride = Math.ceil(width * 3 / 4) * 4;
  const result = Buffer.alloc(54 + stride * height);
  result.write('BM'); result.writeUInt32LE(result.length, 2); result.writeUInt32LE(54, 10);
  result.writeUInt32LE(40, 14); result.writeInt32LE(width, 18); result.writeInt32LE(height, 22);
  result.writeUInt16LE(1, 26); result.writeUInt16LE(24, 28); result.writeUInt32LE(stride * height, 34);
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const input = (y * width + x) * 3;
    const output = 54 + (height - 1 - y) * stride + x * 3;
    result[output] = logo[input + 2]; result[output + 1] = logo[input + 1]; result[output + 2] = logo[input];
  }
  await save(file, result);
}
async function main() {
  const tray = await png('tray', 256);
  await save(path.join(images, 'logo-sunshine-256.png'), tray);
  await save(path.join(panel, 'src/assets/logo-sunshine-256.png'), tray);
  await fs.copyFile(path.join(masters, 'symbol.ico'), path.join(panel, 'src/assets/sunshine.ico'));
  await fs.copyFile(path.join(masters, 'symbol.ico'), path.join(panel, 'src-tauri/icons/icon.ico'));
  for (const [file, size] of [['32x32.png', 32], ['128x128.png', 128], ['128x128@2x.png', 256]]) {
    await save(path.join(panel, 'src-tauri/icons', file), await png('symbol', size));
  }
  const macIcon = await icns();
  await save(path.join(panel, 'src-tauri/icons/icon.icns'), macIcon);
  await save(path.join(root, 'assets/brand/sunshine.icns'), macIcon);
  await save(path.join(root, 'assets/brand/sunshine.png'), await png('symbol', 1024));
  await save(path.join(root, 'assets/brand/sunshine.svg'), svgImage(await png('symbol', 512), 512));
  await fs.copyFile(path.join(masters, 'symbol.ico'), path.join(root, 'assets/brand/sunshine.ico'));
  for (const state of ['', '-playing', '-pausing', '-locked', '-offline']) {
    const name = `sunshine${state}`;
    const source = `tray${state}`;
    await fs.copyFile(path.join(masters, `${source}.ico`), path.join(images, `${name}.ico`));
    await fs.copyFile(path.join(masters, `${source}.ico`), path.join(panel, 'src-tauri/icons/tray', `${name}.ico`));
    if (state !== '-offline') {
      await save(path.join(images, `${name}.svg`), svgImage(await png(source, 256)));
      await save(path.join(images, `${name}-16.png`), await png(source, 16));
    }
  }
  // Keep the complete wordmark in Vite's module graph instead of adding a new
  // unauthenticated image-serving route to the core server.
  await fs.copyFile(path.join(masters, 'logo.png'), path.join(panel, 'src/assets/sunshine-lite-logo.png'));
  for (const file of ['welcome.bmp', 'wizard_small.bmp']) {
    const target = path.join(root, 'assets/installer', file);
    const existing = await fs.readFile(target);
    await bitmap(target, existing.readInt32LE(18), Math.abs(existing.readInt32LE(22)), '#fffbf8');
  }
  for (const dark of [false, true]) {
    const background = dark ? '#242020' : '#fffbf8';
    const foreground = dark ? '#f6e8df' : '#40312c';
    const mark = await png('symbol', 300);
    const banner = `<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="340"><rect width="1600" height="340" fill="${background}"/><text x="70" y="150" font-family="Segoe UI, sans-serif" font-size="67" font-weight="600" fill="${foreground}">Foundation Sunshine Lite</text><text x="74" y="215" font-family="Segoe UI, sans-serif" font-size="26" fill="${foreground}">Game streaming · HDR · Virtual display</text><image x="1240" y="20" width="300" height="300" href="data:image/png;base64,${mark.toString('base64')}"/></svg>`;
    await sharp(Buffer.from(banner)).png().toFile(path.join(root, 'assets/readme', dark ? 'hero-dark.png' : 'hero.png'));
  }
  console.log('Exported E1 WebUI, core/desktop, notification/tray, installer, README and platform icons.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
