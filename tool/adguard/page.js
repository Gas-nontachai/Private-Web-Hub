import { scriptlets } from '@adguard/scriptlets';
import { ExtendedCss } from '@adguard/extended-css';

// All executable code is bundled. The bridge only returns rule data.
(() => {
  const config = __MV_ADGUARD_CONFIG__;
  if (window.__mvAdguard) return;
  const state = window.__mvAdguard = { scripts: new Set(), styles: new Set(), extended: [], applied: false };
  const url = location.href;
  const owned = new Set((config.owned[location.hostname] || []));
  const apply = (rules) => {
    if (!rules || location.href !== url || state.applied) return;
    state.applied = true;
    if (config.cosmetic) {
      const css = rules.css.filter((line) => {
        const selector = line.replace(/\s*\{ display: none !important; \}$/, '');
        return !owned.has(selector) && !state.styles.has(line);
      });
      css.forEach((line) => state.styles.add(line));
      if (css.length) {
        const style = document.createElement('style');
        style.dataset.mvAdguard = 'true';
        style.textContent = css.join('\n');
        const install = () => {
          if (document.documentElement) {
            (document.head || document.documentElement).appendChild(style);
          } else {
            const observer = new MutationObserver(() => {
              if (document.documentElement) { observer.disconnect(); install(); }
            });
            observer.observe(document, {childList:true});
          }
        };
        install();
      }
      if (rules.extended.length) {
        const install = () => {
          try {
            const extended = new ExtendedCss({ styleSheet: [...new Set(rules.extended)].join('\n') });
            extended.apply();
            state.extended.push(extended);
          } catch (_) { /* A malformed cosmetic rule must not break the page. */ }
        };
        if (document.documentElement) install();
        else document.addEventListener('DOMContentLoaded', install, {once:true});
      }
    }
    if (config.scriptlets) for (const source of rules.scripts) {
      const key = JSON.stringify([source.name, source.args]);
      if (state.scripts.has(key)) continue;
      state.scripts.add(key);
      try { scriptlets.getScriptletFunction(source.name)?.(source, source.args || []); }
      catch (_) { /* One incompatible scriptlet must not disable the others. */ }
    }
  };
  if (config.initialUrl === url && window === window.top && config.initialRules) apply(config.initialRules);
  else {
    const load = () => {
      const handler = window.flutter_inappwebview;
      if (handler) handler.callHandler('mvAdguardRules', url, document.referrer).then(apply).catch(() => {});
    };
    if (window.flutter_inappwebview?.callHandler) load();
    else window.addEventListener('flutterInAppWebViewPlatformReady', load, {once:true});
  }
  window.addEventListener('pagehide', (event) => {
    if (!event.persisted) state.extended.forEach((instance) => instance.dispose());
  }, {once:true});
})();
