import { Engine, FilterList, NetworkRule, NetworkRuleOption, Request, RequestType, setConfiguration } from '@adguard/tsurlfilter';

let engine;
let compatibility = [];
const http = (url) => typeof url === 'string' && /^https?:\/\//i.test(url) && url.length <= 16384;
const text = (rule) => rule.getIndex() < 0 ? rule.getText() : engine.retrieveRuleText(rule.getFilterListId(), rule.getIndex()) || rule.getText();
function entry(context) {
  return compatibility.filter((item) => item.siteId === context.siteId &&
    (item.host === context.host || context.host.endsWith(`.${item.host}`)));
}
function request(context) {
  if (!http(context.url) || !http(context.sourceUrl)) throw new Error('Invalid request URL');
  const req = new Request(context.url, context.sourceUrl, RequestType[context.type] || RequestType.Other);
  if (typeof context.method === 'string' && /^(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|CONNECT|TRACE)$/.test(context.method)) req.method = context.method;
  return req;
}
globalThis.adguard = {
  init(filters, config = []) {
    if (!Array.isArray(config) || config.some((item) =>
      !item || typeof item.siteId !== 'string' || typeof item.host !== 'string' || !/^[a-z0-9.-]+$/.test(item.host) ||
      Object.keys(item).some((key) => !['siteId', 'host', 'networkExceptions', 'disabledRules', 'disabledScriptlets'].includes(key)) ||
      ['networkExceptions', 'disabledRules', 'disabledScriptlets'].some((key) => !Array.isArray(item[key]) || item[key].some((v) => typeof v !== 'string' || v.length > 4096)))) {
      throw new Error('Invalid compatibility configuration');
    }
    compatibility = config.map((item) => ({ ...item, exceptions: item.networkExceptions.map((line) => {
      const rule = new NetworkRule(line);
      if (!rule.isAllowlist()) throw new Error('Compatibility network rules must be exceptions');
      return rule;
    }) }));
    setConfiguration({ engine: 'extension', version: '1.0.0', verbose: false });
    engine = Engine.createSync({ filters: filters.map((f) => ({ id: f.id,
      content: typeof f.content === 'string' && f.data ? new FilterList(f.content, f.id, f.data) : f.content })) });
    return { rules: engine.getRulesCount(), conversionErrors: engine.getConversionErrors().length };
  },
  evaluateRequest(context) {
    const req = request(context);
    const overrides = entry(context);
    if (overrides.some((item) => item.exceptions.some((rule) => rule.match(req)))) return { block: false };
    const result = engine.matchRequest(req, engine.matchFrame(context.sourceUrl));
    const rule = result.getBasicResult();
    if (!rule || rule.isAllowlist() || overrides.some((item) => item.disabledRules.includes(text(rule)))) return { block: false };
    const redirect = rule.isOptionEnabled(NetworkRuleOption.Redirect) ? rule.getAdvancedModifierValue() : null;
    return { block: true, redirect, rule: text(rule) };
  },
  getPageRules(context) {
    const req = request({ ...context, type: 'Document' });
    const frame = engine.matchFrame(context.url);
    const result = engine.matchRequest(req, frame);
    const cosmetic = engine.getCosmeticResult(req, result.getCosmeticOption());
    const overrides = entry(context);
    const enabled = (rule) => !overrides.some((item) => item.disabledRules.includes(text(rule)));
    const collect = (group, ext = false) => ['elementHiding', 'CSS'].flatMap((key) =>
      cosmetic[key][group].filter(enabled).map((rule) => key === 'CSS' ? rule.getContent() : `${rule.getContent()} { display: none !important; }`));
    return {
      css: [...new Set([...collect('generic'), ...collect('specific')])],
      extended: [...new Set([...collect('genericExtCss', true), ...collect('specificExtCss', true)])],
      scripts: cosmetic.getScriptRules().filter((rule) => rule.isScriptlet && enabled(rule)).flatMap((rule) => {
        const data = rule.getScriptletData();
        // Click/tap automation belongs exclusively to the app's existing runtime.
        if (data && ['trusted-click-element', 'trusted-dispatch-event'].includes(data.params.name)) return [];
        if (!data || overrides.some((item) => item.disabledScriptlets.includes(data.params.name))) return [];
        return [{ ...data.params, domainName: context.host }];
      }),
      unsupportedHtmlRules: cosmetic.Html.getRules().length,
    };
  },
};
