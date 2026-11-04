import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/preloaded_data.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _logger = Logger('LocalProfilePicture');

/// Prefix of the file name of the profile picture.
const _kFilePrefix = 'profile_picture_';

/// The profile picture the user chose for themselves.
///
/// It is only stored on this device and only shown to the user: lichess has no profile pictures,
/// so nobody else sees it.
final localProfilePictureProvider = AsyncNotifierProvider<LocalProfilePictureNotifier, File?>(
  LocalProfilePictureNotifier.new,
  name: 'LocalProfilePictureProvider',
);

class LocalProfilePictureNotifier() extends AsyncNotifier<File?> {
  Directory? get _directory => ref.read(preloadedDataProvider).requireValue.appSupportDirectory;

  /// The stored pictures. Each one gets a new name, so that the image cache never shows a
  /// previous picture.
  List<File> _storedPictures() {
    final directory = _directory;
    if (directory == null || !directory.existsSync()) return const [];
    return directory
        .listSync()
        .whereType<File>()
        .where((file) => p.basename(file.path).startsWith(_kFilePrefix))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  @override
  Future<File?> build() async {
    return _storedPictures().lastOrNull;
  }

  /// Replaces the profile picture with the image [bytes].
  Future<void> setPicture(Uint8List bytes) async {
    final directory = _directory;
    if (directory == null) {
      _logger.warning('No storage directory for the profile picture');
      return;
    }
    final previous = _storedPictures();
    final file = File(
      p.join(directory.path, '$_kFilePrefix${DateTime.now().millisecondsSinceEpoch}.jpg'),
    );
    await file.writeAsBytes(bytes, flush: true);
    for (final old in previous) {
      await old.delete();
    }
    state = AsyncData(file);
  }

  /// Removes the profile picture, going back to the default avatar.
  Future<void> remove() async {
    for (final old in _storedPictures()) {
      await old.delete();
    }
    state = const AsyncData(null);
  }
}
