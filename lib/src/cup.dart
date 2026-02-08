import 'package:tapioca_v2/src/video_editor.dart';

import 'tapioca_ball.dart';
import 'content.dart';

/// Cup is a class to wrap a Content object and List object.
class Cup {
  /// Returns the [Content] instance for applying filters.
  final Content content;

  /// Returns the [List<TapiocaBall>] instance.
  final List<TapiocaBall> tapiocaBalls;

  /// Creates a Cup object.
  Cup(this.content, this.tapiocaBalls);

  /// Edit the video based on the [tapiocaBalls](list of processing)
  /// 
  /// [onProgress] receives progress updates as a percentage (0-100)
  Future suckUp(
    String destFilePath,
    double inTime,
    double outTime,
    {void Function(double progress)? onProgress}
  ) {
    // Build processing map with unique keys for duplicate types.
    // If there are two ImageOverlay entries, they become
    // "ImageOverlay" and "ImageOverlay_1" so the map doesn't drop one.
    final Map<String, Map<String, dynamic>> processing = {};
    final typeCounts = <String, int>{};
    for (var v in tapiocaBalls) {
      final baseName = v.toTypeName();
      final count = typeCounts[baseName] ?? 0;
      typeCounts[baseName] = count + 1;
      final key = count == 0 ? baseName : '${baseName}_$count';
      processing[key] = v.toMap();
    }

    return VideoEditorTapioca.writeVideofile(
      content.name,
      destFilePath,
      inTime,
      outTime,
      processing,
      onProgress: onProgress,
    );
  }

  Future cancelExport() {
    return VideoEditorTapioca.cancelExport();
  }
}
