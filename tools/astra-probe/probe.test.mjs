import test from 'node:test';
import assert from 'node:assert/strict';
import {validateActions,executeActions,requestBody,tokenEstimate,summarize} from './probe.mjs';

test('rejects the whole batch before a partial input can be applied',async()=>{
  let moves=0;
  const page={mouse:{move(){moves++;}}};
  await assert.rejects(executeActions(page,[{type:'move',x:200,y:200},{type:'keypress',keys:['META','L']}]),/Unsupported/);
  assert.equal(moves,0);
});
test('constrains pointer input to finite court coordinates and bounded batches',()=>{
  for(const x of [NaN,Infinity,-1,1024]) assert.throws(()=>validateActions([{type:'move',x,y:200}]));
  for(const y of [0,85,626,1000]) assert.throws(()=>validateActions([{type:'move',x:200,y}]));
  assert.throws(()=>validateActions([{type:'click',button:'right',x:200,y:200}]));
  assert.throws(()=>validateActions(Array.from({length:13},()=>({type:'screenshot'}))));
  assert.equal(validateActions([{type:'click',button:'left',x:200,y:200}]).length,1);
});
test('uses the requested Astra model and computer tool with bounded output',()=>{
  const body=requestBody([{role:'user',content:'test'}],'resp_example');
  assert.equal(body.model,'gpt-6-astra');assert.deepEqual(body.tools,[{type:'computer'}]);
  assert.equal(body.previous_response_id,'resp_example');assert.equal(body.reasoning.effort,'low');
  assert.equal(body.max_output_tokens,1536);
});
test('estimates cached and uncached token charges without calling it an invoice',()=>{
  assert.equal(tokenEstimate({input_tokens:1000,input_tokens_details:{cached_tokens:500},output_tokens:100}),.0105);
  assert.equal(tokenEstimate(undefined),null);
  assert.deepEqual(summarize([40,10,30,20]),{count:4,median:25,p95:40,min:10,max:40});
});
