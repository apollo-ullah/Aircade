import test from 'node:test';
import assert from 'node:assert/strict';
import {startSurface,launchBrowser,executeComputerCall,request,requestBody} from './probe.mjs';

test('mocked API cycle executes real browser input and returns the changed screenshot with its call ID',async(t)=>{
  const surface=await startSurface();
  t.after(()=>surface.close());
  const {browser,page}=await launchBrowser(surface.url);
  t.after(()=>browser.close());
  await page.evaluate(()=>window.probe.reset({x:250,y:240}));
  const before=await page.screenshot();
  const realFetch=globalThis.fetch;
  t.after(()=>{globalThis.fetch=realFetch;});
  let requests=0;
  globalThis.fetch=async(url,options)=>{
    assert.equal(url,'https://api.openai.com/v1/responses');
    const body=JSON.parse(options.body);requests++;
    if(requests===1) return Response.json({id:'resp_mock_1',model:'gpt-6-astra',status:'completed',output:[{
      type:'computer_call',call_id:'call_mock_1',actions:[{type:'move',x:250,y:326},{type:'click',button:'left',x:250,y:326}]
    }]});
    assert.equal(body.previous_response_id,'resp_mock_1');
    assert.equal(body.input[0].call_id,'call_mock_1');
    assert.equal(body.input[0].type,'computer_call_output');
    assert.equal(body.input[0].output.type,'computer_screenshot');
    assert.notEqual(body.input[0].output.image_url,`data:image/png;base64,${before.toString('base64')}`);
    assert.equal((await page.evaluate(()=>window.probe.result())).hit,true);
    return Response.json({id:'resp_mock_2',model:'gpt-6-astra',status:'completed',output:[]});
  };
  const first=await request('unit-test-placeholder',requestBody([{role:'user',content:'scripted fixture'}]));
  const executed=await executeComputerCall(page,first.output[0]);
  assert.equal(executed.result.hit,true);
  await request('unit-test-placeholder',requestBody([executed.output],first.id));
  assert.equal(requests,2);
});

test('pending safety checks stop before browser input is executed',async()=>{
  await assert.rejects(executeComputerCall({}, {call_id:'fixture',pending_safety_checks:[{code:'review'}],actions:[{type:'click',x:250,y:326,button:'left'}]}),/requires review/);
});

test('provider rejection reveals only a status/code and is not retried',async(t)=>{
  const realFetch=globalThis.fetch;t.after(()=>{globalThis.fetch=realFetch;});let calls=0;
  globalThis.fetch=async()=>{calls++;return Response.json({error:{code:'model_not_found',message:'private diagnostic text'}},{status:404});};
  await assert.rejects(request('unit-test-placeholder',requestBody([])),{message:'OpenAI HTTP 404 (model_not_found)'});
  assert.equal(calls,1);
});
