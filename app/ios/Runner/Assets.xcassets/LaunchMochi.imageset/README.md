# Launch Screen Assets

Mochi waving on lavender #B9B4F0: the 1x, 2x and 3x images are assets/twin/bear/pose/wave.png
resized so each one is exactly 139x180 pt. lib/ui/loading_screen.dart draws the same picture in
Flutter, so keep them in step.

Named LaunchMochi, not LaunchImage: iOS caches launch-screen images by name, so a renamed
asset is what makes an already-installed app pick up the new picture.
