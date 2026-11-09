const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const args = process.argv.slice(2);
const argument = name => {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : '';
};
const port = Number(argument('--port') || process.env.PORT) || 3000;
const host = argument('--host') || '127.0.0.1';
const allowed = new Set(['index.html', 'style.css', 'product.css', 'endorsement-logo.png', 'app.js', 'config.js']);
const types = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.png': 'image/png'
};

function runtimeConfig() {
  const publicConfig = JSON.parse(fs.readFileSync(path.join(__dirname, 'portal.config.json'), 'utf8'));
  return Buffer.from(`window.PORTAL_CONFIG=Object.freeze(${JSON.stringify({
    supabaseUrl: process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL || publicConfig.supabaseUrl || '',
    supabasePublishableKey: process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY || publicConfig.supabasePublishableKey || ''
  })});\n`);
}

const server = http.createServer((req, res) => {
  if (!['GET', 'HEAD'].includes(req.method)) {
    res.writeHead(405);
    return res.end();
  }

  let name;
  try {
    name = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\//, '') || 'index.html';
  } catch {
    res.writeHead(400);
    return res.end('Invalid URL');
  }

  if (!allowed.has(name)) {
    res.writeHead(404);
    return res.end('Not found');
  }

  if (name === 'config.js') {
    const data = runtimeConfig();
    res.writeHead(200, { 'Content-Type': types['.js'], 'Cache-Control': 'no-store', 'Content-Length': data.length });
    return res.end(req.method === 'HEAD' ? undefined : data);
  }

  fs.readFile(path.join(__dirname, name), (error, data) => {
    if (error) {
      res.writeHead(500);
      return res.end('File could not be read');
    }
    res.writeHead(200, {
      'Content-Type': types[path.extname(name)],
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      'Content-Length': data.length
    });
    res.end(req.method === 'HEAD' ? undefined : data);
  });
});

server.on('error', error => {
  console.error(error.code === 'EADDRINUSE' ? `Port ${port} is busy. Choose another PORT.` : error.message);
  process.exitCode = 1;
});

server.listen(port, host, () => {
  console.log(`Impact portal: http://${host}:${port}\nPress Ctrl+C to stop.`);
});
