import {test} from 'node:test';
import assert from 'node:assert/strict';
import {evaluationBody,decodeDecision,jevModel,evaluateJev,evaluateJevShot} from './jev.mjs';
test('Jev uses typed lane and swing decisions with no model substitution',()=>{
 const body=evaluationBody({recentObservations:[{ball:{x:1,y:0,z:-15},incoming:true}]});
 assert.equal(body.model,jevModel);assert.equal(body.questions.position.type,'choice');assert.equal(body.questions.swing.type,'boolean');
 const result=decodeDecision({model:jevModel,answers:{position:{choice:'left'},swing:{probability:0.9}}});
 assert.equal(result.x,2.5);assert.equal(result.swing,true);
 assert.throws(()=>decodeDecision({model:'other'}));
 assert.throws(()=>decodeDecision({model:jevModel,answers:{position:{choice:'teleport'},swing:{probability:0.9}}}));
});
test('Gateway errors are surfaced without returning a fallback decision or secrets',async()=>{
 const original=globalThis.fetch;
 try{globalThis.fetch=async()=>new Response('sensitive-provider-body',{status:401});await assert.rejects(()=>evaluateJev('secret',{},AbortSignal.timeout(1000)),/^Error: Jev Gateway HTTP 401$/)}finally{globalThis.fetch=original}
});
test('Rate limits preserve Retry-After without exposing the provider response',async()=>{
 const original=globalThis.fetch;
 try{
  for(const [header,expected] of [['3',3000],[null,1000],['invalid',1000]]){
   globalThis.fetch=async()=>new Response('sensitive-provider-body',{status:429,headers:header===null?{}:{'Retry-After':header}});
   await assert.rejects(()=>evaluateJev('secret',{},AbortSignal.timeout(1000)),error=>{
    assert.equal(error.message,'Jev Gateway HTTP 429');assert.equal(error.retryable,true);assert.equal(error.retryAfterMS,expected);return true;
   });
  }
 }finally{globalThis.fetch=original}
});

test('Tactical Jev preserves its selected legal shot and rejects invented shots',async()=>{
 const original=globalThis.fetch;
 const state={candidates:[{id:'left',targetX:-3.1,flightDuration:2.7,delay:0.3,stroke:'forehand'},{id:'right',targetX:3.1,flightDuration:2.5,delay:0.3,stroke:'backhand'}]};
 try{
  globalThis.fetch=async(_,req)=>{const body=JSON.parse(req.body);assert.equal(body.questions.shot.type,'choice');return Response.json({model:jevModel,answers:{shot:{choice:'right'}}})};
  assert.equal((await evaluateJevShot('secret',state,AbortSignal.timeout(1000))).targetX,3.1);
  globalThis.fetch=async()=>Response.json({model:jevModel,answers:{shot:{choice:'invented'}}});
  await assert.rejects(()=>evaluateJevShot('secret',state,AbortSignal.timeout(1000)),/Invalid Jev shot/);
 }finally{globalThis.fetch=original}
});
