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

test('Android tap action sends visible button coordinates to native handler', () => {
  let timer;
  const calls = [];
  const button = {isConnected:true, hasAttribute:()=>false, disabled:false,
    getClientRects:()=>[1], getBoundingClientRect:()=>({left:10, top:20, width:30, height:40})};
  const window = {innerWidth:400, addEventListener() {},
    getComputedStyle:()=>({display:'block', visibility:'visible', opacity:'1'}),
    flutter_inappwebview:{callHandler:(...args)=>calls.push(args)}};
  window.top = window;
  const context = {window, location:{hostname:'example.com'}, URL,
    document:{referrer:'', querySelector:()=>button,
      createDocumentFragment:()=>({querySelector:()=>null})},
    setInterval:(cb)=>{timer=cb;return 1}, clearInterval() {}};
  const rules = [{id:'skip', hosts:['*'], actions:[{type:'tapWhenVisible', selectors:['button#adgate-skip']}]}];
  vm.runInNewContext(read('assets/runtime/rule_runtime.js').replace('__RULES__',JSON.stringify(rules)),context);
  timer();
  assert.deepEqual(calls, [['mvTap',25,40,400]]);
  button.disabled = true;
  timer();
  assert.equal(calls.length,1);
});
