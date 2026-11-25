export const FILTER_IDS = [2, 3, 11];
export const DEFAULT_SETTINGS = {enabled:true, disabledHosts:[]};

export function normalizeSettings(value) {
  return {
    enabled: typeof value?.enabled === 'boolean' ? value.enabled : true,
    disabledHosts: Array.isArray(value?.disabledHosts) ? [...new Set(value.disabledHosts.filter(host =>
      typeof host === 'string' && host.length <= 253 && /^[a-z0-9.-]+$/.test(host) && !host.startsWith('.') && !host.endsWith('.')))] : [],
  };
}
export function configuration(settings, rules) {
  return {
    filtersPath:'adguard/filters', rulesetsPath:'adguard/filters/declarative',
    staticFiltersIds:FILTER_IDS, customFilters:[], trustedDomains:[],
    declarativeLogEnabled:false, allowlist:settings.disabledHosts,
    userrules:{content:rules.join('\n')},
    settings:{
      filteringEnabled:settings.enabled, allowlistEnabled:true, allowlistInverted:false,
      collectStats:false, debugScriptlets:false, stealthModeEnabled:false,
      assistantUrl:'', gpcScriptUrl:'', hideDocumentReferrerScriptUrl:'',
      stealth:{
        selfDestructFirstPartyCookies:false, selfDestructFirstPartyCookiesTime:3600,
        selfDestructThirdPartyCookies:false, selfDestructThirdPartyCookiesTime:3600,
        hideReferrer:false, hideSearchQueries:false, blockChromeClientData:false,
        sendDoNotTrack:false, blockWebRTC:false,
      },
    },
  };
}
