import assert from 'node:assert/strict';
import { test } from 'node:test';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { configuration, normalizeSettings } from './config.js';

test('extension settings preserve explicit off and reject invalid hosts',()=>{
  assert.deepEqual(normalizeSettings(undefined),{enabled:true,disabledHosts:[]});
  assert.deepEqual(normalizeSettings({enabled:false,disabledHosts:['example.com','example.com','evil.com/path','.invalid','x'.repeat(254),null]}),{enabled:false,disabledHosts:['example.com']});
});
test('Chrome configuration disables automatic cookie destruction and keeps app bridges absent',()=>{
  const config=configuration({enabled:false,disabledHosts:['example.com']},['example.com#@#.ad']);
  assert.equal(config.settings.filteringEnabled,false);
  assert.equal(config.settings.stealthModeEnabled,false);
  assert.equal(config.settings.stealth.selfDestructFirstPartyCookies,false);
  assert.equal(config.settings.stealth.selfDestructThirdPartyCookies,false);
  assert.deepEqual(config.staticFiltersIds,[2,3,11]);
  assert.deepEqual(config.allowlist,['example.com']);
  assert(!JSON.stringify(config).includes('flutter_inappwebview'));
});
test('packaged DNR snapshots match the pinned provenance',()=>{
  const root=new URL('../../extension/',import.meta.url);
  const manifest=JSON.parse(fs.readFileSync(new URL('manifest.json',root)));
  const info=JSON.parse(fs.readFileSync(new URL('adguard/build-info.json',root)));
  assert.equal(info.snapshot,'@adguard/dnr-rulesets@5.0.20261013160024');
  for(const {id,sha256} of info.filters) {
    const bytes=fs.readFileSync(new URL(`adguard/filters/declarative/ruleset_${id}/ruleset_${id}.json`,root));
    assert.equal(createHash('sha256').update(bytes).digest('hex'),sha256);
  }
  assert.equal(manifest.minimum_chrome_version,'121');
  assert.equal(manifest.declarative_net_request.rule_resources.length,3);
  assert(manifest.content_scripts.some(script=>script.world==='MAIN' && script.js.includes('content/adgate-skip-global.js')));
  assert(manifest.content_scripts.some(script=>script.js?.includes('adguard/content.js') && script.all_frames));
});
