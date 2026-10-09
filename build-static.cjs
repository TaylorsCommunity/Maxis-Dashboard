// Creates the static output that Vercel serves. No dependencies required.
const fs = require('node:fs');
const path = require('node:path');

const root = __dirname;
const output = path.join(root, 'dist');
const assets = [
  'index.html',
  'style.css',
  'maxis-logo.png',
  'brand.js',
  'data.js',
  'store.js',
  'app.js',
  'demo-lesson.mp4',
  'demo-lesson.vtt'
];

fs.rmSync(output, { recursive: true, force: true });
fs.mkdirSync(output, { recursive: true });

for (const asset of assets) {
  const source = path.join(root, asset);
  if (!fs.existsSync(source)) throw new Error(`Missing static asset: ${asset}`);
  fs.copyFileSync(source, path.join(output, asset));
}

console.log(`Static site ready in dist (${assets.length} files).`);
