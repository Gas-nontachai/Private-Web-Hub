// This worker is served exclusively from reviewed APK assets in a private WebView.
importScripts('engine.js');
(async () => {
  try {
    const filters = await Promise.all([2, 3, 11].map(async id => {
      const response = await fetch(`filter_${id}.json`);
      if (!response.ok) throw new Error(`Filter ${id}: HTTP ${response.status}`);
      return response.json();
    }));
    const response = await fetch('compatibility.json');
    if (!response.ok) throw new Error('Missing compatibility configuration');
    const stats = adguard.init(filters, await response.json());
    self.postMessage({kind:'ready',rules:stats.rules});
  } catch (error) { self.postMessage({kind:'fatal',error:String(error)}); }
})();
self.onmessage = ({data}) => {
  try {
    if (!['evaluateRequest','getPageRules'].includes(data.method)) throw new Error('Invalid engine method');
    self.postMessage({kind:'result',id:data.id,result:adguard[data.method](data.context)});
  } catch (error) { self.postMessage({kind:'result',id:data.id,result:null,error:String(error)}); }
};
