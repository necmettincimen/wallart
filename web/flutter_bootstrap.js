{{flutter_js}}
{{flutter_build_config}}

// İlk kare çizilince splash kaldırılır; eski Flutter service worker'ı kullanılmaz.
window.addEventListener('flutter-first-frame', () => document.getElementById('splash')?.remove());
_flutter.loader.load();
