import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class ChapterMeta {
  final String title;
  final String audio;
  final String data;
  final double duration;
  ChapterMeta(this.title, this.audio, this.data, this.duration);

  factory ChapterMeta.fromJson(Map<String, dynamic> j) => ChapterMeta(
        j['title'] as String,
        j['audio'] as String,
        j['data'] as String,
        (j['duration'] as num).toDouble(),
      );
}

class Sentence {
  final String text;
  final Duration start;
  final Duration end;
  final String kind;
  Sentence(this.text, this.start, this.end, this.kind);

  factory Sentence.fromJson(Map<String, dynamic> j) => Sentence(
        j['text'] as String,
        Duration(milliseconds: ((j['start'] as num) * 1000).round()),
        Duration(milliseconds: ((j['end'] as num) * 1000).round()),
        (j['kind'] as String?) ?? 'narration',
      );
}

class Book {
  final String id; // folder name
  final String dir;
  final String title;
  final List<ChapterMeta> chapters;
  Book(this.id, this.dir, this.title, this.chapters);

  static Future<Book?> load(Directory d) async {
    final f = File(p.join(d.path, 'book.json'));
    if (!await f.exists()) return null;
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    final chapters = (j['chapters'] as List)
        .map((c) => ChapterMeta.fromJson(c as Map<String, dynamic>))
        .toList();
    return Book(p.basename(d.path), d.path, j['title'] as String, chapters);
  }

  String audioPath(int i) => p.join(dir, chapters[i].audio);

  Future<List<Sentence>> sentences(int i) async {
    final f = File(p.join(dir, chapters[i].data));
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return (j['sentences'] as List)
        .map((s) => Sentence.fromJson(s as Map<String, dynamic>))
        .toList();
  }
}

class Bookmark {
  final int chapter;
  final int sentence;
  final String preview;
  Bookmark(this.chapter, this.sentence, this.preview);

  Map<String, dynamic> toJson() =>
      {'c': chapter, 's': sentence, 'p': preview};
  factory Bookmark.fromJson(Map<String, dynamic> j) =>
      Bookmark(j['c'] as int, j['s'] as int, j['p'] as String);
}
