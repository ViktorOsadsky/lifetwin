# LifeTwin Projection Lab

Local Flutter web tester for the exact Dart models in `../lifetwin_on_device`.

```powershell
flutter pub get
flutter run -d chrome
```

If Chrome is not configured as a Flutter device, run `flutter run -d web-server` and open the printed local URL. The page shows the neural relative hazard versus its fixed reference, the current supported Cox five-year survival percentage, and two experimental chained Cox curves. The 50% crossings are simulated median thresholds and are especially speculative when they depend on age inputs above 79. Turn off “Show unvalidated ages 80–110” to inspect only model-age-supported assessments.

The form starts with an illustrative profile. It does not store inputs or call a prediction API. Run `flutter test`, `flutter analyze`, and `flutter build web` to verify changes. See [the handoff](../SURVIVAL_PROJECTION_HANDOFF.md) for interpretation and app integration.
