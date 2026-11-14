import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'player_screen.dart';
import 'store.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<Book> _books = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final b = await Store.listBooks();
    if (mounted) setState(() => _books = b);
  }

  Future<void> _import() async {
    // Pick every file inside the generated book folder (book.json, *.json, *.m4a).
    final res = await FilePicker.pickFiles(type: FileType.any);
    if (res.isEmpty) return;
    setState(() => _busy = true);
    final paths = res.map((f) => f.path).whereType<String>().toList();
    final book = await Store.importFiles(paths);
    setState(() => _busy = false);
    if (!mounted) return;
    if (book == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No book.json among the selected files. Select all files in the book folder.')));
    } else {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book Narrator')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _import,
        icon: const Icon(Icons.library_add),
        label: Text(_busy ? 'Importing…' : 'Import book'),
      ),
      body: _books.isEmpty
          ? const Center(
              child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No books yet.\nGenerate one on your PC, copy the folder to this device, '
                'then tap Import and select all its files.',
                textAlign: TextAlign.center,
              ),
            ))
          : ListView(
              children: [
                for (final b in _books)
                  ListTile(
                    leading: const Icon(Icons.menu_book),
                    title: Text(b.title),
                    subtitle: Text('${b.chapters.length} chapters'),
                    onTap: () async {
                      await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => PlayerScreen(book: b)));
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: Text('Delete "${b.title}"?'),
                            content: const Text('This removes its audio from this device.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await Store.deleteBook(b);
                          _refresh();
                        }
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
