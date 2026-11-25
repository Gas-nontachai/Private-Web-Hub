import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { build } from 'esbuild';
const here=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(here,'../..');
const output=path.join(root,'extension/adguard');
const ids=[2,3,11];
await fs.mkdir(output,{recursive:true});
const catalog=JSON.parse(await fs.readFile(path.join(root,'assets/catalog/websites.json'),'utf8'));
const rules=["#@%#//scriptlet('trusted-click-element')", "#@%#//scriptlet('trusted-dispatch-event')"];
for (const site of catalog.sites) if (site.enabled) for (const rule of site.rules) if (rule.enabled) {
  for (const action of rule.actions) if (action.type==='hide') for (const selector of action.selectors) rules.push(`${rule.hosts.join(',')}#@#${selector}`);
}
await fs.writeFile(path.join(here,'compatibility.generated.json'),JSON.stringify(rules,null,2)+'\n');
for (const [entry,name] of [['background.js','background.js'],['content.js','content.js']]) {
  await build({absWorkingDir:here,entryPoints:[entry],bundle:true,platform:'browser',format:'iife',target:'chrome121',minify:true,legalComments:'eof',outfile:path.join(output,name)});
}
const assets=path.join(here,'node_modules/@adguard/dnr-rulesets/dist/filters/chromium-mv3');
const manifest=JSON.parse(await fs.readFile(path.join(root,'extension/manifest.json'),'utf8'));
manifest.minimum_chrome_version='121';
manifest.background={service_worker:'adguard/background.js'};
manifest.permissions=['storage','unlimitedStorage','scripting','tabs','webNavigation','webRequest','cookies','declarativeNetRequest'];
manifest.host_permissions=['http://*/*','https://*/*'];
manifest.declarative_net_request={rule_resources:[]};
const provenance={snapshot:'@adguard/dnr-rulesets@5.0.20261013160024',filters:[]};
for (const id of [0,...ids]) {
  const relative=`declarative/ruleset_${id}/ruleset_${id}.json`;
  const bytes=await fs.readFile(path.join(assets,relative));
  const target=path.join(output,'filters',relative);
  await fs.mkdir(path.dirname(target),{recursive:true});await fs.writeFile(target,bytes);
  if(id!==0) manifest.declarative_net_request.rule_resources.push({id:`ruleset_${id}`,enabled:false,path:`adguard/filters/${relative}`});
  provenance.filters.push({id,sha256:createHash('sha256').update(bytes).digest('hex'),entries:JSON.parse(bytes).length});
}
const scriptletEntry=import.meta.resolve('@adguard/scriptlets',{parentURL:import.meta.url});
const scriptletDirectory=path.dirname(fileURLToPath(scriptletEntry));
await fs.mkdir(path.join(root,'extension/web-accessible-resources'),{recursive:true});
await fs.copyFile(path.join(scriptletDirectory,'redirects.yml'),path.join(root,'extension/web-accessible-resources/redirects.yml'));
await fs.cp(path.join(scriptletDirectory,'redirect-files'),path.join(root,'extension/web-accessible-resources/redirects'),{recursive:true});
manifest.web_accessible_resources=[{resources:['web-accessible-resources/redirects/*'],matches:['http://*/*','https://*/*'],use_dynamic_url:true}];
await fs.writeFile(path.join(root,'extension/manifest.json'),JSON.stringify(manifest,null,2)+'\n');
await fs.writeFile(path.join(output,'build-info.json'),JSON.stringify(provenance,null,2)+'\n');
await fs.rm(path.join(output,'licenses'),{recursive:true,force:true});
await fs.mkdir(path.join(output,'licenses'),{recursive:true});
async function notices(dir) {
 for (const item of await fs.readdir(dir,{withFileTypes:true})) {
  if(!item.isDirectory()||item.name.startsWith('.'))continue;
  const child=path.join(dir,item.name);
  if(item.name.startsWith('@')){await notices(child);continue;}
  let pkg;try{pkg=JSON.parse(await fs.readFile(path.join(child,'package.json'),'utf8'));}catch{continue;}
  for (const file of await fs.readdir(child)) if(/^(license|copying|notice)(\.|$)/i.test(file)) await fs.copyFile(path.join(child,file),path.join(output,'licenses',`${pkg.name.replaceAll('/','_')}-${pkg.version}-${file}`));
  try { await notices(path.join(child,'node_modules')); } catch(error) { if(error.code!=='ENOENT') throw error; }
 }
}
await notices(path.join(here,'node_modules'));
console.log('Built Chrome MV3 AdGuard integration and three pinned DNR rulesets.');
