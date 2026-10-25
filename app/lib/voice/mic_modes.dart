import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The iPhone's Mic Mode menu (Standard, Voice Isolation, Wide Spectrum), channel
/// "lifetwin/mic_mode" in AppDelegate.swift. Voice Isolation filters out other voices and
/// background sound better than anything the app can do. iOS keeps the choice per app, and
/// offers it only while the microphone is in use.
class MicModes {
  const MicModes._();

  static const _channel = MethodChannel('lifetwin/mic_mode');

  /// The menu exists on this phone (iOS 15 or later; the app's minimum).
  static bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Opens the system menu. False when it could not be shown.
  static Future<bool> show() async {
    try {
      return await _channel.invokeMethod<bool>('show') ?? false;
    } catch (_) {
      return false;
    }
  }
}
