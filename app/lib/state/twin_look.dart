import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/lt_twin.dart';

/// Cosmetic choices only. Nothing here feeds any number.
class TwinLookNotifier extends Notifier<TwinLook> {
  @override
  TwinLook build() => const TwinLook();

  void setSkin(int i) => state = state.copyWith(skin: i);
  void setHairStyle(TwinHair h) => state = state.copyWith(hairStyle: h);
  void setHairColor(int i) => state = state.copyWith(hairColor: i);
  void setTop(int i) => state = state.copyWith(top: i);
  void setExtra(TwinExtra e) => state = state.copyWith(extra: e);
}

final twinLookProvider = NotifierProvider<TwinLookNotifier, TwinLook>(
  TwinLookNotifier.new,
);
