import assert from 'node:assert/strict';
import { test } from 'node:test';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import './engine.js';
const context = (url, type = 'Script', sourceUrl = 'https://example.org/') => ({url, sourceUrl, type, siteId:'test',host:'example.org'});
const fixture = [
  '||ads.example^',
  '@@||ads.example/allowed.js',
  '||third.example^$third-party',
  '||typed.example^$image',
  '||redirect.example^$redirect=noopjs',
  'example.org##.advert',
  'example.org#@#.excepted',
  'example.org##.excepted',
  "example.org#%#//scriptlet('set-constant', 'adguardTest', 'true')",
  "example.org#%#//scriptlet('set-constant', 'excepted', 'true')",
  "example.org#@%#//scriptlet('set-constant', 'excepted', 'true')",
].join('\n');
test('blocking, exact domains, exceptions, third-party and known resource types', () => {
  adguard.init([{id:1,content:fixture}]);
  for (const host of ['ads.example','sub.ads.example']) assert.equal(adguard.evaluateRequest(context(`https://${host}/ad.js`)).block,true);
  for (const url of ['https://notads.example/a','https://ads.example.evil/a','https://ads.example/allowed.js','https://cdn.example/?ad=ads.example']) assert.equal(adguard.evaluateRequest(context(url)).block,false);
  assert.equal(adguard.evaluateRequest(context('https://third.example/ad.js')).block,true);
  assert.equal(adguard.evaluateRequest(context('https://third.example/ad.js','Script','https://third.example/')).block,false);
  assert.equal(adguard.evaluateRequest(context('https://typed.example/a','Image')).block,true);
  assert.equal(adguard.evaluateRequest(context('https://typed.example/a','Other')).block,false);
  const redirect = adguard.evaluateRequest(context('https://redirect.example/a'));
  assert.equal(redirect.block,true);
  assert.equal(redirect.redirect,'noopjs');
});
test('cosmetic and scriptlet exceptions use upstream semantics', () => {
  adguard.init([{id:1,content:fixture}]);
  const rules = adguard.getPageRules(context('https://example.org/','Document'));
  assert(rules.css.some((css)=>css.startsWith('.advert ')));
  assert(!rules.css.some((css)=>css.startsWith('.excepted ')));
  assert.equal(rules.scripts.length,1);
  assert.equal(rules.scripts[0].args[0],'adguardTest');
});
test('compatibility exceptions are scoped to site and frame host', () => {
  adguard.init([{id:1,content:fixture}], [{siteId:'test',host:'example.org',networkExceptions:['@@||ads.example^'],disabledRules:['example.org##.advert'],disabledScriptlets:['set-constant']}]);
  assert.equal(adguard.evaluateRequest(context('https://ads.example/a')).block,false);
  assert.equal(adguard.evaluateRequest({...context('https://ads.example/a'),siteId:'other'}).block,true);
  assert.equal(adguard.evaluateRequest({...context('https://ads.example/a'),host:'other.org'}).block,true);
  const rules=adguard.getPageRules(context('https://example.org/','Document'));
  assert.equal(rules.scripts.length,0);
  assert(!rules.css.some((css)=>css.startsWith('.advert ')));
  assert.throws(()=>adguard.init([], [{siteId:'x',host:'*',disabledRules:[],disabledScriptlets:[],networkExceptions:[]}]),/Invalid compatibility/);
  assert.throws(()=>adguard.init([], [{siteId:'x',host:'x.org',disabledRules:[],disabledScriptlets:[],networkExceptions:['||ads.example^']}]),/must be exceptions/);
});
test('bundled filter assets match their pinned manifest and initialize together', () => {
  const root=new URL('../../assets/adguard/',import.meta.url);
  const manifest=JSON.parse(fs.readFileSync(new URL('manifest.json',root)));
  const filters=manifest.filters.map((item)=>{
    const bytes=fs.readFileSync(new URL(`filter_${item.id}.json`,root));
    assert.equal(createHash('sha256').update(bytes).digest('hex'),item.assetSha256);
    return JSON.parse(bytes);
  });
  const stats=adguard.init(filters);
  assert(stats.rules>200000);
  assert.equal(stats.conversionErrors,0);
  assert.equal(adguard.evaluateRequest(context('https://doubleclick.net/ad.js')).block,true);
});

test('page runtime is idempotent, preserves owned selectors, and runs bundled scriptlets without eval', async () => {
  const { JSDOM } = await import('jsdom');
  const page = fs.readFileSync(new URL('../../assets/adguard/page.js',import.meta.url),'utf8');
  adguard.init([{id:1,content:fixture+'\nexample.org##.owned'}]);
  const rules = adguard.getPageRules(context('https://example.org/','Document'));
  const dom = new JSDOM('<div class="advert"></div><div class="owned"></div><button class="jw-skip jw-skippable">Skip</button>', {url:'https://example.org/',runScripts:'outside-only'});
  const config = {initialUrl:'https://example.org/',initialRules:rules,cosmetic:true,scriptlets:true,owned:{'example.org':['.owned']}};
  const code=page.replaceAll('__MV_ADGUARD_CONFIG__',JSON.stringify(config));
  dom.window.eval(code);
  dom.window.eval(code);
  assert.equal(dom.window.document.querySelectorAll('[data-mv-adguard]').length,1);
  assert.equal(dom.window.adguardTest,true);
  assert.equal(dom.window.excepted,undefined);
  assert.equal(dom.window.getComputedStyle(dom.window.document.querySelector('.advert')).display,'none');
  assert.notEqual(dom.window.getComputedStyle(dom.window.document.querySelector('.owned')).display,'none');
  assert.notEqual(dom.window.getComputedStyle(dom.window.document.querySelector('.jw-skip')).display,'none');
  dom.window.close();
});
test('iframe bridge discards results after URL changes and respects switches', async () => {
  const { JSDOM } = await import('jsdom');
  const page = fs.readFileSync(new URL('../../assets/adguard/page.js',import.meta.url),'utf8');
  const dom = new JSDOM('<div class="advert"></div>',{url:'https://player.example/',runScripts:'outside-only'});
  let resolve;
  dom.window.flutter_inappwebview={callHandler:()=>new Promise((done)=>{resolve=done;})};
  dom.window.eval(page.replaceAll('__MV_ADGUARD_CONFIG__',JSON.stringify({initialUrl:'https://example.org/',cosmetic:true,scriptlets:true,owned:{}})));
  dom.window.history.pushState({},'', '/changed');
  resolve({css:['.advert { display: none !important; }'],extended:[],scripts:[]});
  await Promise.resolve();
  assert.equal(dom.window.document.querySelectorAll('[data-mv-adguard]').length,0);
  dom.window.close();
});
test('Extended CSS hides dynamic ad text while AdGuard click automation stays excluded', async () => {
  const { JSDOM } = await import('jsdom');
  adguard.init([{id:1,content: "example.org#?#div.marker:contains(Ad marker)\nexample.org#%#//scriptlet('trusted-click-element', '.jw-skip')"}]);
  const rules=adguard.getPageRules(context('https://example.org/','Document'));
  assert.equal(rules.scripts.length,0);
  assert.equal(rules.extended.length,1);
  const dom=new JSDOM('<div class="marker">Ad marker</div><button class="jw-skip">Skip</button>',{url:'https://example.org/',runScripts:'outside-only',pretendToBeVisual:true});
  const page=fs.readFileSync(new URL('../../assets/adguard/page.js',import.meta.url),'utf8');
  dom.window.eval(page.replaceAll('__MV_ADGUARD_CONFIG__',JSON.stringify({initialUrl:'https://example.org/',initialRules:rules,cosmetic:true,scriptlets:true,owned:{}})));
  await new Promise(resolve=>setTimeout(resolve,50));
  assert.equal(dom.window.getComputedStyle(dom.window.document.querySelector('.marker')).display,'none');
  assert.notEqual(dom.window.getComputedStyle(dom.window.document.querySelector('.jw-skip')).display,'none');
  dom.window.dispatchEvent(new dom.window.Event('pagehide'));
  dom.window.close();
});


test('actual filter worker initializes all lists and answers private request messages', async () => {
  const { Worker } = await import('node:worker_threads');
  const directory = new URL('../../assets/adguard/',import.meta.url).pathname;
  const worker = new Worker(`
    const {parentPort} = require('node:worker_threads');
    const fs = require('node:fs'); const vm = require('node:vm');
    const directory = ${JSON.stringify(directory)};
    globalThis.self=globalThis;
    globalThis.postMessage=(value)=>parentPort.postMessage(value);
    globalThis.importScripts=(name)=>vm.runInThisContext(fs.readFileSync(directory+name,'utf8'));
    globalThis.fetch=async(name)=>({ok:true,json:async()=>JSON.parse(fs.readFileSync(directory+name,'utf8'))});
    vm.runInThisContext(fs.readFileSync(directory+'worker.js','utf8'));
    parentPort.on('message',data=>self.onmessage({data}));
  `,{eval:true});
  try {
    const next=()=>new Promise((resolve,reject)=>{worker.once('message',resolve);worker.once('error',reject);});
    const ready=await next();
    assert.equal(ready.kind,'ready',JSON.stringify(ready));
    assert.equal(ready.rules,612554);
    const response=next();
    worker.postMessage({id:1,method:'evaluateRequest',context:context('https://doubleclick.net/ad.js')});
    assert.equal((await response).result.block,true);
  } finally {await worker.terminate();}
});
