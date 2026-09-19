import { startSurface,launchBrowser } from './probe.mjs';
const surface=await startSurface();
const {browser}=await launchBrowser(surface.url,true);
console.log(`Manual Phase 0 input surface: ${surface.url}`);
console.log('Move over the yellow target and left-click. This is a static probe, not live tennis.');
const close=async()=>{await browser.close();await surface.close();};
process.once('SIGINT',async()=>{await close();process.exit();});
process.once('SIGTERM',async()=>{await close();process.exit();});
browser.on('disconnected',async()=>{await surface.close();process.exit();});
