import { TsWebExtension, MESSAGE_HANDLER_NAME } from '@adguard/tswebextension/mv3';
import { configuration, normalizeSettings, FILTER_IDS } from './config.js';
import rules from './compatibility.generated.json';

const KEY = 'movieExtensionAdguard';
const engine = new TsWebExtension('/web-accessible-resources');
TsWebExtension.setLocalScriptRules({}); // Raw JavaScript rules stay disabled; bundled scriptlets remain available.
let settings;
let failure = null;
const ready = (async () => {
  settings = normalizeSettings((await chrome.storage.local.get(KEY))[KEY]);
  await engine.initStorage();
  const result = await engine.start(configuration(settings, rules));
  if (result.staticFiltersStatus?.errors?.length) throw new Error('Chrome could not enable all AdGuard rulesets');
})().catch(error => {failure = [error.message, error.cause?.message || String(error.cause || ''), error.cause?.cause?.message].filter(Boolean).join(' '); console.error('Movie.exe AdGuard:', error);});
let mutations = Promise.resolve();

async function state() {
  const [tab] = await chrome.tabs.query({active:true,lastFocusedWindow:true});
  let host = null;
  try {const url = new URL(tab?.url); if (['http:','https:'].includes(url.protocol)) host=url.hostname.toLowerCase();} catch (_) {}
  return {settings,host,error:failure,rules:engine.isStarted ? engine.getRulesCount() : 0};
}
async function handle(message, sender) {
  await ready;
  if (message?.handlerName === MESSAGE_HANDLER_NAME) {
    if (failure) return null;
    return engine.getMessageHandler()(message,sender);
  }
  if (message?.type === 'MOVIE_ADGUARD_STATE') return state();
  if (message?.type !== 'MOVIE_ADGUARD_SET') return undefined;
  if (sender.url !== chrome.runtime.getURL('popup/index.html')) throw new Error('Settings can only be changed in the popup');
  if (failure) throw new Error(failure);
  const current = await state();
  const next = {...settings, disabledHosts:[...settings.disabledHosts]};
  if (message.key === 'enabled' && typeof message.value === 'boolean') next.enabled=message.value;
  else if (message.key === 'siteEnabled' && typeof message.value === 'boolean' && current.host && message.host === current.host) {
    next.disabledHosts=next.disabledHosts.filter(host=>host !== current.host);
    if (!message.value) next.disabledHosts.push(current.host);
  } else throw new Error('Invalid extension setting');
  try {
    const result=await engine.configure(configuration(next,rules));
    if (result.staticFiltersStatus?.errors?.length) throw new Error('Chrome could not enable all AdGuard rulesets');
    await chrome.storage.local.set({[KEY]:next});
  } catch (error) {
    await engine.configure(configuration(settings,rules));
    throw error;
  }
  settings=next;
  return state();
}
// Register synchronously: MV3 may wake this worker for the first content-script message.
chrome.runtime.onMessage.addListener((message,sender,respond) => {
  if (sender.id !== chrome.runtime.id) return false;
  if (message?.type === 'MOVIE_ADGUARD_SET') {
    const update = mutations.then(()=>handle(message,sender));
    mutations=update.catch(()=>{});
    update.then(respond,error=>respond({error:error.message}));
  } else handle(message,sender).then(respond,error=>respond({error:error.message}));
  return true;
});
