// Local mTLS gateway for testing the client certificate flow without a real setup.
// It terminates TLS, demands a client certificate signed by the dev CA, then forwards
// every request to an upstream NextExplorer server (the demo instance by default).
//
//   node proxy.mjs [upstream] [port] [mode]
//
// mode: "require" (default) rejects the handshake without a valid certificate,
//       "optional" asks for one but lets anonymous clients through,
//       "off" serves plain TLS with no certificate request at all.
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

server.listen(port, '0.0.0.0', () => {
  console.log(`mTLS proxy (${mode}) on https://localhost:${port} -> ${upstream.origin}`);
});
