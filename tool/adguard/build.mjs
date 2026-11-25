import { build } from 'esbuild';
import { FilterList } from '@adguard/tsurlfilter';
import yaml from 'js-yaml';
import { createHash } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const output = path.resolve(here, '../../assets/adguard');
const revision = '0ba847dd94469616a3032bb810275d12e0abe4b0';
const filters = [[2, 'Base'], [3, 'Spyware'], [11, 'Mobile']];
const check = process.argv.includes('--check');
async function save(file, value) {
  const bytes = Buffer.from(value);
  if (check) {
    if (!(await fs.readFile(file)).equals(bytes)) throw new Error(`Stale generated asset: ${file}`);
  } else await fs.writeFile(file, bytes);
}
await fs.mkdir(output, {recursive:true});
if (process.argv.includes('--update-filters')) {
  const manifest = { revision, filters: [] };
  for (const [id, name] of filters) {
    const url = `https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/${revision}/platforms/extension/chromium/filters/${id}.txt`;
    const response = await fetch(url);
    if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`);
    const raw = await response.text();
    const list = new FilterList(raw, id);
    const serialized = JSON.stringify({id, content:list.getContent(), data:list.getConversionData()});
    await fs.writeFile(path.join(output, `filter_${id}.json`), serialized);
    manifest.filters.push({id,name,url,sha256:createHash('sha256').update(raw).digest('hex'),
      assetSha256:createHash('sha256').update(serialized).digest('hex'),conversionErrors:list.getConversionErrors().length});
  }
  await fs.writeFile(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2)+'\n');
}
for (const [entry, name] of [['engine.js','engine.js'], ['page.js','page.js']]) {
  const result = await build({ absWorkingDir:here, entryPoints:[entry], bundle:true, format:'iife', platform:'browser',
    define:{global:'globalThis'}, target:'es2020', minify:true, legalComments:'eof', write:false });
  await save(path.join(output,name), result.outputFiles[0].contents);
}
const redirects = yaml.safeLoad(await fs.readFile(path.join(here,'node_modules/@adguard/scriptlets/dist/redirects.yml'),'utf8'));
const resources = {};
for (const item of redirects) {
  if (!item.content || !item.contentType || item.content.includes('{{')) continue;
  for (const name of [item.title, ...(item.aliases || [])]) resources[name] = {content:item.content,contentType:item.contentType};
}
await save(path.join(output,'redirects.json'),JSON.stringify(resources));
await fs.mkdir(path.join(output,'licenses'), {recursive:true});
// Include notices for the full dependency tree, not just the direct imports.
async function notices(dir) {
  for (const item of await fs.readdir(dir, {withFileTypes:true})) {
    if (!item.isDirectory() || item.name.startsWith('.')) continue;
    const child = path.join(dir,item.name);
    if (item.name.startsWith('@')) {await notices(child);continue;}
    let pkg;
    try {pkg=JSON.parse(await fs.readFile(path.join(child,'package.json'),'utf8'));} catch {continue;}
    for (const file of await fs.readdir(child)) if (/^(license|copying|notice)(\.|$)/i.test(file)) {
      await fs.copyFile(path.join(child,file),path.join(output,'licenses',`${pkg.name.replaceAll('/','_')}-${file}`));
    }
  }
}
if (!check) await notices(path.join(here,'node_modules'));
// Preserve the reviewed license in normal builds, so verification works offline.
const filterLicense = path.join(output,'licenses','AdGuardFilters-LICENSE');
try { await fs.access(filterLicense); } catch {
  if (check) throw new Error('Missing filter license');
  const response = await fetch('https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/LICENSE');
  if (!response.ok) throw new Error('Unable to fetch filter license');
  await fs.writeFile(filterLicense,await response.text());
}
const manifest = JSON.parse(await fs.readFile(path.join(output,'manifest.json'),'utf8'));
for (const filter of manifest.filters) {
  const bytes = await fs.readFile(path.join(output,`filter_${filter.id}.json`));
  if (createHash('sha256').update(bytes).digest('hex') !== filter.assetSha256) throw new Error('Filter asset checksum mismatch');
}
console.log(check ? 'Verified AdGuard assets.' : 'Built bundled AdGuard engine, page runtime, redirects and notices.');
