import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {root} from '../astra-probe/probe.mjs';
export const jevModel='typesafe-ai/jev';
export async function gatewayKey(){
 if(process.env.AI_GATEWAY_API_KEY?.trim())return process.env.AI_GATEWAY_API_KEY.trim();
 let env='';try{env=await readFile(join(root,'.env'),'utf8')}catch{}
 let value=env.match(/^\s*(?:export\s+)?AI_GATEWAY_API_KEY\s*=\s*(.*?)\s*$/m)?.[1];
 if(value?.startsWith('"')||value?.startsWith("'"))value=value.slice(1,value.indexOf(value[0],1));
 return value?.split(/\s+#/)[0]?.trim()||null;
}
export const lanePositions={farLeft:4,left:2.5,slightLeft:1.25,centre:0,slightRight:-1.25,right:-2.5,farRight:-4};
export function evaluationBody(state){
 return {model:jevModel,providerOptions:{gateway:{only:['typesafe-ai']}},state,questions:{
  position:{type:'choice',instructions:'You control a tennis racket at your baseline z=-18. Positive x is your left. Choose where to move to intercept the incoming ball, using only the recent measured positions. The ball travels toward z=-18 when incoming. Account for its lateral motion. Stay near centre when it travels away.',criteria:Object.fromEntries(Object.entries(lanePositions).map(([key,x])=>[key,`Move racket centre to court x=${x}.`]))},
  swing:{type:'boolean',instructions:'Should you start a forward stroke now? The racket face moves from z=-19.2 to z=-16.05 over 3 seconds and needs real contact with the incoming ball. Decisions are spaced 2.2 seconds apart, plus network latency. Start early, while an incoming ball is around z=-12 to -16, so the forward stroke meets it near z=-18. Do not wait for the ball to reach the racket or its final height; the ball bounces and rises during the stroke. Never swing when the ball is travelling away, no ball is present, or a stroke is already active. The centre of the racket face is y=0.05 with half-height 0.60.',criteria:{true:'Incoming ball nearing baseline, ready for one deliberate stroke.',false:'Wait: ball is distant, going away, absent, or racket is already swinging.'}}
 }};
}
export function decodeDecision(result){
 if(result.model!==jevModel)throw Error('Unexpected Jev model');
 const lane=result.answers?.position?.choice,probability=result.answers?.swing?.probability;
 if(!Object.hasOwn(lanePositions,lane)||!Number.isFinite(probability)||probability<0||probability>1)throw Error('Invalid Jev decision');
 return {x:lanePositions[lane],swing:probability>=0.5,lane,probability};
}
export async function evaluateJev(key,state,signal){
 const response=await fetch('https://ai-gateway.vercel.sh/v1/evaluate',{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify(evaluationBody(state)),signal});
 if(!response.ok){
  let type;try{type=(await response.json()).error?.type}catch{}
  if(type==='customer_verification_required')throw Error('Vercel needs a payment method to unlock AI Gateway');
  const error=Error(`Jev Gateway HTTP ${response.status}`);
  if(response.status===429){
   error.retryable=true;
   const value=response.headers.get('retry-after');
   const seconds=value===null?NaN:Number(value);
   error.retryAfterMS=Number.isFinite(seconds)?Math.max(1000,seconds*1000):Math.max(1000,(Date.parse(value)||Date.now())-Date.now());
  }
  throw error;
 }
 const result=await response.json();return{...decodeDecision(result),usage:result.usage,cost:Number(result.providerMetadata?.gateway?.cost)||0};
}
