import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {chromium} from '../astra-probe/node_modules/playwright/index.mjs';

test('Manual browser input uses authenticated frame identity and native command queue',async()=>{
 const child=spawn(process.execPath,[new URL('./server.mjs',import.meta.url).pathname],{env:{...process.env,AIRCADE_ARENA_MANUAL:'1',AIRCADE_ARENA_TOKEN:'manual-test-token'},stdio:['ignore','pipe','pipe']});
 let browser;
 try{
  const config=await new Promise((resolve,reject)=>{child.stdout.once('data',data=>{try{resolve(JSON.parse(data))}catch(e){reject(e)}});child.once('error',reject);child.once('exit',()=>reject(Error('Server exited')))});
  const request=(path,opts={})=>fetch(config.url+path,{...opts,headers:{Authorization:`Bearer ${config.token}`,...opts.headers}});
  assert.equal((await fetch(config.url+'/poll')).status,401);
  const image=await readFile(new URL('../astra-probe/court.png',import.meta.url));
  const meta={run:'test-run',rally:2,frame:42,captured:123.4,playing:true};
  assert.equal((await request('/frame',{method:'POST',headers:{'X-Aircade-Meta':JSON.stringify(meta)},body:image})).status,200);
  browser=await chromium.launch({headless:true,executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
  const page=await browser.newPage({viewport:{width:1024,height:720}});
  await page.goto(config.manualURL);await page.waitForFunction(()=>document.querySelector('#court').naturalWidth>0);
  await page.mouse.move(562,604);await page.mouse.click(942,667);await page.evaluate(()=>window.arena.flush());
  const poll=await(await request('/poll')).json();
  assert.equal(poll.commands.length,2);assert.equal(poll.commands[1].swing,true);
  assert.equal(poll.commands[1].run,meta.run);assert.equal(poll.commands[1].rally,2);assert.equal(poll.commands[1].frame,42);
  assert.ok(poll.commands[0].x<0);assert.ok(poll.commands[0].x>=-4.6);
  assert.deepEqual((await(await request('/poll')).json()).commands,[]);
  await request('/frame',{method:'POST',headers:{'X-Aircade-Meta':JSON.stringify({...meta,rally:3,frame:43})},body:image});
  const stale=await(await request('/input',{method:'POST',body:JSON.stringify({...meta,x:0,swing:true})})).json();
  assert.equal(stale.accepted,false);
  assert.equal((await request('/input',{method:'POST',headers:{Origin:'https://example.com'},body:'{}'})).status,403);
 }finally{await browser?.close();child.kill('SIGTERM')}
});
