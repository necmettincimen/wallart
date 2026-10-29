{{flutter_js}}
{{flutter_build_config}}

// İlk kare çizilince splash kaldırılır; eski Flutter service worker'ı yerine kurulabilir PWA için sw.js kullanılır.
window.addEventListener('flutter-first-frame', () => document.getElementById('splash')?.remove());
if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js');
_flutter.loader.load();
