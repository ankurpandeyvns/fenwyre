(() => {
  const isAV1 = t => typeof t === 'string' && /av01|av1/i.test(t);
  const ms = window.MediaSource;
  if (ms && ms.isTypeSupported) {
    const orig = ms.isTypeSupported.bind(ms);
    ms.isTypeSupported = t => isAV1(t) ? false : orig(t);
  }
  if (window.ManagedMediaSource && ManagedMediaSource.isTypeSupported) {
    const o2 = ManagedMediaSource.isTypeSupported.bind(ManagedMediaSource);
    ManagedMediaSource.isTypeSupported = t => isAV1(t) ? false : o2(t);
  }
  const cpt = HTMLMediaElement.prototype.canPlayType;
  HTMLMediaElement.prototype.canPlayType = function (t) { return isAV1(t) ? '' : cpt.call(this, t); };
  const mc = navigator.mediaCapabilities;
  if (mc && mc.decodingInfo) {
    const di = mc.decodingInfo.bind(mc);
    mc.decodingInfo = cfg => {
      const ct = cfg && cfg.video && cfg.video.contentType;
      return isAV1(ct) ? Promise.resolve({ supported: false, smooth: false, powerEfficient: false }) : di(cfg);
    };
  }
})();
