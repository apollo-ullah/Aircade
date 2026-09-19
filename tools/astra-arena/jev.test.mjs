import {test} from 'node:test';
import assert from 'node:assert/strict';
import {evaluationBody,decodeDecision,jevModel,evaluateJev} from './jev.mjs';
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
