import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class Store {
  static Future<Directory> booksDir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'books'));
    await d.create(recursive: true);
    return d;
  }

  static Future<List<Book>> listBooks() async {
    final root = await booksDir();
    final out = <Book>[];
    await for (final e in root.list()) {
      if (e is Directory) {
        final b = await Book.load(e);
        if (b != null) out.add(b);
      }
    }
    out.sort((a, b) => a.title.compareTo(b.title));
    return out;
  }

  /// Copies picked files (book.json, *.json, *.m4a) into books/(bookId)/.
  /// The book id comes from the title inside book.json.
  static Future<Book?> importFiles(List<String> paths) async {
    final manifest = paths.where((x) => p.basename(x) == 'book.json');
    if (manifest.isEmpty) return null;
    final j = jsonDecode(await File(manifest.first).readAsString());
    final id = (j['title'] as String)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final dest = Directory(p.join((await booksDir()).path, id));
    await dest.create(recursive: true);
    for (final src in paths) {
      await File(src).copy(p.join(dest.path, p.basename(src)));
    }
    return Book.load(dest);
  }

  static Future<void> deleteBook(Book b) => Directory(b.dir).delete(recursive: true);

  // ---- progress ----
  static Future<void> saveProgress(String bookId, int chapter, int ms) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('progress:$bookId', '$chapter:$ms');
  }

  static Future<(int, int)> loadProgress(String bookId) async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString('progress:$bookId');
    if (v == null) return (0, 0);
    final parts = v.split(':');
    return (int.parse(parts[0]), int.parse(parts[1]));
  }

  // ---- bookmarks ----
  static Future<List<Bookmark>> loadBookmarks(String bookId) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('bookmarks:$bookId');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveBookmarks(String bookId, List<Bookmark> list) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('bookmarks:$bookId', jsonEncode(list.map((b) => b.toJson()).toList()));
  }
}
