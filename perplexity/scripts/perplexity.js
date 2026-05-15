#!/usr/bin/env node
// Minimal Perplexity AI web client, tokenless.
// Reproduces the basic search/ask path of:
//   https://github.com/mishamyrt/perplexity-web-api-mcp
// (crates/perplexity-web-api/src/{client,config,types,parse}.rs)

const https = require('https');
const { randomUUID } = require('crypto');

const API_HOST = 'www.perplexity.ai';
const ENDPOINT_AUTH_SESSION = '/api/auth/session';
const ENDPOINT_SSE_ASK = '/rest/sse/perplexity_ask';
const API_VERSION = '2.18';
const API_MODE_CONCISE = 'concise';
const MODEL_TURBO = 'turbo';

const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36';

const CHROME_HEADERS = {
  'User-Agent': USER_AGENT,
  'Accept-Language': 'en-US,en;q=0.9',
  'sec-ch-ua': '"Chromium";v="136", "Google Chrome";v="136", "Not.A/Brand";v="99"',
  'sec-ch-ua-mobile': '?0',
  'sec-ch-ua-platform': '"macOS"',
  'sec-fetch-dest': 'empty',
  'sec-fetch-mode': 'cors',
  'sec-fetch-site': 'same-origin',
};

function request(options, body) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () =>
        resolve({
          status: res.statusCode,
          headers: res.headers,
          body: Buffer.concat(chunks).toString('utf8'),
        }),
      );
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}

function parseCookies(setCookieHeader) {
  if (!setCookieHeader) return {};
  const arr = Array.isArray(setCookieHeader) ? setCookieHeader : [setCookieHeader];
  const jar = {};
  for (const line of arr) {
    const first = line.split(';', 1)[0];
    const eq = first.indexOf('=');
    if (eq <= 0) continue;
    jar[first.slice(0, eq).trim()] = first.slice(eq + 1).trim();
  }
  return jar;
}

function cookieHeader(jar) {
  return Object.entries(jar)
    .map(([k, v]) => `${k}=${v}`)
    .join('; ');
}

async function warmupSession() {
  const res = await request({
    method: 'GET',
    host: API_HOST,
    path: ENDPOINT_AUTH_SESSION,
    headers: {
      ...CHROME_HEADERS,
      Accept: '*/*',
      Referer: `https://${API_HOST}/`,
    },
  });
  if (res.status !== 200) {
    throw new Error(`Session warm-up failed: HTTP ${res.status}\n${res.body.slice(0, 500)}`);
  }
  return parseCookies(res.headers['set-cookie']);
}

function buildPayload(query) {
  return JSON.stringify({
    query_str: query,
    params: {
      attachments: [],
      frontend_context_uuid: randomUUID(),
      frontend_uuid: randomUUID(),
      is_incognito: false,
      language: 'en-US',
      mode: API_MODE_CONCISE,
      model_preference: MODEL_TURBO,
      source: 'default',
      sources: ['web'],
      version: API_VERSION,
    },
  });
}

function postSearch(jar, payload) {
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        method: 'POST',
        host: API_HOST,
        path: ENDPOINT_SSE_ASK,
        headers: {
          ...CHROME_HEADERS,
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(payload),
          Accept: 'text/event-stream',
          Origin: `https://${API_HOST}`,
          Referer: `https://${API_HOST}/`,
          Cookie: cookieHeader(jar),
        },
      },
      (res) => {
        if (res.statusCode !== 200) {
          const chunks = [];
          res.on('data', (c) => chunks.push(c));
          res.on('end', () =>
            reject(
              new Error(
                `Search request failed: HTTP ${res.statusCode}\n${Buffer.concat(chunks)
                  .toString('utf8')
                  .slice(0, 500)}`,
              ),
            ),
          );
          return;
        }
        let buffer = '';
        let lastEvent = null;
        res.setEncoding('utf8');
        res.on('data', (chunk) => {
          buffer += chunk;
          let idx;
          while ((idx = buffer.indexOf('\n')) !== -1) {
            const line = buffer.slice(0, idx);
            buffer = buffer.slice(idx + 1);
            if (!line.startsWith('data:')) continue;
            const raw = line.slice(5).trimStart();
            if (!raw) continue;
            let parsed;
            try {
              parsed = JSON.parse(raw);
            } catch {
              continue;
            }
            // Skip the trailing end_of_stream frame ({}). Keep the last
            // event that actually carries content.
            if (parsed && (parsed.text || parsed.answer || parsed.blocks)) {
              lastEvent = parsed;
            }
          }
        });
        res.on('end', () => resolve(lastEvent));
        res.on('error', reject);
      },
    );
    req.on('error', reject);
    req.write(payload);
    req.end();
  });
}

function extractFromEvent(event) {
  if (!event) return { answer: null, web_results: [] };

  let textValue = event.text;
  if (typeof textValue === 'string') {
    try {
      textValue = JSON.parse(textValue);
    } catch {
      textValue = null;
    }
  }

  if (Array.isArray(textValue)) {
    const finalStep = textValue.find((s) => s && s.step_type === 'FINAL');
    const innerStr = finalStep && finalStep.content && finalStep.content.answer;
    if (typeof innerStr === 'string') {
      try {
        const data = JSON.parse(innerStr);
        return {
          answer: typeof data.answer === 'string' ? data.answer : null,
          web_results: Array.isArray(data.web_results) ? data.web_results : [],
        };
      } catch {
        // fall through
      }
    }
  }

  return {
    answer: typeof event.answer === 'string' ? event.answer : null,
    web_results: [],
  };
}

async function main() {
  const [, , mode, ...rest] = process.argv;
  const query = rest.join(' ').trim();
  if (!mode || !query || (mode !== 'search' && mode !== 'ask')) {
    process.stderr.write('Usage: node perplexity.js <search|ask> "<query>"\n');
    process.exit(2);
  }

  const jar = await warmupSession();
  const event = await postSearch(jar, buildPayload(query));
  const { answer, web_results } = extractFromEvent(event);

  if (mode === 'search') {
    process.stdout.write(JSON.stringify({ web_results }, null, 2) + '\n');
  } else {
    process.stdout.write(JSON.stringify({ answer, web_results }, null, 2) + '\n');
  }
}

main().catch((err) => {
  process.stderr.write(`Error: ${err.message}\n`);
  process.exit(1);
});
