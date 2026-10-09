// Dependency-free local preview server. Vercel uses the static dist build instead.
const http=require('node:http');
const fs=require('node:fs');
const path=require('node:path');
const port=Number(process.env.PORT)||3000;
const allowed=new Set(['index.html','style.css','maxis-logo.png','brand.js','data.js','store.js','app.js','demo-lesson.mp4','demo-lesson.vtt']);
const types={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.mp4':'video/mp4','.vtt':'text/vtt; charset=utf-8','.png':'image/png'};
const server=http.createServer((req,res)=>{
  if(!['GET','HEAD'].includes(req.method)){res.writeHead(405);return res.end();}
  let name;
  try{name=decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\//,'')||'index.html';}catch{res.writeHead(400);return res.end('Invalid URL');}
  if(!allowed.has(name)){res.writeHead(404);return res.end('Not found');}
  fs.readFile(path.join(__dirname,name),(err,data)=>{
    if(err){res.writeHead(500);return res.end('File could not be read');}
    const headers={'Content-Type':types[path.extname(name)],'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Accept-Ranges':'bytes'};
    const range=req.headers.range;
    if(range){
      const match=/^bytes=(\d*)-(\d*)$/.exec(range);
      let start,end;
      if(match){start=match[1]?Number(match[1]):Math.max(0,data.length-Number(match[2]));end=match[1]&&match[2]?Number(match[2]):data.length-1;}
      if(!match||start>=data.length||end<start||(!match[1]&&!match[2])){res.writeHead(416,{'Content-Range':`bytes */${data.length}`});return res.end();}
      end=Math.min(end,data.length-1);
      res.writeHead(206,{...headers,'Content-Range':`bytes ${start}-${end}/${data.length}`,'Content-Length':end-start+1});return res.end(req.method==='HEAD'?undefined:data.subarray(start,end+1));
    }
    res.writeHead(200,{...headers,'Content-Length':data.length});res.end(req.method==='HEAD'?undefined:data);
  });
});
server.on('error',err=>{console.error(err.code==='EADDRINUSE'?`Port ${port} is busy. Close the existing server or choose another PORT.`:err.message);process.exitCode=1;});
server.listen(port,'127.0.0.1',()=>console.log(`Maxis prototype: http://localhost:${port}\nPress Ctrl+C to stop.`));
