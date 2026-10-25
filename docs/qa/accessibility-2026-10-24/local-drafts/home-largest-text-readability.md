[P2][Home] Largest accessibility text fragments score direction labels and Today summary

Pinned main: 1a648bd405df4c76b5c1dea3339194c31201913c. Actual iPhone 18 Pro simulator, iOS 27.0, light appearance. System content_size=accessibility-extra-extra-extra-large, no app text-scale override. Runtime read-back: native/effective20=62.35294117647059 pt, effective17=53 pt, effective48=149.64705882352942 pt. Synthetic DEMO_SEED=1 Rosa, actual+0.59.

Reproduce: set the simulator's largest accessibility text size, launch Home, then scroll the health-score card down to the scale labels and Today summary.

Observed: the direction labels Higher risk and Better health wrap into fragments/single letters around the unwrapped Average label, substantially impairing readability. Farther down, the Today summary is reduced to To / d… beside the Check in action. This is a content readability finding, not a claim that navigation or check-in is unreachable. The+0.59 score and percentile remain readable.

Expected: direction labels remain readable as words, and the summary has enough space or another accessible presentation at this size.

Evidence: final-ax5-readable/ax5-home-scroll1.png (scale directions) and ax5-home-scroll4.png (Today summary), font-readback.json. Independently reviewed. Source context: app/lib/wellness/home_panel.dart:564–567 fixes three labels in one Row with Average unwrapped; app/lib/wellness/today_card.dart:198 places condensed summary beside a trailing action. Design owner chooses layout. Distinct from #142 automatic VoiceOver live-region speech. Published as [#150](https://github.com/ViktorOsadsky/lifetwin/issues/150).
