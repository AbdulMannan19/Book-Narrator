import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'models.dart';
import 'store.dart';

class PlayerScreen extends StatefulWidget {
  final Book book;
  const PlayerScreen({super.key, required this.book});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _player = AudioPlayer();
  final _scroll = AutoScrollController();
  List<Sentence> _sentences = [];
  List<Bookmark> _bookmarks = [];
  int _chapter = 0;
  int _current = -1;
  bool _follow = true;
  double _speed = 1.0;
  Duration _lastSaved = Duration.zero;
  StreamSubscription? _posSub, _stateSub;

  Book get book => widget.book;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _bookmarks = await Store.loadBookmarks(book.id);
    final (ch, ms) = await Store.loadProgress(book.id);
    await _loadChapter(ch.clamp(0, book.chapters.length - 1), Duration(milliseconds: ms));

    _posSub = _player.positionStream.listen(_onPosition);
    _stateSub = _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed && _chapter < book.chapters.length - 1) {
        _loadChapter(_chapter + 1, Duration.zero, autoplay: true);
      }
    });
  }

  Future<void> _loadChapter(int i, Duration at, {bool autoplay = false}) async {
    final sentences = await book.sentences(i);
    setState(() {
      _chapter = i;
      _sentences = sentences;
      _current = -1;
    });
    await _player.setAudioSource(
      AudioSource.file(
        book.audioPath(i),
        tag: MediaItem(
          id: '${book.id}/$i',
          album: book.title,
          title: book.chapters[i].title,
        ),
      ),
      initialPosition: at,
    );
    if (autoplay) _player.play();
  }

  int _indexAt(Duration pos) {
    // Last sentence whose start <= pos (binary search).
    var lo = 0, hi = _sentences.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (_sentences[mid].start <= pos) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  void _onPosition(Duration pos) {
    final idx = _indexAt(pos);
    if (idx != _current) {
      setState(() => _current = idx);
      if (_follow && idx >= 0) {
        _scroll.scrollToIndex(idx,
            preferPosition: AutoScrollPosition.middle,
            duration: const Duration(milliseconds: 300));
      }
    }
    if ((pos - _lastSaved).abs() > const Duration(seconds: 5)) {
      _lastSaved = pos;
      Store.saveProgress(book.id, _chapter, pos.inMilliseconds);
    }
  }

  Future<void> _toggleBookmark(int i) async {
    final existing = _bookmarks.indexWhere((b) => b.chapter == _chapter && b.sentence == i);
    setState(() {
      if (existing >= 0) {
        _bookmarks.removeAt(existing);
      } else {
        final t = _sentences[i].text;
        _bookmarks.add(Bookmark(_chapter, i, t.length > 80 ? '${t.substring(0, 80)}…' : t));
      }
    });
    await Store.saveBookmarks(book.id, _bookmarks);
  }

  bool _isBookmarked(int i) => _bookmarks.any((b) => b.chapter == _chapter && b.sentence == i);

  Future<void> _jumpTo(int chapter, int sentence) async {
    if (chapter != _chapter) {
      await _loadChapter(chapter, Duration.zero);
    }
    final s = (await book.sentences(chapter))[sentence];
    await _player.seek(s.start);
    _player.play();
  }

  void _showChapters() {
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView(children: [
        for (var i = 0; i < book.chapters.length; i++)
          ListTile(
            selected: i == _chapter,
            title: Text(book.chapters[i].title),
            onTap: () {
              Navigator.pop(context);
              _loadChapter(i, Duration.zero, autoplay: true);
            },
          ),
      ]),
    );
  }

  void _showBookmarks() {
    showModalBottomSheet(
      context: context,
      builder: (_) => _bookmarks.isEmpty
          ? const Center(child: Text('Long-press a sentence to bookmark it.'))
          : ListView(children: [
              for (final b in _bookmarks)
                ListTile(
                  title: Text(b.preview, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(book.chapters[b.chapter].title),
                  onTap: () {
                    Navigator.pop(context);
                    _jumpTo(b.chapter, b.sentence);
                  },
                ),
            ]),
    );
  }

  @override
  void dispose() {
    Store.saveProgress(book.id, _chapter, _player.position.inMilliseconds);
    _posSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(book.chapters.isEmpty ? book.title : book.chapters[_chapter].title,
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(icon: const Icon(Icons.bookmarks_outlined), onPressed: _showBookmarks),
          IconButton(icon: const Icon(Icons.list), onPressed: _showChapters),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: NotificationListener<UserScrollNotification>(
            onNotification: (n) {
              if (n.direction != ScrollDirection.idle && _follow) {
                setState(() => _follow = false);
              }
              return false;
            },
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: _sentences.length,
              itemBuilder: (_, i) {
                final s = _sentences[i];
                final active = i == _current;
                return AutoScrollTag(
                  key: ValueKey(i),
                  controller: _scroll,
                  index: i,
                  child: InkWell(
                    onTap: () {
                      _player.seek(s.start);
                      _player.play();
                      setState(() => _follow = true);
                    },
                    onLongPress: () => _toggleBookmark(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: active ? cs.primaryContainer : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (_isBookmarked(i))
                          const Padding(
                            padding: EdgeInsets.only(right: 6, top: 3),
                            child: Icon(Icons.bookmark, size: 16),
                          ),
                        Expanded(
                          child: Text(
                            s.text,
                            style: TextStyle(
                              fontSize: s.kind == 'title' ? 22 : 18,
                              height: 1.5,
                              fontWeight: s.kind == 'title' ? FontWeight.bold : null,
                              fontStyle: s.kind == 'dialogue' ? FontStyle.italic : null,
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        _controls(),
      ]),
      floatingActionButton: _follow || _current < 0
          ? null
          : FloatingActionButton.small(
              onPressed: () {
                setState(() => _follow = true);
                _scroll.scrollToIndex(_current, preferPosition: AutoScrollPosition.middle);
              },
              child: const Icon(Icons.my_location),
            ),
    );
  }

  Widget _controls() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          StreamBuilder<Duration?>(
            stream: _player.durationStream,
            builder: (_, dsnap) {
              final total = dsnap.data ?? Duration.zero;
              return StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (_, psnap) {
                  final pos = psnap.data ?? Duration.zero;
                  final max = total.inMilliseconds.toDouble();
                  return Row(children: [
                    Text(_fmt(pos)),
                    Expanded(
                      child: Slider(
                        value: pos.inMilliseconds.toDouble().clamp(0, max <= 0 ? 1 : max),
                        max: max <= 0 ? 1 : max,
                        onChanged: (v) => _player.seek(Duration(milliseconds: v.round())),
                      ),
                    ),
                    Text(_fmt(total)),
                  ]);
                },
              );
            },
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            IconButton(
              icon: const Icon(Icons.skip_previous),
              onPressed: _chapter > 0 ? () => _loadChapter(_chapter - 1, Duration.zero, autoplay: true) : null,
            ),
            IconButton(
              icon: const Icon(Icons.replay_10),
              onPressed: () => _player.seek(_player.position - const Duration(seconds: 10)),
            ),
            StreamBuilder<bool>(
              stream: _player.playingStream,
              builder: (_, snap) {
                final playing = snap.data ?? false;
                return IconButton.filled(
                  iconSize: 36,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  onPressed: playing ? _player.pause : _player.play,
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.forward_10),
              onPressed: () => _player.seek(_player.position + const Duration(seconds: 10)),
            ),
            IconButton(
              icon: const Icon(Icons.skip_next),
              onPressed: _chapter < book.chapters.length - 1
                  ? () => _loadChapter(_chapter + 1, Duration.zero, autoplay: true)
                  : null,
            ),
            TextButton(
              onPressed: () {
                const speeds = [0.8, 1.0, 1.15, 1.3, 1.5, 2.0];
                final next = speeds[(speeds.indexOf(_speed) + 1) % speeds.length];
                setState(() => _speed = next);
                _player.setSpeed(next);
              },
              child: Text('${_speed}x'),
            ),
          ]),
        ]),
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0'), ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }
}
