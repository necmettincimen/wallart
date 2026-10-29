import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const WallArtApp());

/// Varsayılan sistem teması; AppBar'daki düğme açık/koyu arasında geçiş yapar.
final themeMode = ValueNotifier(ThemeMode.system);

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? Colors.black : Colors.white;
  final fg = dark ? Colors.white : Colors.black;
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.grey,
      brightness: b,
      dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
      surface: bg,
      onSurface: fg,
      primary: fg,
    ),
    appBarTheme: AppBarTheme(backgroundColor: bg, foregroundColor: fg),
    cardTheme: CardThemeData(color: dark ? Colors.grey.shade900 : Colors.grey.shade200),
  );
}

class WallArtApp extends StatelessWidget {
  const WallArtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'WallArt',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: mode,
        home: const HomePage(),
      ),
    );
  }
}

class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: dark ? 'Açık tema' : 'Koyu tema',
      icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
      onPressed: () => themeMode.value = dark ? ThemeMode.light : ThemeMode.dark,
    );
  }
}

/// Cleveland Museum of Art açık API'sinden gelen eser.
class Artwork {
  final int id;
  final String title;
  final String artist;
  final String date;
  final String medium;
  final String dimensions;
  final String origin;
  final String description;
  final String webUrl;
  final String printUrl;

  Artwork.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        title = j['title'] ?? 'İsimsiz',
        artist = ((j['creators'] as List?) ?? [])
            .map((c) => c['description'] ?? '')
            .join('\n'),
        date = j['creation_date'] ?? '',
        medium = j['technique'] ?? '',
        dimensions = j['measurements'] ?? '',
        origin = ((j['culture'] as List?) ?? []).join(', '),
        description = (j['description'] ?? '')
            .toString()
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .trim(),
        webUrl = j['images']?['web']?['url'] ?? '',
        printUrl = (j['images']?['print']?['url']) ?? (j['images']?['web']?['url']) ?? '';

  /// Fiziksel piksel genişliğine göre web (~750px) ya da baskı (~3400px) görseli.
  String imageUrl(BuildContext context, double logicalWidth) =>
      logicalWidth * MediaQuery.devicePixelRatioOf(context) > 800 ? printUrl : webUrl;
}

/// CDN CORS başlığı göndermediği için web'de doğrudan <img> elemanı kullanılır;
/// önce XHR denenmediğinden konsolda CORS hatası oluşmaz.
Widget netImage(String url, {BoxFit fit = BoxFit.cover}) =>
    Image.network(
      url,
      fit: fit,
      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      // Görsel gelene kadar yükleniyor göstergesi.
      frameBuilder: (_, child, frame, sync) => sync || frame != null
          ? child
          : const Center(child: CircularProgressIndicator()),
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
    );

const _fields =
    'id,title,creators,creation_date,technique,measurements,culture,description,images';

Future<Map<String, dynamic>> _query(int limit, int skip) async {
  final uri = Uri.parse(
      'https://openaccess-api.clevelandart.org/api/artworks/?has_image=1&type=Painting'
      '&fields=$_fields&limit=$limit&skip=$skip');
  final res = await http.get(uri);
  if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
  return jsonDecode(res.body);
}

Future<List<Artwork>> fetchArtworks(int page) async {
  final data = (await _query(30, (page - 1) * 30))['data'] as List;
  return data
      .map((e) => Artwork.fromJson(e))
      .where((a) => a.webUrl.isNotEmpty)
      .toList();
}

/// Koleksiyonda ~3900 tablo var; sayıyı sabit tutmak açılışta fazladan
/// bir sıralı isteği önler.
const _collectionSize = 3900;

Future<Artwork> fetchArtworkAt(int index) async =>
    Artwork.fromJson(((await _query(1, index))['data'] as List).first);

/// Tarihe göre sabit sıra: aynı gün herkes aynı tabloyu görür.
Future<Artwork> fetchDailyArtwork() {
  final now = DateTime.now();
  final day = DateTime.utc(now.year, now.month, now.day)
      .difference(DateTime.utc(2000))
      .inDays;
  // Ardışık günlerde benzer eserler gelmesin diye asal sayıyla dağıtılır.
  return fetchArtworkAt(day * 7919 % _collectionSize);
}

Future<Artwork> fetchRandomArtwork() =>
    fetchArtworkAt(Random().nextInt(_collectionSize));

/// Görseli en yüksek çözünürlükte yeni sekmede açar.
class OpenImageButton extends StatelessWidget {
  final Artwork art;
  const OpenImageButton({super.key, required this.art});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Yeni sekmede aç',
        icon: const Icon(Icons.open_in_new),
        onPressed: () => launchUrl(Uri.parse(art.printUrl), webOnlyWindowName: '_blank'),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<Artwork> _art = fetchDailyArtwork();
  bool _daily = true;

  void _show(Future<Artwork> art, bool daily) => setState(() {
        _art = art;
        _daily = daily;
      });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('WallArt'), actions: const [ThemeToggle()]),
      body: FutureBuilder<Artwork>(
        future: _art,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => _show(_daily ? fetchDailyArtwork() : fetchRandomArtwork(), _daily),
                child: Text('Tekrar dene\n${snap.error}'),
              ),
            );
          }
          if (!snap.hasData || snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final art = snap.data!;
          // stretch: Column ekran genişliğini kaplar, içerik ortada kalır.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(_daily ? 'Günün Tablosu' : 'Rastgele Tablo',
                    textAlign: TextAlign.center, style: text.titleLarge),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ArtDetailPage(art: art)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Hero(tag: art.id, child: netImage(art.webUrl, fit: BoxFit.contain)),
                  ),
                ),
              ),
              Text(art.title,
                  textAlign: TextAlign.center, style: text.titleMedium, maxLines: 2),
              Text(art.artist.split('\n').first,
                  textAlign: TextAlign.center, style: text.bodyMedium),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _show(fetchRandomArtwork(), false),
                      icon: const Icon(Icons.shuffle),
                      label: const Text('Rastgele'),
                    ),
                    if (!_daily)
                      OutlinedButton.icon(
                        onPressed: () => _show(fetchDailyArtwork(), true),
                        icon: const Icon(Icons.today),
                        label: const Text('Günün tablosu'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ArtListPage()),
                      ),
                      icon: const Icon(Icons.grid_view),
                      label: const Text('Tüm tablolar'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ArtListPage extends StatefulWidget {
  const ArtListPage({super.key});

  @override
  State<ArtListPage> createState() => _ArtListPageState();
}

class _ArtListPageState extends State<ArtListPage> {
  final _items = <Artwork>[];
  final _scroll = ScrollController();
  int _page = 1;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 800) _load();
    });
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final more = await fetchArtworks(_page);
      setState(() {
        _items.addAll(more);
        _page++;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // Ekran genişliğine göre sütun sayısı: telefonda 2, tablette 3-4, masaüstünde daha fazla.
    final columns = (width / 260).floor().clamp(2, 8);

    return Scaffold(
      appBar: AppBar(title: const Text('WallArt'), actions: const [ThemeToggle()]),
      body: _items.isEmpty && _error != null
          ? Center(
              child: TextButton(onPressed: _load, child: Text('Tekrar dene\n$_error')))
          : GridView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(8),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.75,
              ),
              itemCount: _items.length + (_loading ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= _items.length) {
                  return const Center(child: CircularProgressIndicator());
                }
                final a = _items[i];
                return _ArtTile(art: a);
              },
            ),
    );
  }
}

class _ArtTile extends StatelessWidget {
  final Artwork art;

  const _ArtTile({required this.art});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ArtDetailPage(art: art)),
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: art.id,
              child: netImage(art.webUrl),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black54,
                child: Text(
                  art.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ArtDetailPage extends StatelessWidget {
  final Artwork art;
  const ArtDetailPage({super.key, required this.art});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width > 900;

    final image = Hero(
      tag: art.id,
      child: InteractiveViewer(
        maxScale: 5,
        // Büyük görsel gelene kadar alttaki küçük web görseli görünür.
        child: Stack(fit: StackFit.expand, children: [
          netImage(art.webUrl, fit: BoxFit.contain),
          netImage(art.imageUrl(context, wide ? size.width * 0.6 : size.width),
              fit: BoxFit.contain),
        ]),
      ),
    );

    final info = ListView(
      padding: const EdgeInsets.all(16),
      shrinkWrap: !wide,
      physics: wide ? null : const NeverScrollableScrollPhysics(),
      children: [
        Text(art.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(art.artist, style: Theme.of(context).textTheme.titleMedium),
        const Divider(height: 32),
        _row('Tarih', art.date),
        _row('Teknik', art.medium),
        _row('Boyut', art.dimensions),
        _row('Köken', art.origin),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => launchUrl(Uri.parse(art.printUrl), webOnlyWindowName: '_blank'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Yeni sekmede aç'),
          ),
        ),
        if (art.description.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(art.description),
        ],
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(art.title, overflow: TextOverflow.ellipsis),
        actions: [OpenImageButton(art: art), const ThemeToggle()],
      ),
      body: wide
          ? Row(children: [
              Expanded(flex: 3, child: image),
              Expanded(flex: 2, child: info),
            ])
          : ListView(children: [
              SizedBox(height: size.height * 0.55, child: image),
              info,
            ]),
    );
  }

  Widget _row(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
