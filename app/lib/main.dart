import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'library_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.booknarrator.audio',
    androidNotificationChannelName: 'Book playback',
    androidNotificationOngoing: true,
  );
  runApp(const BookNarratorApp());
}

class BookNarratorApp extends StatelessWidget {
  const BookNarratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Book Narrator',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
          useMaterial3: true),
      home: const LibraryScreen(),
    );
  }
}
