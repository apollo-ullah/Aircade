import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { randomInt } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { apiKey, root, model, startSurface, launchBrowser, executeActions, executeComputerCall, requestBody, request, tokenEstimate, summarize } from './probe.mjs';

const args=new Set(process.argv.slice(2));
if ([...args].some(a=>!['--self-test','--headed'].includes(a))) throw new Error('Supported flags: --self-test, --headed');
const selfTest=args.has('--self-test');
const output=join(root,'.local','astra-probe',`${new Date().toISOString().replace(/[:.]/g,'-')}-${selfTest?'self-test':'live'}`);
await mkdir(output,{recursive:true});
const report={ version:1,mode:selfTest?'scripted harness check':'live API',model:selfTest?null:model,
  status:'running',startedAt:new Date().toISOString(),fixture:'recorded native court with static target overlay',
  provesLiveTennis:false,hardwareVerified:false,limits:{trials:3,maxCalls:9,maxOutputTokensPerCall:1536,requestTimeoutMS:45000},
  trials:[],requests:[],estimatedTokenUSD:0,unknownUsageRequests:0,
  costNote:'Estimated standard token charges using documented 2026-09-19 rates; excludes any additional tool fees. Not an invoice.',
  outputDirectory:output };
let surface,browser,stopping=false;
async function save() {
  report.apiLatencyMS=summarize(report.requests.filter(r=>r.completed).map(r=>r.latencyMS));
  report.screenshotToActionMS=summarize(report.trials.flatMap(t=>t.actionLatenciesMS));
  report.passedTrials=report.trials.filter(t=>t.passed).length;
  report.phaseZeroVerified=!selfTest&&report.status==='passed';
  report.finishedAt=new Date().toISOString();
  await writeFile(join(output,'report.json'),JSON.stringify(report,null,2)+'\n');
  await writeFile(join(output,'report.md'),`# Astra Phase 0 probe\n\nStatus: **${report.status}**\n\nMode: ${report.mode}\n\nPassed trials: ${report.passedTrials}/3\n\nModel: ${report.model||'none (scripted)'}\n\nAPI completed-call latency: ${JSON.stringify(report.apiLatencyMS)}\n\nScreenshot-to-action latency: ${JSON.stringify(report.screenshotToActionMS)}\n\nEstimated token charges: $${report.estimatedTokenUSD.toFixed(6)}; ${report.costNote}\n\n${report.error?`Reason: ${report.error}\n\n`:''}This is a static court control test. It does not prove live tennis, AirPod usability, or deadline-sensitive gameplay.\n`);
}
async function cleanup() { await browser?.close().catch(()=>{});await surface?.close(); }
for (const signal of ['SIGINT','SIGTERM']) process.once(signal,async()=>{
  stopping=true;report.status='cancelled';await save();await cleanup();process.exit(130);
});

try {
  const key=selfTest?null:await apiKey();
  if (!selfTest&&!key) {
    report.status='blocked';report.error='OPENAI_API_KEY is missing. Add it to the ignored repository-root .env file.';
    process.exitCode=2;
  } else {
    surface=await startSurface();
    const launched=await launchBrowser(surface.url,args.has('--headed'));
    browser=launched.browser;
    const page=launched.page;
    console.log(`Probe browser ready. Evidence: ${output}`);
    for (let index=0;index<3&&!stopping;index++) {
      const target={x:randomInt(130,894),y:randomInt(100,420)};
      await page.evaluate(target=>window.probe.reset(target),target);
      const trial={index:index+1,passed:false,actionLatenciesMS:[],calls:[],screenshotReturned:false};
      report.trials.push(trial);
      let screenshot=await page.screenshot({path:join(output,`trial-${index+1}-before.png`)});
      if (selfTest) {
        await executeActions(page,[{type:'click',button:'left',x:20,y:110}]);
        const missed=await page.evaluate(()=>window.probe.result());
        if(missed.hit) throw new Error('Invalid fixture: an off-target click scored');
        trial.offTargetMissVerified=true;
        await executeActions(page,[{type:'move',x:target.x,y:target.y+86},{type:'click',button:'left',x:target.x,y:target.y+86}]);
        await page.screenshot({path:join(output,`trial-${index+1}-after.png`)});
        trial.result=await page.evaluate(()=>window.probe.result());trial.passed=trial.result.hit;
        await save();continue;
      }
      let previous,afterHitSubmitted=false;
      let observationAt=performance.now();
      let input=[{role:'user',content:[
        {type:'input_text',text:'You control an isolated Aircade test surface, 1024 by 720 pixels. Inspect the screenshot. Move the cyan racket onto the yellow TARGET circle on the court and LEFT-click once. Supported computer actions: move, left click, screenshot, wait. Use screenshot coordinates. The court is below the header. After receiving the resulting screenshot, verify TARGET HIT and finish with a short confirmation. This is a static input probe, not a live tennis match. Do not navigate or use keyboard shortcuts.'},
        {type:'input_image',image_url:`data:image/png;base64,${screenshot.toString('base64')}`,detail:'original'}
      ]}];
      for(let turn=0;turn<3;turn++) {
        if(report.requests.length>=9||report.estimatedTokenUSD>=1) throw new Error('Probe request/cost cap reached');
        const started=performance.now();
        const entry={trial:index+1,turn:turn+1,completed:false};report.requests.push(entry);
        console.log(`Astra trial ${index+1}/3, request ${turn+1}/3…`);
        let response;
        const returningScreenshot=input.some(item=>item.type==='computer_call_output');
        try { response=await request(key,requestBody(input,previous)); }
        catch(error) {entry.latencyMS=Math.round(performance.now()-started);report.unknownUsageRequests++;throw error;}
        entry.latencyMS=Math.round(performance.now()-started);entry.completed=true;entry.responseID=response.id;entry.usage=response.usage;
        if(returningScreenshot) trial.screenshotReturned=true;
        const estimate=tokenEstimate(response.usage);
        if(estimate===null) report.unknownUsageRequests++;else report.estimatedTokenUSD+=estimate;
        previous=response.id;
        const calls=(response.output||[]).filter(item=>item.type==='computer_call');
        trial.result=await page.evaluate(()=>window.probe.result());
        if (!calls.length) {
          trial.passed=trial.result.hit&&afterHitSubmitted;
          if(!trial.passed) trial.failure='Model finished without a verified screenshot/action/screenshot cycle.';
          break;
        }
        input=[];
        if(calls.length>4) throw new Error('Excessive computer calls in one response');
        for(const call of calls) {
          const executed=await executeComputerCall(page,call,join(output,`trial-${index+1}-turn-${turn+1}-${trial.calls.length+1}.png`));
          if(executed.actions.some(a=>['click','move'].includes(a.type))) trial.actionLatenciesMS.push(Math.round(executed.executedAt-observationAt));
          trial.calls.push({callID:call.call_id,actions:executed.actions});
          observationAt=executed.observedAt;
          trial.result=executed.result;
          // This will be submitted on the next request, including the actual changed pixels.
          input.push(executed.output);
        }
        afterHitSubmitted=trial.result.hit;
        await save();
      }
      if(!trial.passed) trial.failure ||= 'Three-request limit reached before model confirmation.';
      console.log(`Trial ${index+1}: ${trial.passed?'PASS':'NOT PROVEN'}`);
      await save();
    }
    report.status=report.trials.length===3&&report.trials.every(t=>t.passed)?'passed':'failed';
    if(report.status!=='passed') process.exitCode=1;
  }
} catch(error) {
  report.status='failed';
  // Credential value is never deliberately logged, including transport errors.
  const key=await apiKey().catch(()=>null);
  report.error=key?String(error.message).split(key).join('[REDACTED]'):String(error.message);
  process.exitCode=1;
} finally {
  await save();await cleanup();
  console.log(`${selfTest?'Scripted harness (Astra not tested)':'Live Astra Phase 0'} ${report.status}. Report: ${join(output,'report.md')}`);
  if(report.error) console.log(report.error);
}
