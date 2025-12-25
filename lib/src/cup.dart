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
    final Map<String, Map<String, dynamic>> processing = {
      for (var v in tapiocaBalls) v.toTypeName(): v.toMap()
    };
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
