const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync('assets/runtime/media_runtime.js', 'utf8');
function fixture() {
  let plays=0, pauses=0, nextClicks=0, styles=0;
  const classes = new Set();
  const video={isConnected:true,ended:false,paused:false,readyState:4,tagName:'VIDEO',currentTime:12,duration:120,
    play(){plays++;this.paused=false;return Promise.resolve();},pause(){pauses++;this.paused=true;}};
  const next={disabled:false,getAttribute:()=>null,getClientRects:()=>[{}],click:()=>nextClicks++};
  const env={window:{},navigator:{mediaSession:{metadata:{title:'Test song',artist:'Artist'}}},document:{
    title:'Page',createElement:()=>({}),documentElement:{appendChild(){styles++;},classList:{toggle(name,on){if(on)classes.add(name);else classes.delete(name);}}},
    querySelectorAll:()=>[video],querySelector:selector=>selector==='.ytp-next-button'?next:null,
  }};
  vm.createContext(env);
  vm.runInContext(source,env);
  return {env,video,next,classes,stats:()=>({plays,pauses,nextClicks,styles}),api:env.window.__mvMedia};
}
test('media controls report real capabilities, respect disabled buttons and pause without replay',()=>{
  const {api,video,next,stats}=fixture();
  assert.equal(api.snapshot().playing,true);
  assert.equal(api.snapshot().next,true);
  assert.equal(api.snapshot().previous,false);
  api.command('next');assert.equal(stats().nextClicks,1);
  next.disabled=true;
  assert.equal(api.snapshot().next,false);
  api.command('next');assert.equal(stats().nextClicks,1);
  api.command('pause');api.snapshot();assert.equal(video.paused,true);assert.equal(stats().plays,0);
  api.command('play');assert.equal(video.paused,false);assert.equal(stats().plays,1);
  api.command('stop');assert.equal(video.paused,true);
});
test('runtime is idempotent and PiP restores page styling; invalid times stay finite',()=>{
  const {env,api,video,classes,stats}=fixture();
  vm.runInContext(source,env);assert.equal(stats().styles,1);
  api.pip(true);assert(classes.has('mv-media-pip'));
  api.pip(false);assert(!classes.has('mv-media-pip'));
  video.duration=Infinity;video.currentTime=NaN;
  assert.equal(api.snapshot().duration,0);assert.equal(api.snapshot().position,0);
});
