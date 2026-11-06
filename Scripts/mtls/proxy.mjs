// Local mTLS gateway for testing the client certificate flow without a real setup.
// It terminates TLS, demands a client certificate signed by the dev CA, then forwards
// every request to an upstream NextExplorer server (the demo instance by default).
//
//   node proxy.mjs [upstream] [port] [mode]
//   HOST=0.0.0.0 node proxy.mjs ...   also listen on the LAN (default: this Mac only)
//
// mode: "require" (default) rejects the handshake without a valid certificate,
//       "optional" asks for one but lets anonymous clients through,
//       "off" serves plain TLS with no certificate request at all,
//       "nginx" behaves like nginx ssl_verify_client on: the handshake always completes and a
//       missing or untrusted certificate gets nginx's 400 page instead.
import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(here, 'out');
const upstream = new URL(process.argv[2] ?? 'https://nextexplorer.phillipmaizza.com');
const port = Number(process.argv[3] ?? 8443);
const mode = process.argv[4] ?? 'require';
const client = upstream.protocol === 'https:' ? https : http;

const server = https.createServer(
  {
    key: fs.readFileSync(path.join(out, 'server.key')),
    cert: fs.readFileSync(path.join(out, 'server.pem')),
    ca: fs.readFileSync(path.join(out, 'ca.pem')),
    requestCert: mode !== 'off',
    rejectUnauthorized: mode === 'require',
  },
  (req, res) => {
    if (mode === 'nginx' && !req.socket.authorized) {
      const presented = Object.keys(req.socket.getPeerCertificate() ?? {}).length > 0;
      const title = presented ? '400 The SSL certificate error' : '400 No required SSL certificate was sent';
      console.log(`${title} ${req.method} ${req.url}`);
      res.writeHead(400, { 'content-type': 'text/html' });
      res.end(`<html><head><title>${title}</title></head><body><center><h1>400 Bad Request</h1></center>`
        + `<center>${title.slice(4)}</center><hr><center>nginx</center></body></html>`);
      return;
    }
    const peer = req.socket.getPeerCertificate();
    const who = req.socket.authorized ? peer.subject?.CN : 'anonymous';
    const headers = { ...req.headers, host: upstream.host };
    if (headers.origin) headers.origin = upstream.origin;
    if (headers.referer) headers.referer = upstream.origin + '/';
    const forward = client.request(
      { protocol: upstream.protocol, hostname: upstream.hostname, port: upstream.port || undefined,
        method: req.method, path: req.url, headers },
      (upstreamRes) => {
        const outHeaders = { ...upstreamRes.headers };
        if (outHeaders['set-cookie']) {
          outHeaders['set-cookie'] = outHeaders['set-cookie'].map((c) => c.replace(/;\s*domain=[^;]+/i, ''));
        }
        if (outHeaders.location?.startsWith(upstream.origin)) {
          outHeaders.location = outHeaders.location.replace(upstream.origin, `https://${req.headers.host}`);
        }
        console.log(`${upstreamRes.statusCode} ${req.method} ${req.url} [${who}]`);
        res.writeHead(upstreamRes.statusCode, outHeaders);
        upstreamRes.pipe(res);
      },
    );
    forward.on('error', (error) => {
      console.error(`upstream error: ${error.message}`);
      if (!res.headersSent) res.writeHead(502);
      res.end();
    });
    req.pipe(forward);
  },
);

server.on('tlsClientError', (error, socket) => {
  console.log(`handshake rejected from ${socket.remoteAddress}: ${error.code ?? error.message}`);
});

const host = process.env.HOST ?? '127.0.0.1';
server.listen(port, host, () => {
  console.log(`mTLS proxy (${mode}) on https://${host}:${port} -> ${upstream.origin}`);
});
