(() => {
  const queue = [];
  const flush = () => {
    if (!window.flutter_inappwebview?.callHandler) return;
    while (queue.length) window.flutter_inappwebview.callHandler('mvAdguardEngine',queue.shift());
  };
  window.addEventListener('flutterInAppWebViewPlatformReady',flush);
  const worker = window.mvAdguardWorker = new Worker('worker.js');
  worker.onmessage = ({data}) => {queue.push(data);flush();};
  worker.onerror = (error) => {queue.push({kind:'fatal',error:error.message || 'Filter worker failed'});flush();};
})();
