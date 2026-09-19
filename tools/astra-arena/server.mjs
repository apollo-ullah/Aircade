import {createServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {chromium} from '../astra-probe/node_modules/playwright/index.mjs';
import {apiKey,requestBody,tokenEstimate,root,model} from '../astra-probe/probe.mjs';

import {gatewayKey,evaluateJev,jevModel} from './jev.mjs';
const provider=process.env.AIRCADE_ARENA_PROVIDER==='jev'?'jev':'astra';
const activeModel=provider==='jev'?jevModel:model;
const token=process.env.AIRCADE_ARENA_TOKEN||randomUUID();
const manual=process.env.AIRCADE_ARENA_MANUAL==='1';
const html=await readFile(new URL('./index.html',import.meta.url));
const traceDir=join(root,'.local','astra-arena',new Date().toISOString().replaceAll(':','-'));
await mkdir(traceDir,{recursive:true});
let lastScreenshot=null,observationID=0,runCalls=0,runCost=0;
let latest=null,commands=[],sequence=0,generation=0,stopped=false,browser,page,abort;
let status={state:manual?'Manual controller':'Waiting for court',latencyMS:0,calls:0,cost:0,lastAction:'No action yet',rejected:0};
const trace=[];
function queueInput(input){
 if(!latest?.meta.playing||input.run!==latest.meta.run||input.rally!==latest.meta.rally||!Number.isFinite(input.x)||!Number.isFinite(input.captured)||!Number.isInteger(input.frame)||input.frame>latest.meta.frame){status.rejected++;return false}
 const command={run:input.run,rally:input.rally,frame:input.frame,sequence:++sequence,x:Math.max(-4.6,Math.min(4.6,input.x)),swing:input.swing===true,captured:input.captured};
 if(!command.swing&&commands.at(-1)?.swing===false)commands.pop();
 commands.push(command);if(commands.length>24)commands.shift();return true;
}

function authenticated(req){return req.headers.authorization===`Bearer ${token}`||req.headers.cookie?.split('; ').includes(`arena=${token}`)}
async function body(req,limit){const chunks=[];let n=0;for await(const c of req){n+=c.length;if(n>limit)throw Error('Body too large');chunks.push(c)}return Buffer.concat(chunks)}
function json(res,value,code=200){res.writeHead(code,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(value))}
const server=createServer(async(req,res)=>{try{
 const url=new URL(req.url,'http://localhost');
 if(url.pathname==='/'&&url.searchParams.get('token')===token){res.writeHead(302,{'Set-Cookie':`arena=${token}; HttpOnly; SameSite=Strict; Path=/`,'Location':'/'});res.end();return}
 if(!authenticated(req)){json(res,{error:'Unauthorized'},401);return}
 if(req.headers.origin&&req.headers.origin!==`http://127.0.0.1:${server.address().port}`){json(res,{error:'Origin'},403);return}
 if(req.method==='GET'&&url.pathname==='/'){res.writeHead(200,{'Content-Type':'text/html','Content-Security-Policy':"default-src 'none'; img-src data:; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'"});res.end(html);return}
 if(req.method==='POST'&&url.pathname==='/frame'){
  const meta=JSON.parse(req.headers['x-aircade-meta']||'{}');const image=await body(req,1500000);
  if(typeof meta.run!=='string'||!Number.isInteger(meta.rally)||!Number.isInteger(meta.frame)||!Number.isFinite(meta.captured))throw Error('Invalid frame');
  if(latest?.meta.run!==meta.run){runCalls=0;runCost=0}
  if(latest&&(latest.meta.run!==meta.run||latest.meta.rally!==meta.rally||latest.meta.playing!==meta.playing)){generation++;commands=[];abort?.abort()}
  latest={meta,image:image.toString('base64'),received:performance.now(),label:meta.playing?'8-second flights · 60-second match':'Match paused'};
  json(res,{ok:true});return;
 }
 if(req.method==='GET'&&url.pathname==='/observation'){json(res,latest);return}
 if(req.method==='GET'&&url.pathname==='/last-observation'){res.writeHead(lastScreenshot?200:404,{'Content-Type':'image/png'});res.end(lastScreenshot);return}
 if(req.method==='GET'&&url.pathname==='/poll'){const batch=commands;commands=[];json(res,{commands:batch,status:{...status,observationID}});return}
 if(req.method==='POST'&&url.pathname==='/input'){
  const input=JSON.parse(await body(req,4096));
  json(res,{accepted:queueInput(input)});return;
 }
 json(res,{error:'Not found'},404);
}catch{json(res,{error:'Invalid arena request'},400)}});
await new Promise((yes,no)=>{server.once('error',no);server.listen(0,'127.0.0.1',yes)});
const url=`http://127.0.0.1:${server.address().port}`;
console.log(JSON.stringify({url,token,manualURL:`${url}/?token=${token}`}));
const pause=ms=>new Promise(r=>setTimeout(r,ms));
const instruction=`You play real live tennis using a browser controller. You see only the rendered court. Your racket is closest to the camera; your opponent is far away. The yellow ball travels for 8 seconds per flight, bouncing before reaching you. Move horizontally along the rail at y=604, x=420..604 to align your racket with the approaching ball. The view is from YOUR baseline: screen-left means left along the rail. The rail is horizontally aligned with the court: move to the same screen x as the ball, anticipating its lateral travel. Each decision takes about 3 seconds. Account for that delay. When the ball is approaching or passing the net, move and click SWING in the SAME batch so your three-second stroke is underway as it reaches you. Click SWING at (942,667) when the ball is approaching your baseline; the stroke moves forward for 3 seconds, then resets. The racket must physically intersect the ball during the stroke. Clicking too early or late misses. You may move the rail then click swing in the same action batch. Never assume a hit. Observe and keep playing continuously until the match ends. Only move, left click, screenshot and wait are supported. The court image itself has no controls. You can act only in the rail or the swing button. Be quick; the simulation continues while you think.`;
async function screenshot(){const frame=latest;await page.evaluate(async f=>{window.arena.freeze(true);await window.arena.show(f)},frame);const png=await page.screenshot();return{frame,png}}
async function loop(){
 const key=await apiKey();if(!key){status.state='Unavailable: OpenAI key missing';return}
 browser=await chromium.launch({headless:true,executablePath:process.env.AIRCADE_CHROME_PATH||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
 const context=await browser.newContext({viewport:{width:1024,height:720}});
 await context.route('**/*',route=>new URL(route.request().url()).origin===url?route.continue():route.abort());
 page=await context.newPage();page.on('popup',p=>void p.close());await page.goto(`${url}/?token=${token}`);
 while(!stopped){
  if(!latest?.meta.playing){status.state=latest?'Waiting for match':'Waiting for court';await pause(100);continue}
  if(status.calls>=200||status.cost>=5){status.state='Session budget reached';break}
  if(runCalls>=40||runCost>=1.5){status.state='Match budget reached';await pause(100);continue}
  const epoch=generation,observed=await screenshot();
  const body=requestBody([{role:'user',content:[{type:'input_text',text:instruction},{type:'input_image',image_url:`data:image/png;base64,${observed.png.toString('base64')}`,detail:'original'}]}]);
  let next=body,source=observed,previous;
  // Keep a short response chain per decision. Discard all chains on rally/session change.
  for(let step=0;step<3&&epoch===generation&&latest?.meta.playing;step++){
   if(runCalls>=40||runCost>=1.5||status.calls>=200||status.cost>=5)break;
   status.state='Thinking';const began=performance.now();abort=new AbortController();
   let result;
   try{
    lastScreenshot=source.png;observationID++;
    status.calls++;runCalls++;
    const response=await fetch('https://api.openai.com/v1/responses',{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify(next),signal:AbortSignal.any([abort.signal,AbortSignal.timeout(20000)])});
    if(!response.ok)throw Error(`OpenAI HTTP ${response.status}`);
    result=await response.json();if(result.status!=='completed'||!result.model?.startsWith(model))throw Error('Incomplete or unexpected model response');
   }catch(e){if(epoch!==generation||stopped)break;status.state=`Unavailable: ${e.name==='TimeoutError'?'request timed out':e.message}`;return}
   status.latencyMS=Math.round(performance.now()-began);const cost=tokenEstimate(result.usage)||0;status.cost+=cost;runCost+=cost;
   if(epoch!==generation||!latest?.meta.playing)break;
   const calls=result.output.filter(x=>x.type==='computer_call');if(!calls.length)break;
   const outputs=[];
   for(const call of calls){
    const actions=call.actions||(call.action?[call.action]:[]);
    if(call.pending_safety_checks?.length||!actions.length||actions.length>12)throw Error('Unsupported computer call');
    // Validate every action before executing the batch; never navigate or type arbitrary data.
    for(const a of actions){if(!['move','click','wait','screenshot'].includes(a.type))throw Error(`Unsupported action ${a.type}`);
     if(['move','click'].includes(a.type)&&(!Number.isFinite(a.x)||!Number.isFinite(a.y)||!((a.x>=420&&a.x<=604&&a.y>=584&&a.y<=624)||(a.x>=850&&a.x<=1010&&a.y>=630&&a.y<=710))||(a.type==='click'&&a.button!=='left')))throw Error('Input outside controller');}
    const age=performance.now()-source.frame.received;
    await page.evaluate(meta=>window.arena.source(meta),source.frame.meta);
    const late=age>6000;
    if(!late){for(const a of actions){if(epoch!==generation)break;if(a.type==='move')await page.mouse.move(a.x,a.y);if(a.type==='click')await page.mouse.click(a.x,a.y);if(a.type==='wait')await pause(150)}await page.evaluate(()=>window.arena.flush())}
    status.state=late?'Input late — missed deadline':'Playing';status.lastAction=late?'Expired input discarded':actions.map(a=>a.type+(['move','click'].includes(a.type)?` (${Math.round(a.x)}, ${Math.round(a.y)})`:'')).join(' · ');
    const traceID=trace.length;await writeFile(join(traceDir,`${traceID}.png`),source.png);
    trace.push({run:source.frame.meta.run,rally:source.frame.meta.rally,frame:source.frame.meta.frame,latencyMS:status.latencyMS,ageMS:Math.round(age),actions,discarded:late,usage:result.usage});
    source=await screenshot();outputs.push({type:'computer_call_output',call_id:call.call_id,output:{type:'computer_screenshot',image_url:`data:image/png;base64,${source.png.toString('base64')}`,detail:'original'}});
   }
   previous=result.id;next=requestBody(outputs,previous);
   await writeFile(join(traceDir,'trace.json'),JSON.stringify({model:activeModel,status,trace},null,2));
  }
 }
}
async function close(){stopped=true;abort?.abort();await browser?.close();server.close();await writeFile(join(traceDir,'trace.json'),JSON.stringify({model:activeModel,status,trace},null,2));process.exit(0)}
process.on('SIGTERM',close);process.on('SIGINT',close);
async function jevLoop(){
 const key=await gatewayKey();if(!key){status.state='Unavailable: AI_GATEWAY_API_KEY missing';return}
 let lastFrame=-1;
 while(!stopped){
  if(!latest?.meta.playing||!latest.meta.observation||latest.meta.frame===lastFrame){if(!latest?.meta.playing)status.state='Waiting for match';await pause(50);continue}
  if(status.calls>=1000||status.cost>=5){status.state='Session budget reached';return}
  if(runCalls>=300||runCost>=1.5){status.state='Match budget reached';await pause(100);continue}
  const source=latest,epoch=generation;lastFrame=source.meta.frame;abort=new AbortController();
  status.state='Thinking';const began=performance.now();status.calls++;runCalls++;
  try{
   const decision=await evaluateJev(key,source.meta.observation,AbortSignal.any([abort.signal,AbortSignal.timeout(6000)]));
   status.cost+=decision.cost;runCost+=decision.cost;status.latencyMS=Math.round(performance.now()-began);
   if(epoch!==generation||!latest?.meta.playing)continue;
   const age=performance.now()-source.received;
   const accepted=age<=6000&&queueInput({...source.meta,x:decision.x,swing:decision.swing});
   status.state=accepted?'Playing':'Input late — missed deadline';
   status.lastAction=`${decision.lane} (x=${decision.x}) · ${decision.swing?'SWING':'wait'} · ${Math.round(decision.probability*100)}% swing`;
   trace.push({run:source.meta.run,rally:source.meta.rally,frame:source.meta.frame,observation:source.meta.observation,decision,latencyMS:status.latencyMS,ageMS:Math.round(age),accepted});
   await writeFile(join(traceDir,'trace.json'),JSON.stringify({model:activeModel,status,trace},null,2));
  }catch(e){if(epoch!==generation||stopped)continue;status.state=`Unavailable: ${e.name==='TimeoutError'?'Jev timed out':e.message}`;return}
  await pause(Math.max(0,250-(performance.now()-began)));
 }
}
if(!manual)(provider==='jev'?jevLoop():loop()).catch(e=>{status.state=`Unavailable: ${e.message}`});
