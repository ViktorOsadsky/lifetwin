library lifetwin_on_device;

import 'dart:convert';

import 'package:flutter/services.dart';

export 'src/model.dart';
export 'src/neural_hazard.dart';
export 'src/projection.dart';

import 'src/model.dart';
import 'src/neural_hazard.dart';
import 'src/projection.dart';

/// Loads the model once from assets compiled into the Flutter application.
/// No network, Python runtime, or platform channel is used for inference.
Future<LifeTwinModel> loadLifeTwinModel({AssetBundle? bundle}) async {
  final assets = bundle ?? rootBundle;
  const prefix = 'packages/lifetwin_on_device/assets/';
  final modelText = await assets.loadString('${prefix}model.json');
  final encoded = await assets.load('${prefix}support_reference.f64');
  return LifeTwinModel.fromArtifacts(
    jsonDecode(modelText) as Map<String, dynamic>,
    Uint8List.fromList(
      encoded.buffer.asUint8List(encoded.offsetInBytes, encoded.lengthInBytes),
    ),
  );
}

/// Loads both frozen models locally, with no network or inference service.
Future<LifeTwinProjectionLab> loadLifeTwinProjectionLab({
  AssetBundle? bundle,
}) async {
  final assets = bundle ?? rootBundle;
  final cox = await loadLifeTwinModel(bundle: assets);
  final neuralText = await assets.loadString(
    'packages/lifetwin_on_device/assets/neural_model.json',
  );
  return LifeTwinProjectionLab(
    cox,
    NeuralHazardModel(jsonDecode(neuralText) as Map<String, dynamic>),
  );
}
