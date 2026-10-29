import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const WallArtApp());

class WallArtApp extends StatelessWidget {
  const WallArtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WallArt',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.brown,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const ArtListPage(),
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

/// CDN CORS başlığı göndermediği için web'de <img> elemanına düşülür.
Widget netImage(String url, {BoxFit fit = BoxFit.cover, ImageLoadingBuilder? loadingBuilder}) =>
    Image.network(
      url,
      fit: fit,
      loadingBuilder: loadingBuilder,
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
    );

const _fields =
    'id,title,creators,creation_date,technique,measurements,culture,description,images';

Future<List<Artwork>> fetchArtworks(int page) async {
  final uri = Uri.parse(
      'https://openaccess-api.clevelandart.org/api/artworks/?has_image=1&type=Painting'
      '&fields=$_fields&limit=30&skip=${(page - 1) * 30}');
  final res = await http.get(uri);
  if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
  final data = jsonDecode(res.body)['data'] as List;
  return data
      .map((e) => Artwork.fromJson(e))
      .where((a) => a.webUrl.isNotEmpty)
      .toList();
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
      appBar: AppBar(title: const Text('WallArt')),
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
        child: netImage(
          art.imageUrl(context, wide ? size.width * 0.6 : size.width),
          fit: BoxFit.contain,
          // Büyük görsel gelene kadar küçük web görseli gösterilir.
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : netImage(art.webUrl, fit: BoxFit.contain),
        ),
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
        if (art.description.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(art.description),
        ],
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(art.title, overflow: TextOverflow.ellipsis)),
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
