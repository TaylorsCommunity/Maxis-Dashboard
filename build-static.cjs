const fs = require('node:fs');
const path = require('node:path');

const root = __dirname;
const output = path.join(root, 'dist');
const assets = [
  'index.html',
  'style.css',
  'product.css',
  'endorsement-logo.png',
  'app.js'
];

fs.rmSync(output, { recursive: true, force: true });
fs.mkdirSync(output, { recursive: true });

for (const asset of assets) {
  const source = path.join(root, asset);
  if (!fs.existsSync(source)) throw new Error(`Missing production asset: ${asset}`);
  fs.copyFileSync(source, path.join(output, asset));
}

const publicConfig = JSON.parse(fs.readFileSync(path.join(root, 'portal.config.json'), 'utf8'));
const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || publicConfig.supabaseUrl || '';
const publishableKey = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY || publicConfig.supabasePublishableKey || '';
const runtimeConfig = `window.PORTAL_CONFIG=Object.freeze(${JSON.stringify({
  supabaseUrl,
  supabasePublishableKey: publishableKey
})});\n`;
fs.writeFileSync(path.join(output, 'config.js'), runtimeConfig);

if (!supabaseUrl || !publishableKey) console.warn('Supabase public configuration is incomplete.');

console.log(`Production site ready in dist (${assets.length + 1} files).`);
