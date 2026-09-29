// Run with sharp available through NODE_PATH. Source PNGs remain as originals.
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');

async function main() {
  const directory = path.resolve(__dirname, '../assets/achievements');
  let originalBytes = 0;
  let optimizedBytes = 0;
  for (const name of await fs.readdir(directory)) {
    if (!name.endsWith('.png') || name.startsWith('badge_')) continue;
    const source = path.join(directory, name);
    const output = source.replace(/\.png$/, '.webp');
    // Badges render at up to 96 logical pixels: 384 covers 4x displays.
    const encoded = await sharp(source)
      .resize({width: 384, height: 384, fit: 'inside', withoutEnlargement: true})
      .webp({quality: 80, alphaQuality: 100, effort: 6}).toBuffer();
    const decoded = await sharp(encoded).metadata();
    if (decoded.width > 384 || decoded.height > 384 || encoded.length > 100000) {
      throw new Error(`Badge exceeds size budget: ${name}`);
    }
    const size = (await fs.stat(source)).size;
    if (encoded.length >= size) throw new Error(`No saving: ${name}`);
    await fs.writeFile(output, encoded);
    originalBytes += size;
    optimizedBytes += encoded.length;
    console.log(`${name}: ${size} -> ${encoded.length}, ${decoded.width}x${decoded.height}`);
  }
  console.log(JSON.stringify({originalBytes, optimizedBytes, savedBytes: originalBytes - optimizedBytes}));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
