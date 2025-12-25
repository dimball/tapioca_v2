import 'dart:async';
import 'package:flutter/services.dart';

abstract class IVideoEditor {}

class _VideoEditorImpl extends IVideoEditor {
  _VideoEditorImpl._();

  static _VideoEditorImpl? _instance;

  static _VideoEditorImpl get instance {
    return _instance ??= _VideoEditorImpl._();
  }
}

// ignore: non_constant_identifier_names
IVideoEditor get VideoEditorV2 => _VideoEditorImpl.instance;

extension VideoEditorTapioca on IVideoEditor {
  static const MethodChannel _channel = MethodChannel('video_editor');
  static const EventChannel _progressChannel = EventChannel('video_editor_progress');

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  /// Write video file with optional progress callback
  /// 
  /// [onProgress] receives progress updates as a percentage (0-100)
  static Future writeVideofile(
    String srcFilePath, 
    String destFilePath, 
    double inTime, 
    double outTime,
    Map<String, Map<String, dynamic>> processing,
    {void Function(double progress)? onProgress}
  ) async {
    StreamSubscription? progressSubscription;
    
    if (onProgress != null) {
      progressSubscription = _progressChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is num) {
            onProgress(event.toDouble());
          }
        },
      );
    }
    
    try {
      await _channel.invokeMethod('writeVideofile', <String, dynamic>{
        'srcFilePath': srcFilePath,
        'destFilePath': destFilePath,
        'processing': processing,
        'inTime': inTime, 
        'outTime': outTime 
      });
    } finally {
      await progressSubscription?.cancel();
    }
  }

  static Future cancelExport() async {
    await _channel.invokeMethod('cancelExport', <String, dynamic>{});
  }
}
