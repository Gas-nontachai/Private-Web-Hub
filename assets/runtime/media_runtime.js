(() => {
  if (window.__mvMedia) return window.__mvMedia.snapshot();
  const style = document.createElement('style');
  style.textContent = `html.mv-media-pip,html.mv-media-pip body{overflow:hidden!important;background:#000!important}
    html.mv-media-pip body *{visibility:hidden!important}
    html.mv-media-pip video{visibility:visible!important;position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;object-fit:contain!important;z-index:2147483647!important}`;
  document.documentElement.appendChild(style);
  let selected;
  function media() {
    if (selected?.isConnected && !selected.ended && !selected.paused) return selected;
    const items = [...document.querySelectorAll('video,audio')];
    selected = items.find(el => !el.paused && !el.ended) || items.find(el => el.readyState > 0);
    return selected;
  }
  function skipButton(action) {
    const selectors = action === 'next'
      ? ['ytmusic-player-bar .next-button', '.ytp-next-button']
      : ['ytmusic-player-bar .previous-button', '.ytp-prev-button'];
    return selectors.map(selector => document.querySelector(selector))
      .find(button => button && !button.disabled && button.getAttribute('aria-disabled') !== 'true'
        && button.getClientRects().length > 0);
  }
  window.__mvMedia = {
    snapshot() {
      const el = media();
      const metadata = navigator.mediaSession?.metadata;
      return {
        available: !!el,
        playing: !!el && !el.paused && !el.ended,
        video: el?.tagName === 'VIDEO',
        next: !!skipButton('next'),
        previous: !!skipButton('previous'),
        title: String(metadata?.title || document.title || 'Movie.exe').slice(0, 200),
        artist: String(metadata?.artist || '').slice(0, 200),
        position: Number.isFinite(el?.currentTime) ? el.currentTime : 0,
        duration: Number.isFinite(el?.duration) ? el.duration : 0,
      };
    },
    command(action) {
      const el = media();
      if (action === 'pause' || action === 'stop') {
        for (const item of document.querySelectorAll('video,audio')) item.pause();
      } else if (action === 'play') {
        if (el) el.play().catch(() => {});
      } else if (action === 'next' || action === 'previous') {
        skipButton(action)?.click();
      }
    },
    pip(active) { document.documentElement.classList.toggle('mv-media-pip', active); },
  };
  return window.__mvMedia.snapshot();
})();
