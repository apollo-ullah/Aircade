import { createServer } from 'node:http';
import { readFile, access } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, join } from 'node:path';
import { chromium } from 'playwright';

export const directory = fileURLToPath(new URL('.', import.meta.url));
export const root = resolve(directory, '../..');
export const model = 'gpt-6-astra';
export const viewport = { width: 1024, height: 720 };

export async function apiKey() {
  if (process.env.OPENAI_API_KEY?.trim()) return process.env.OPENAI_API_KEY.trim();
  // Parse only the requested variable; never source/execute the credentials file.
  let text = '';
  try { text = await readFile(join(root, '.env'), 'utf8'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
  const line = text.match(/^\s*(?:export\s+)?OPENAI_API_KEY\s*=\s*(.*?)\s*$/m)?.[1];
  if (!line) return null;
  if (line.startsWith('"') || line.startsWith("'")) {
    const end = line.indexOf(line[0], 1);
    if (end < 0) throw new Error('OPENAI_API_KEY has an unclosed quote in .env');
    return line.slice(1, end).trim() || null;
  }
  return line.split(/\s+#/)[0].trim() || null;
}

export async function startSurface() {
  const html = await readFile(join(directory, 'index.html'));
  const image = await readFile(join(directory, 'court.png'));
  const server = createServer((req, res) => {
    const path = new URL(req.url, 'http://localhost').pathname;
    if (req.method !== 'GET' || !['/', '/court.png'].includes(path)) { res.writeHead(404);res.end();return; }
    res.writeHead(200, { 'Content-Type':path === '/' ? 'text/html; charset=utf-8':'image/png',
      'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff',
      'Content-Security-Policy': "default-src 'none'; img-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'none'; frame-ancestors 'none'" });
    res.end(path === '/' ? html : image);
  });
  await new Promise((yes,no)=>{ server.once('error',no);server.listen(0,'127.0.0.1',yes); });
  const url = `http://127.0.0.1:${server.address().port}/`;
  return { url, close:()=>new Promise(resolve=>server.close(resolve)) };
}

export async function launchBrowser(url, headed = false) {
  const chrome = process.env.AIRCADE_CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  const exists = await access(chrome).then(()=>true,()=>false);
  const browser = await chromium.launch({ headless:!headed, ...(exists ? {executablePath:chrome} : {}) });
  try {
    const context=await browser.newContext({viewport,deviceScaleFactor:1});
    // The model-controlled browser may load only this local game surface.
    await context.route('**/*',route=> new URL(route.request().url()).origin === new URL(url).origin ? route.continue() : route.abort());
    const page=await context.newPage();
    page.on('popup',popup=>void popup.close());
    await page.goto(url);await page.waitForFunction(()=>window.probe?.loaded());
    return {browser,page};
  } catch (error) { await browser.close();throw error; }
}

export function validateActions(actions) {
  if (!Array.isArray(actions) || actions.length>12) throw new Error('Invalid or excessive action batch');
  for (const a of actions) {
    if (!a || !['move','click','screenshot','wait'].includes(a.type)) throw new Error(`Unsupported action: ${a?.type}`);
    if (['move','click'].includes(a.type) && (!Number.isFinite(a.x)||!Number.isFinite(a.y)||a.x<0||a.y<86||a.x>=viewport.width||a.y>=626)) throw new Error('Pointer action outside the court');
    if (a.type==='click' && a.button!=='left') throw new Error('Only left-click is supported by the Phase 0 surface');
  }
  return actions;
}

export async function executeActions(page,actions) {
  // Validate the whole batch before executing any input.
  validateActions(actions);
  for (const a of actions) {
    if (a.type==='move') await page.mouse.move(a.x,a.y);
    if (a.type==='click') await page.mouse.click(a.x,a.y,{button:'left'});
    if (a.type==='wait') await new Promise(resolve=>setTimeout(resolve,250));
  }
}

export async function executeComputerCall(page,call,screenshotPath) {
  if(call.pending_safety_checks?.length) throw new Error('Computer-use safety check requires review; probe stopped.');
  if(!call.call_id) throw new Error('Computer call missing call_id');
  const actions=call.actions || (call.action?[call.action]:[]);
  if(!actions.length) throw new Error('Computer call contains no actions');
  await executeActions(page,actions);
  const executedAt=performance.now();
  const screenshot=await page.screenshot(screenshotPath?{path:screenshotPath}:{});
  return { actions,executedAt,observedAt:performance.now(),
    result:await page.evaluate(()=>window.probe.result()),
    output:{type:'computer_call_output',call_id:call.call_id,output:{
      type:'computer_screenshot',image_url:`data:image/png;base64,${screenshot.toString('base64')}`,detail:'original'
    }} };
}

export function requestBody(input, previous) {
  return { model, reasoning:{effort:'low'}, tools:[{type:'computer'}],
    max_output_tokens:1536, input, ...(previous ? {previous_response_id:previous}: {}) };
}

export async function request(key,body) {
  const response=await fetch('https://api.openai.com/v1/responses',{
    method:'POST', headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},
    body:JSON.stringify(body),signal:AbortSignal.timeout(45000)
  });
  if (!response.ok) {
    // Never print provider bodies, headers or request content: only status and a code.
    let code='request_failed';try { const payload=await response.json();code=String(payload.error?.code||payload.error?.type||code).replace(/[^a-zA-Z0-9_-]/g,'').slice(0,80); } catch {}
    throw new Error(`OpenAI HTTP ${response.status} (${code})`);
  }
  const result=await response.json();
  if (result.status!=='completed') throw new Error(`OpenAI response status: ${result.status}`);
  if (!result.model?.startsWith(model)) throw new Error('Unexpected response model');
  return result;
}

export function tokenEstimate(usage) {
  if (!usage || !Number.isFinite(usage.input_tokens) || !Number.isFinite(usage.output_tokens)) return null;
  const cached=usage.input_tokens_details?.cached_tokens||0;
  // Standard short-context rates checked 2026-09-19. Estimate only, not a billing receipt.
  return ((usage.input_tokens-cached)*10+cached+usage.output_tokens*50)/1e6;
}

export function summarize(values) {
  if (!values.length) return null;
  const sorted=[...values].sort((a,b)=>a-b);
  const mid=Math.floor(sorted.length/2);
  return { count:sorted.length,median:sorted.length%2?sorted[mid]:(sorted[mid-1]+sorted[mid])/2,p95:sorted[Math.ceil(sorted.length*.95)-1],min:sorted[0],max:sorted.at(-1) };
}
