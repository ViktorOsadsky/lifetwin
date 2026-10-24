# Root mobile and interaction review

2026-10-23. Actual browser checks against the loopback-served sample, after the design agent's desktop review.

At 390px, the page had no horizontal overflow and all product/receipt controls were available. At 320px, a DOM geometry inspection and screenshot exposed a real collision: the description occupied x24–234,y354.5–441.28 while the absolute budget occupied x188–298,y385.78–441.28. The narrow-screen CSS now stacks the budget below the text, uses a 56px heading, and keeps the mobile controls 44px tall/wide as applicable. The stylesheet URL is versioned v2 so QA actually loads the revised asset.

After reloading the revised stylesheet at 320px, budget top392.45px exceeded description bottom372.45px by 20px; scroll width and viewport were both 320px. The root visually inspected narrow-after-root.jpg and verified the text no longer collides. Browser interaction added peaches and bread, producing an actual $11 total and $9 remaining under a $20 sample budget. Changing budget to $10 produced a $1-over warning. Quiet view became pressed and computed transition duration was 0s. Invalid budget -1 showed the validation message and disabled download. The normal viewport was restored; desktop scroll width matched 1280px viewport.

Screenshots: mobile-root.jpg (390px), narrow-before-root.jpg, narrow-after-root.jpg, and final-preview.jpg (normal 1280px view with actual selections). Parent reviewed desktop-after.jpg too. No checkout, payment or order exists. Download-list text has automated tests, but a completed browser download was not verified: the worker's download event wait hung and was interrupted. No claim of download completion is made.

These are local UI tests, not measured frame-rate or real WebGL 3D tests. The sample is SVG/CSS 2.5D. Real 3D guidance belongs in the skill reference.
