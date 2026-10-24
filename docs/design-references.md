# LifeTwin design references

Status: V = verified by visit to the page (2026-10-23, page text only, no screenshots inspected); S = second-hand (search snippet or prior knowledge, not confirmed). Model relationships and interaction patterns only. Do not copy branding, characters or art. Where a claim is S, re-check before citing in the submission.

## 1. Inclusive avatars and character customization

1. **Crayola Adventures (ADA 2024, Inclusivity)**. https://www.apple.com/newsroom/2024/06/apple-announces-winners-of-the-2024-apple-design-awards. V. Players pick characters with varied skin tones, abilities, body types and pronouns, with full narration. Model: broad, user-chosen identity options in a kids-friendly, non-clinical tone. Do not copy art. Informs Studio.
2. **Apple Memoji**. https://support.apple.com/guide/iphone/iph3ba2d3d2c/ios. S (fetch returned no detail). Model: option categories for skin, age cues, glasses, hearing-aid-style accessories, headwear, all user-chosen, head-and-shoulders only (no body). Do not copy the 3D look. Studio.
3. **Bitmoji**. https://www.imore.com/make-your-bitmoji-even-more-spot-snapchat-bitmoji-deluxe. S. Deluxe added many skin tones and hair colors. Body-type claims are unverified. Model: wide skin and hair palettes. Do not copy the Snap look. Studio.
4. **Nintendo Mii / Zepeto / The Sims sliders**. S (no page fetched). Model: sliders for build and height are user-chosen, never derived. Avoid numeric weight or BMI display. LifeTwin rule: body shape is a separate Studio tab of about 5 silhouettes with no numbers, and it never feeds the health model. Studio.
5. **Humaaans**. https://www.humaaans.com. V. Mix-and-match parts (hair, tops, pants) with rotate and position. The page does not mention skin tone or age. Model: modular SVG layers, which suits Flutter/Lottie layering. Do not copy the art. Studio.
6. **Open Peeps**. https://www.openpeeps.com. V. Combinable bodies, poses, faces, hair, facial hair, glasses, and colors. Page claims 584,688 combinations. Documents no explicit diversity controls. Model: layer-and-slot architecture. Add your own mobility aid and hearing aid layers. Studio.
7. **Microsoft Inclusive Design**. https://inclusive.microsoft.design. V. Principles: recognize exclusion, learn from diversity, solve for one and extend to many. Gives no specific imagery rules. Model: use as a checklist for older-adult and disability representation. Studio, Intake.
8. **Duolingo's diverse cast**. https://blog.duolingo.com/hub/design/. V that the hub lists no character-design post. S on the diverse cast. Model: varied shapes, ages, and styles in one friendly cast. Do not copy the characters. Studio, Quiz.

## 2. Health apps with a reactive friendly character

9. **Gentler Streak (Yorhart)**. https://gentlerstories.com/gentlerstreak/. V. A non-judgmental companion. Daily goals adapt to how the body feels. Rest days and an injury/illness status exist. Breaks do not reset streaks. Compares you only to your own history. Apple Watch App of the Year 2022, ADA 2024 Social Impact. Model: rest is progress, no punishment, self-comparison only. Do not copy Yorhart. Room, Activity.
10. **Finch**. https://finchcare.com. V (thin). "Take care of your pet by taking care of yourself." Details of guilt avoidance are on help.finchcare.com (not read). Model: pet grows from your habits. Check in-app that missed days do not harm the pet. Room, Activity.
11. **Pokémon Sleep**. https://www.pokemonsleep.net/en/. V. A morning reward, a sleep-type quiz, and an "entertainment only, not medical" disclaimer. Model: a playful framing with an explicit non-medical disclaimer, which fits the Fortune screen. Do not copy the IP. Fortune, Quiz.
12. **Zombies, Run!**. https://zombiesrungame.com. V. Story missions unlock as you move, supplies are collected, and chases add urgency. Model: narrative pull instead of numbers. Avoid chase and threat framing, which is scary. Activity.
13. **Habitica**. https://habitica.com. V (page gave no detail). S: avatar loses health on missed tasks. Do NOT copy the punishment loop. Model only the customizable avatar. Activity, Studio.

## 3. Cozy habitat and tactile UI

14. **Rooms (ADA 2024, Visuals and Graphics)**. https://www.apple.com/newsroom/2024/06/apple-announces-winners-of-the-2024-apple-design-awards. V. Build scenes with playful visuals and sounds. Model: a scene-first home screen with small interactive props. Do not copy the art. Room.
15. **Bears Gratitude (ADA 2024, Delight and Fun)**. Same Apple page. V. Warm characters carry a daily routine. Model: a character-led ritual for a daily check-in. Intake, Room.
16. **Rytmos and Crouton (ADA 2024, Interaction)**. Same Apple page. V. Rytmos: simple drag gestures, with progress that adds to a song. Crouton: hands-free, low-friction cooking use. Model: one-gesture interactions for the magic-ball shake or drag, and large targets for the food quiz. Fortune, Quiz.
17. **ADA 2026 Delight and Fun and Inclusivity winners**. https://developer.apple.com/design/awards/. V. Delight: grug, Is This Seat Taken?. Inclusivity: Guitar Wiz, Pine Hearts. Pine Hearts has settings for text, controls and motion. Model: Pine Hearts' text, control and motion settings, applied to older-adult accessibility. Room, all.
18. **Pok Pok, Toca Boca World, Neko Atsume, Tamagotchi Uni**. S. All fetches failed. Look at their App Store pages for calm, no-fail loops and tap-to-poke props. Room.

## 4. Conversational intake

19. **Wysa / Woebot**. https://www.wysa.com. Fetch returned only the page title. S. Model: short chat bubbles and quick-reply chips, with a clear "I am not a clinician" framing. Intake.
20. **Replika / Duolingo onboarding**. S. Model: one question per screen, a mascot narrating, and a visible progress cue. Avoid free-text-only input for older adults, so offer large chips and a voice option. Intake.

## Top 6 to model

1. **Crayola Adventures**: user-chosen body, ability and skin options, with no scores attached. Studio.
2. **Gentler Streak**: a non-judgmental companion where rest never resets progress. Room, Activity.
3. **Open Peeps and Humaaans**: layered SVG parts as the Studio architecture, plus our own aid layers. Studio.
4. **Pokémon Sleep**: a playful framing with a visible "entertainment only" disclaimer. Fortune.
5. **Pine Hearts and Guitar Wiz (ADA 2026)**: text, control and motion settings with strong VoiceOver. All screens.
6. **Wysa/Woebot-style chips**: large quick replies and one question per screen for the Pip intake. Intake.

## Open gaps

Screenshots were not inspected for any reference. Bitmoji, Mii, Zepeto, Sims, Toca, Pok Pok, Neko Atsume and Tamagotchi were not verified. Re-check those before citing them.

## 5. Friendly lists, surfaces and gentle health UI (added for the 'too blocky and bubbly' feedback)

Verification key: **V** = page fetched this session and the quoted claim is on it; **V-text** = page fetched but it is marketing text only, so the layout technique is second-hand (known app behaviour, not confirmed from the page); **S** = second-hand/not fetched. No screenshots were inspected. Open each app before citing a layout technique.

| # | Reference (URL) | Technique to model | Do NOT copy | Informs | Status |
|---|---|---|---|---|---|
| 1 | Apple HIG, Lists and tables (developer.apple.com/design/human-interface-guidelines/lists-and-tables) | Plain rows, hairline separators, small section headers, text hierarchy. | Default inset-grouped rounded blocks stacked 6 deep. | All lists | S (page is JS-rendered; fetch returned title only) |
| 2 | Apple HIG, Writing (developer.apple.com/design/human-interface-guidelines/writing) | Plain, "you"-directed language; avoid "just/simply". | Treating it as a tone guide for health. | Pip copy | S (fetch returned title only) |
| 3 | NHS Service Manual, Voice and tone (service-manual.nhs.uk/content/voice-and-tone) | Comfort without alarming; warm, direct; avoid "should"; give agency; reassuring context; serious-but-clear tone for sensitive topics, upbeat for everyday ones. | Clinical deferral on every screen. | Outlook, lever copy | V |
| 4 | NHS Service Manual, Health literacy (service-manual.nhs.uk/content/health-literacy) | Write for lower health literacy; test with users. | Readability scores as a quality gate (page discourages this). | Plan rows, confirm summary | V |
| 5 | Gentler Streak (gentlerstories.com/gentlerstreak/) | Goals adapt to the body; breaks do not reset progress; no guilt; log illness or rest; daily/10-day/30-day Activity Path views; mascot encourages without judgment. | Fitness-ring framing; streak counts. | Workout log, quiz-miss reactions, outlook | V |
| 6 | Apple Design Awards 2024, Social Impact (apple.com/newsroom/2024/06/apple-announces-winners-of-the-2024-apple-design-awards/) | Gentler Streak's Monthly Summary compares you with your own past, not other people. | Any peer comparison. | Progress views | V |
| 7 | Finch (finchcare.com) | Pet-as-self-care framing, warm upbeat voice ("self-care best friend"). | Reward-economy chrome. | Mascot tone | V-text |
| 8 | Things 3 (culturedcode.com/things/) | Reviewers cite an uncluttered long list, "sheet of paper" whitespace, animations that keep your place. Technique: type hierarchy and spacing, not containers. | Checkbox-circle motif for levers. | Lever list, plan items | V-text |
| 9 | Flighty (flighty.com) | 2023 Design Award; reviewers praise clarity. Technique: dense rows with leading status, hairlines. | Data density for a gentle app. | Activity log | V-text (technique S) |
| 10 | Pokemon Sleep (pokemonsleep.net/en/) | Playful sleep framing; fine print says entertainment only, not medical. | Game-reward language for health. | Outlook disclaimer pattern | V-text |
| 11 | Apple Weather (apple.com/ios/weather) | Full-screen sky gradient continuing behind translucent content, with list rows over it. | n/a | Habitat to page | S (URL 404; locate current page) |
| 12 | How We Feel (howwefeel.org) | Calm, non-judgmental check-ins; colour-by-mood, minimal chrome. | n/a | Quiz answers, mood-like confirm | S (fetch returned nothing) |
| 13 | Apple Health Summary/Highlights | Trends as quiet text plus a light chart, no alarm colours. | Red/amber risk badges. | Outlook | S |
| 14 | Alto's Odyssey / Monument Valley menus | Scene gradient is the page ground; UI is type over it. | Full-bleed art behind dense text. | Habitat, home | S |
| 15 | Headspace, Calm, Daylio, Bearable, Structured, Stoic, Oura/Whoop | Not verified; Headspace design page 404ed. Candidates only for soft sections and gentle "readiness" framing. | n/a | Settings, studio | S |

### Rules we will apply
1. The habitat's top sky colour equals the page ground token and fades over at least 120pt via a gradient mask; no habitat sits inside a rounded card.
2. Lists use plain rows on the page ground separated by 0.5pt hairlines inset to the text edge; no per-row card, shadow or border.
3. Group related rows under a small quiet section header (caption, secondary colour); no container around the group unless it is a sheet.
4. At most one filled pill button per screen; every other action is a text button or a trailing chevron row.
5. Chips are limited to selectable filters; values, units and evidence tags render as plain secondary-colour text with a middot separator.
6. Lever rows are one line (label left, "about +x.x pts" right) with a second-line source and strength in caption text; the number is never red or green.
7. Sheets rise from the scene: a top-rounded surface tinted from the page ground (not white-on-grey), one per screen, with a grabber.
8. Wrong quiz answers and missed logs get a gentle line from Pip ("Pip is a little sleepy") and a recovery path; no failure colour, no streak loss, no guilt wording.
9. Outlook copy states a supported range and horizon, one sentence of reassurance, and a "what you can influence" link; never "should", never a countdown.
10. Test: at 390pt width, a screenshot has no visible container edge on the habitat and at most two distinct corner radii on the screen.
