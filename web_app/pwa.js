let deferredInstallPrompt = null;

function isStandalonePwa() {
  return window.matchMedia('(display-mode: standalone)').matches
    || window.navigator.standalone === true;
}

function isIOS() {
  return /iphone|ipad|ipod/i.test(navigator.userAgent);
}

function isInAppBrowser() {
  return /FBAN|FBAV|Instagram|Line\/|WhatsApp/i.test(navigator.userAgent);
}

function updateInstallUi() {
  const banner = document.getElementById('pwa-install-banner');
  const iosHint = document.getElementById('install-hint-ios');
  const inAppHint = document.getElementById('install-hint-inapp');
  const androidHint = document.getElementById('install-hint-android');

  if (isStandalonePwa()) {
    [banner, iosHint, inAppHint, androidHint].forEach((el) => {
      if (el) el.style.display = 'none';
    });
    return;
  }

  if (inAppHint && isInAppBrowser()) {
    inAppHint.style.display = 'block';
    if (iosHint) iosHint.style.display = 'none';
    if (androidHint) androidHint.style.display = 'none';
    if (banner) banner.style.display = 'none';
    return;
  }
  if (inAppHint) inAppHint.style.display = 'none';

  if (banner && deferredInstallPrompt) {
    banner.style.display = 'block';
    if (iosHint) iosHint.style.display = 'none';
    if (androidHint) androidHint.style.display = 'none';
    return;
  }

  if (iosHint && isIOS()) {
    iosHint.style.display = 'block';
    if (androidHint) androidHint.style.display = 'none';
    return;
  }

  if (androidHint) androidHint.style.display = 'block';
}

window.installPwa = async function installPwa() {
  if (!deferredInstallPrompt) return;
  deferredInstallPrompt.prompt();
  try {
    await deferredInstallPrompt.userChoice;
  } finally {
    deferredInstallPrompt = null;
    updateInstallUi();
  }
};

window.addEventListener('beforeinstallprompt', (event) => {
  event.preventDefault();
  deferredInstallPrompt = event;
  updateInstallUi();
});

window.addEventListener('appinstalled', () => {
  deferredInstallPrompt = null;
  updateInstallUi();
});

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch(() => {});
    updateInstallUi();
  });
} else {
  window.addEventListener('load', updateInstallUi);
}
