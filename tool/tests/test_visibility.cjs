const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const root = require('node:path').resolve(__dirname, '../..');
const read = (p) => fs.readFileSync(`${root}/${p}`, 'utf8');

test('shared visibility rejects hidden, disabled and invisible ancestors', () => {
  const context = {window: {getComputedStyle: (el) => el.style}};
  const visible = vm.runInNewContext(read('tool/templates/runtime/visibility.js') + '\nisVisible', context);
  const button = {isConnected: true, hasAttribute: () => false, disabled: false,
    style: {display: 'block', visibility: 'visible', opacity: '1'}, getClientRects: () => [1]};
  assert.equal(visible(button), true);
  for (const property of ['display', 'visibility', 'opacity']) {
    button.parentElement = {style: {...button.style, [property]: {display:'none', visibility:'collapse', opacity:'0'}[property]}};
    assert.equal(visible(button), false);
  }
  delete button.parentElement;
  button.disabled = true;
  assert.equal(visible(button), false);
  button.disabled = false;
  button.isConnected = false;
  assert.equal(visible(button), false);
});

test('extension clicks once, then resets hidden and detached buttons', () => {
  let callback;
  class Element {
    isConnected = true;
    disabled = false;
    hidden = false;
    clicks = 0;
    hasAttribute() { return this.hidden; }
    matches() { return true; }
    querySelectorAll() { return []; }
    getClientRects() { return [1]; }
    click() { this.clicks++; }
  }
  const button = new Element();
  const context = {Element, WeakSet,
    window: {getComputedStyle: () => ({display:'block', visibility:'visible', opacity:'1'})},
    document: {querySelectorAll: () => button.isConnected ? [button] : []},
    MutationObserver: class { constructor(cb) { callback = cb; } observe() {} }};
  vm.runInNewContext(read('extension/content/adgate-skip-global.js'), context);
  const tick = (mutations=[]) => callback(mutations);
  tick(); assert.equal(button.clicks, 1);
  button.hidden = true; tick();
  button.hidden = false; tick(); assert.equal(button.clicks, 2);
  button.isConnected = false;
  tick([{type:'childList', removedNodes:[button]}]);
  button.isConnected = true; tick(); assert.equal(button.clicks, 3);
});

test('Android runtime preserves native tap relay and shared visibility', () => {
  assert.ok(read('assets/runtime/rule_runtime.js').includes('"mvTap"'));
  assert.ok(read('assets/runtime/rule_runtime.js').includes(read('tool/templates/runtime/visibility.js').trim()));
  assert.ok(read('extension/content/adgate-skip-global.js').includes(read('tool/templates/runtime/visibility.js').trim()));
});

test('Android tap action sends visible button coordinates to native handler', async () => {
  let timer;
  const calls = [];
  const button = {isConnected:true, hasAttribute:()=>false, disabled:false,
    getClientRects:()=>[1], getBoundingClientRect:()=>({left:10, top:20, width:30, height:40})};
  const window = {innerWidth:400, innerHeight:600, addEventListener() {},
    getComputedStyle:()=>({display:'block', visibility:'visible', opacity:'1'}),
    flutter_inappwebview:{callHandler:(...args)=>{calls.push(args);return Promise.resolve(true)}}};
  window.top = window;
  const context = {window, location:{hostname:'example.com'}, URL,
    document:{referrer:'', querySelector:()=>button, querySelectorAll:(selector)=>selector==='button#adgate-skip'?[button]:[], elementFromPoint:()=>button,
      createDocumentFragment:()=>({querySelector:()=>null})},
    setInterval:(cb)=>{timer=cb;return 1}, clearInterval() {}};
  const rules = [{id:'skip', hosts:['*'], actions:[{type:'tapWhenVisible', selectors:['button#adgate-skip']}]}];
  vm.runInNewContext(read('assets/runtime/rule_runtime.js').replace('__RULES__',JSON.stringify(rules)),context);
  await timer();
  assert.deepEqual(calls, [['mvTap',25,40,400]]);
  button.disabled = true;
  await timer();
  assert.equal(calls.length,1);
});

test('Android hide rule defeats inline important display and re-hides reinjected ads', () => {
  const sideAd = (id) => {
    const values = new Map([['display', 'block']]);
    const priorities = new Map([['display', 'important']]);
    return {
      nodeType: 1,
      id,
      style: {
        getPropertyValue: (name) => values.get(name) || '',
        getPropertyPriority: (name) => priorities.get(name) || '',
        setProperty: (name, value, priority = '') => {
          values.set(name, value);
          priorities.set(name, priority);
        },
      },
      matches: (selector) => selector.split(',').map((s) => s.trim()).includes(`#${id}`),
      querySelectorAll: () => [],
    };
  };
  const original = sideAd('box-side-r');
  let nodes = [original];
  let observerCallback;
  const documentElement = {appendChild() {}};
  const context = {
    URL,
    location: {hostname: 'animeruka.com'},
    window: {__mvRules: undefined, addEventListener() {}},
    document: {
      referrer: '',
      documentElement,
      head: {appendChild() {}},
      createDocumentFragment: () => ({querySelector: () => null}),
      createElement: () => ({dataset: {}, isConnected: true}),
      querySelectorAll: (selector) => nodes.filter((node) => node.matches(selector)),
    },
    MutationObserver: class {
      constructor(callback) { observerCallback = callback; }
      observe() {}
    },
  };
  const rules = [{
    id: 'animeruka-hide-ads', hosts: ['animeruka.com'],
    actions: [{type: 'hide', selectors: ['#box-side-l', '#box-side-r']}],
  }];
  vm.runInNewContext(
    read('assets/runtime/rule_runtime.js').replace('__RULES__', JSON.stringify(rules)),
    context,
  );
  assert.equal(original.style.getPropertyValue('display'), 'none');
  assert.equal(original.style.getPropertyPriority('display'), 'important');

  original.style.setProperty('display', 'block', 'important');
  observerCallback([{type: 'attributes', attributeName: 'style', target: original}]);
  assert.equal(original.style.getPropertyValue('display'), 'none');

  const reinjected = sideAd('box-side-l');
  nodes = [original, reinjected];
  observerCallback([{type: 'childList', addedNodes: [reinjected]}]);
  assert.equal(reinjected.style.getPropertyValue('display'), 'none');
});

test('extension skips the real JW Player ready DIV control', () => {
  let observer;
  const skip = {isConnected:true, disabled:false, clicks:0, parentElement:null,
    hasAttribute:()=>false, getAttribute:()=>null, matches:()=>false, querySelectorAll:()=>[],
    getClientRects:()=>[1], click(){this.clicks++}, textContent:'ข้าม',
    className:'jw-skip jw-reset jw-skippable'};
  const context = {WeakSet, Element:class {},
    window:{getComputedStyle:()=>({display:'flex',visibility:'visible',opacity:'1'})},
    document:{querySelectorAll:(selector)=>selector.includes('.jw-skip.jw-skippable') ? [skip] : []},
    MutationObserver:class {constructor(cb){observer=cb} observe(){}}};
  vm.runInNewContext(read('extension/content/adgate-skip-global.js'),context);
  assert.equal(skip.clicks,1,'ready JW skip DIV must be clicked by extension');
  observer([]);assert.equal(skip.clicks,1,'same visible ad is not clicked repeatedly');
});

test('WebView requests a native tap for the real JW Player ready DIV control', async () => {
  let timer;
  const calls=[];
  const skip={isConnected:true,hasAttribute:()=>false,getAttribute:()=>null,disabled:false,
    getClientRects:()=>[1],getBoundingClientRect:()=>({left:10,top:20,width:30,height:40})};
  const window={innerWidth:400,innerHeight:600,addEventListener(){},
    getComputedStyle:()=>({display:'flex',visibility:'visible',opacity:'1'}),
    flutter_inappwebview:{callHandler:(...args)=>{calls.push(args);return Promise.resolve(true)}}};
  window.top=window;
  const context={window,location:{hostname:'goseries4k.com'},URL, setTimeout,clearTimeout,
    document:{referrer:'',elementFromPoint:()=>skip,querySelector:(selector)=>selector.includes('.jw-skip.jw-skippable')?skip:null,
      querySelectorAll:(selector)=>selector.includes('.jw-skip.jw-skippable')?[skip]:[],
      createDocumentFragment:()=>({querySelector:()=>null})},
    setInterval:cb=>{timer=cb;return 1},clearInterval(){}};
  const rules=JSON.parse(read('assets/catalog/websites.json')).globalRules;
  vm.runInNewContext(read('assets/runtime/rule_runtime.js').replace('__RULES__',JSON.stringify(rules)),context);
  await timer();
  assert.deepEqual(calls,[['mvTap',25,40,400]],'WebView must use native touch instead of synthetic click');
});

test('Thai skip labels are recognized only among scoped ad-player controls', () => {
  const queries=[];
  const labels=['ข้าม','ข้ามโฆษณา','ข้าม โฆษณา','Skip ad','Skip ads','ข้ามใน 5 วินาที','เล่น','ข้ามตอน'];
  const controls=labels.map(text=>({textContent:text,getAttribute:()=>null,matches:()=>false}));
  const document={querySelectorAll:selector=>{
    queries.push(selector);
    return selector==='button#adgate-skip' ? [] : controls;
  }};
  const find=vm.runInNewContext(read('tool/templates/runtime/skip_targets.js')+'\nfindSkipButtons',{document});
  assert.deepEqual(Array.from(find('button#adgate-skip'),x=>x.textContent),labels.slice(0,5));
  assert.ok(queries[1].includes('.jwplayer.jw-flag-ads [role="button"]'));
  assert.ok(!queries.includes('button,[role="button"]'),'never scan all page buttons for plain skip text');
  controls[0].matches=()=>true;
  assert.ok(!Array.from(find('button#adgate-skip')).includes(controls[0]),'JW countdown is not yet skippable');
});

test('extension can skip a second ad that reuses the same JW element', () => {
  let observer;let ready=true;
  const button={isConnected:true,disabled:false,clicks:0,hasAttribute:()=>false,getAttribute:()=>null,
    getClientRects:()=>[1],textContent:'ข้าม',click(){this.clicks++}};
  const context={Element:class {},WeakSet,
    window:{getComputedStyle:()=>({display:'block',visibility:'visible',opacity:'1'})},
    document:{querySelectorAll:selector=>selector.includes('.jw-skip.jw-skippable')&&ready?[button]:[]},
    MutationObserver:class{constructor(cb){observer=cb}observe(){}}};
  vm.runInNewContext(read('extension/content/adgate-skip-global.js'),context);
  assert.equal(button.clicks,1);
  ready=false;observer([]);
  ready=true;observer([]);
  assert.equal(button.clicks,2);
});

test('WebView waits for viewport and native bridge without exhausting later ads', async () => {
  let timer;let top=900;let bridgeReady=false;let nativeCalls=0;
  const button={isConnected:true,disabled:false,hasAttribute:()=>false,getAttribute:()=>null,
    getClientRects:()=>[1],getBoundingClientRect:()=>({left:10,top,width:40,height:20})};
  const window={innerWidth:400,innerHeight:600,addEventListener(){},
    getComputedStyle:()=>({display:'block',visibility:'visible',opacity:'1'}),
    flutter_inappwebview:{callHandler:async()=>{nativeCalls++;return bridgeReady}}};
  window.top=window;
  const context={window,location:{hostname:'example.com'},URL,
    document:{referrer:'',elementFromPoint:()=>button,querySelectorAll:s=>s==='button#adgate-skip'?[button]:[],
      createDocumentFragment:()=>({querySelector(){}})},
    setInterval:cb=>{timer=cb;return 1},clearInterval(){}};
  const rules=[{id:'skip',hosts:['*'],actions:[{type:'tapWhenVisible',selectors:['button#adgate-skip']}]}];
  vm.runInNewContext(read('assets/runtime/rule_runtime.js').replace('__RULES__',JSON.stringify(rules)),context);
  for(let i=0;i<30;i++)await timer();
  assert.equal(nativeCalls,0,'off-screen buttons must not receive native taps');
  top=100;
  for(let i=0;i<30;i++)await timer();
  bridgeReady=true;await timer();assert.equal(nativeCalls,31,'bridge failures do not consume tap budget');
  for(let i=0;i<20;i++)await timer();
  assert.equal(nativeCalls,42,'twelve accepted taps cap one stuck ad');
  button.disabled=true;await timer();
  button.disabled=false;await timer();assert.equal(nativeCalls,43,'new ad resets budget');
});

test('iframe relay scales CSS borders and viewport then acknowledges only the actual child', async () => {
  let message;const calls=[];const replies=[];
  const child={postMessage:(data)=>replies.push(data)};
  const frame={contentWindow:child,isConnected:true,hasAttribute:()=>false,getAttribute:()=>null,
    getClientRects:()=>[1],offsetWidth:110,offsetHeight:60,clientWidth:100,clientHeight:50,clientLeft:5,clientTop:5,
    getBoundingClientRect:()=>({left:100,top:80,width:220,height:120})};
  const window={innerWidth:800,innerHeight:600,addEventListener:(type,cb)=>{message=cb},
    getComputedStyle:()=>({display:'block',visibility:'visible',opacity:'1'}),
    flutter_inappwebview:{callHandler:async(...args)=>{calls.push(args);return true}}};
  window.top=window;
  const context={window,location:{hostname:'example.com'},URL,
    document:{referrer:'',elementFromPoint:()=>frame,querySelectorAll:s=>s==='iframe'?[frame]:[],createDocumentFragment:()=>({querySelector(){}})},
    setInterval:()=>1,clearInterval(){}};
  const rules=[{id:'skip',hosts:['*'],actions:[{type:'tapWhenVisible',selectors:['button#adgate-skip']}]}];
  vm.runInNewContext(read('assets/runtime/rule_runtime.js').replace('__RULES__',JSON.stringify(rules)),context);
  const data={__mvTap:true,id:7,rect:{x:20,y:10,w:40,h:20},width:200,height:100};
  await message({data,origin:'https://player.example',source:child});
  assert.deepEqual(calls,[['mvTap',150,110,800]]);
  assert.equal(replies[0].ok,true);
  await message({data,origin:'https://player.example',source:{postMessage(){throw Error('spoof')}}});
  assert.equal(calls.length,1,'unrelated windows cannot relay taps');
  await message({data:{...data,id:8,rect:{x:300,y:10,w:40,h:20}},origin:'https://player.example',source:child});
  assert.equal(calls.length,1,'child cannot target outside its own viewport');
  assert.equal(replies[1].ok,false);
});

test('extension uses JW public skip API in MAIN world without requesting native input', () => {
  const apiCalls=[];
  const button={isConnected:true,hasAttribute:()=>false,getAttribute:()=>null,disabled:false,
    getClientRects:()=>[1],closest:()=>({id:'actual-ad-player'}),click(){throw Error('synthetic click rejected')}};
  const context={Element:class{},WeakSet,
    window:{getComputedStyle:()=>({display:'flex',visibility:'visible',opacity:'1'}),
      jwplayer:id=>({skipAd:()=>apiCalls.push(id)})},
    document:{querySelectorAll:s=>s.includes('.jw-skip.jw-skippable')?[button]:[]},
    MutationObserver:class{observe(){}}};
  vm.runInNewContext(read('extension/content/adgate-skip-global.js'),context);
  assert.deepEqual(apiCalls,['actual-ad-player']);
  const manifest=JSON.parse(read('extension/manifest.json'));
  const script=manifest.content_scripts.find(x=>x.js?.includes('content/adgate-skip-global.js'));
  assert.equal(script.world,'MAIN');
  assert.ok(!manifest.permissions?.includes('debugger'),'no debugger permission for trusted input');
});
