/// A small bundled list, not a full AdBlock/EasyList filter engine.
const blockedAdHosts = {
  'doubleclick.net',
  'googlesyndication.com',
  'adnxs.com',
  'pubmatic.com',
  'openx.net',
  'rubiconproject.com',
  'adsrvr.org',
  'popads.net',
  'popcash.net',
};

bool isBlockedAdUri(Uri uri) {
  if (uri.scheme != 'https' && uri.scheme != 'http') return false;
  final host = uri.host.toLowerCase();
  return blockedAdHosts.any(
    (domain) => host == domain || host.endsWith('.$domain'),
  );
}
