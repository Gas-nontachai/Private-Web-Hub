import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { chromium } from 'playwright-core';
const extension=path.resolve(import.meta.dirname,'../../extension');
const profile=await fs.mkdtemp(path.join(os.tmpdir(),'movie-extension-test-'));
const executablePath=process.env.CHROMIUM_PATH || chromium.executablePath();
const pixels=[];
const server=http.createServer((req,res)=>{
  if(req.url.startsWith('/pixel')){pixels.push(req.url);res.writeHead(200,{'Content-Type':'image/gif'});res.end(Buffer.from('R0lGODlhAQABAAAAACwAAAAAAQABAAA=','base64'));return;}
  const port=server.address().port;
  res.writeHead(200,{'Content-Type':'text/html'});
  res.end(`<!doctype html><html><head><title>Movie extension fixture</title></head><body>
    <div class="adhl" id="owned">Owned ad</div><div class="ad-space" id="generic">Generic ad</div>
    <button id="adgate-skip" onclick="window.skipCount=(window.skipCount||0)+1">Skip ad</button>
    <img src="http://ads.doubleclick.net:${port}/pixel?case=${Date.now()}">
  </body></html>`);
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
let context;
try {
  context=await chromium.launchPersistentContext(profile,{executablePath,headless:true,ignoreDefaultArgs:['--disable-extensions'],args:[
    `--disable-extensions-except=${extension}`,`--load-extension=${extension}`,'--no-proxy-server',
    '--host-resolver-rules=MAP www.serieday-z.com 127.0.0.1, MAP ads.doubleclick.net 127.0.0.1, MAP streamcash.to 127.0.0.1',
  ]});
  const worker=context.serviceWorkers()[0] || await context.waitForEvent('serviceworker',{timeout:30000});
  console.log('Extension worker loaded');
  const id=new URL(worker.url()).host;
  const popup=await context.newPage();
  popup.on('console',msg=>{if(msg.type()==='error')console.log('Popup error:',msg.text());});
  await context.route('https://api.github.com/**',route=>route.fulfill({status:200,contentType:'application/json',body:'{"tag_name":"v1.0.0"}'}));
  await popup.goto(`chrome-extension://${id}/popup/index.html`);
  await popup.locator('#adguard-status').filter({hasText:/กฎ|ไม่พร้อม/}).waitFor({timeout:90000});
  const status=await popup.locator('#adguard-status').innerText();console.log('Popup:',status);
  await popup.screenshot({path:path.join(profile,'popup.png')});
  assert(!status.includes('ไม่พร้อม'),status);
  assert.deepEqual((await worker.evaluate(()=>chrome.declarativeNetRequest.getEnabledRulesets())).sort(),['ruleset_11','ruleset_2','ruleset_3']);
  context.on('console',msg=>{if(msg.type()==='error') console.log('Browser error:',msg.text());});
  const page=await context.newPage();
  await page.goto(`http://www.serieday-z.com:${server.address().port}/fixture`,{waitUntil:'networkidle'});
  await page.waitForFunction(()=>window.skipCount===1,{timeout:10000});
  await page.waitForFunction(()=>getComputedStyle(document.querySelector('#generic')).display==='none',null,{timeout:10000});
  assert.equal(await page.locator('#owned').evaluate(el=>getComputedStyle(el).display),'none');
  assert.equal(pixels.length,0,'DNR must block third-party ad requests before the server sees them');
  async function popupForSite() {
    await page.bringToFront();
    await popup.reload();
    await popup.waitForFunction(()=>!document.querySelector('#adguard-site').disabled);
  }
  await popupForSite();
  await popup.locator('#adguard-site').evaluate(el=>el.click());
  await popup.locator('#adguard-status').filter({hasText:'บันทึกแล้ว'}).waitFor();
  assert.deepEqual(await worker.evaluate(async()=>(await chrome.storage.local.get('movieExtensionAdguard')).movieExtensionAdguard.disabledHosts),['www.serieday-z.com']);
  await page.reload({waitUntil:'networkidle'});
  await page.waitForFunction(()=>window.skipCount===1);
  assert.equal(await page.locator('#generic').evaluate(el=>getComputedStyle(el).display),'block');
  assert.equal(await page.locator('#owned').evaluate(el=>getComputedStyle(el).display),'none');
  assert(pixels.length>0,'Site exception must allow the ad request');
  await popupForSite();
  await popup.locator('#adguard-site').evaluate(el=>el.click());
  await popup.locator('#adguard-status').filter({hasText:'บันทึกแล้ว'}).waitFor();
  await popup.locator('#adguard-enabled').evaluate(el=>el.click());
  await popup.locator('#adguard-status').filter({hasText:'บันทึกแล้ว'}).waitFor();
  assert.deepEqual(await worker.evaluate(()=>chrome.declarativeNetRequest.getEnabledRulesets()),[]);
  await page.reload({waitUntil:'networkidle'});
  await page.waitForFunction(()=>window.skipCount===1);
  assert.equal(await page.locator('#generic').evaluate(el=>getComputedStyle(el).display),'block');
  assert.equal(await page.locator('#owned').evaluate(el=>getComputedStyle(el).display),'none');
  await popup.locator('#adguard-enabled').evaluate(el=>el.click());
  await popup.locator('#adguard-status').filter({hasText:'บันทึกแล้ว'}).waitFor();
  await page.goto(`http://streamcash.to:${server.address().port}/fixture`,{waitUntil:'networkidle'});
  await page.waitForFunction(()=>window.__shown===1,null,{timeout:10000});
  console.log('PASS: network + cosmetics + bundled scriptlets, site exception, master off, independent owned CSS/Skip');
} finally {
  await context?.close();
  server.close();
  console.log('Browser test artifacts:',profile);
}
