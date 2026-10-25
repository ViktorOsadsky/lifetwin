# Day summary JSON on the band, read with nRF Connect (iPhone)

The test web page is no longer needed. **The band builds the day summary itself and saves it as a JSON file in its own flash memory.** nRF Connect connects to the band, sets the clock, asks it to save, and reads the result out.

**Be clear about one limit:** nRF Connect cannot create a `.json` file on the iPhone by itself. It can send commands and show or export what the band sends. The real file lives on the band; getting it onto the phone as a file is what the future iPhone app will do (same commands).

## What the band does on its own
- It records one summary per minute whenever it has power (it does not need to be connected).
- **Once its clock has been set**, it rebuilds the day summary every 10 minutes and writes it to `/day_YYYY-MM-DD.json` in flash. That file survives switching the band off. If the band restarts in the middle of a day, what it saved before the restart is added to what it records after, so the day's totals keep adding up.
- It has no clock chip, so **the clock must be set again after every power-off** (see below). Minutes recorded before you set it get correct times as soon as you do, as long as the band stayed on.
- The file has the same format as the test page produced (`lifetwin.band_day.v0`): minutes per category, steps, moderate+vigorous minutes, sit-to-stand transitions, longest sitting stretch, wear minutes, valid-day flag, an hour-by-hour list.

## One-time setup
1. Upload the 0.8 sketch (`lifetwin_band_single_file.ino`). In the Arduino IDE use *Tools → Partition Scheme* with a **SPIFFS** area (the default "Default 4MB with spiffs" is fine).
2. The Serial Monitor should say `Flash file system OK`. If it says FAILED the band still works, but cannot keep files.

## In nRF Connect
Connect to **LifeTwin Band** and open the service starting `4c540001`. The characteristics you need:

| Ends in | Use |
|---|---|
| `…0003` | **Set the clock** (write) |
| `…0004` | **Commands** (write) |
| `…0008` | **The summary** (read, and notifications) |

1. **Set the clock.** Write to `…0003` the local time with your zone, exactly like this (type it as **Text** if your app offers that):
   `2026-10-25 08:30:00 -07:00`
   If it only accepts hex bytes, send the same text as bytes: `32 30 32 36 2D 31 30 2D 32 35 20 30 38 3A 33 30 3A 30 30 20 2D 30 37 3A 30 30`
   (`-07:00` is Pacific Daylight Time; use your own zone. The date and zone decide which day each minute belongs to.) The Serial Monitor confirms `Clock set`.
2. **Save the file now.** Write `0A` (hex) to `…0004`. The band builds the summary and saves the file.
3. **Read the headline numbers.** Tap read on `…0008`. You get a short JSON with the totals (about 450 bytes, `"headline_only":true`).
4. **Get the full file** (with the hourly list). Turn **notifications on** for `…0008` (the triple-arrow icon), then write `0B` to `…0004`. The band sends the file in chunks and finishes with `<EOF>`.
5. **Make a `.json` file on your computer.** Copy the value(s) shown in nRF Connect (hex is fine) into a text file, then run `python tools/hex_to_json.py copied.txt`. It checks the JSON and writes `lifetwin-band-day-YYYY-MM-DD.json`. (nRF Connect can also export its log as text or CSV, which holds the chunks.)

I have not seen how your version of nRF Connect displays the values (hex or text), which is why step 5 accepts hex.

## The simplest route: the Serial Monitor on a laptop
With the band plugged in, in the Serial Monitor (115200, Newline):

| Type | What it does |
|---|---|
| `T 2026-10-25 08:30:00 -07:00` | set the clock and zone |
| `w` | build and save the day files, then list them |
| `j` | print today's file: copy everything between the two lines into a `.json` file |
| `f` | list the files on the band |
| `E yes` | erase every saved file |

## Tested and not tested
- **Tested on a computer:** the band's day-summary code gives the same result as the test page's code on 157 random day summaries across four time zones (including not-worn stretches, gaps and midnight crossings). The headline always agrees with the full file, fits in one Bluetooth read, and the restart-and-merge adds up exactly. The helper script decodes the band's output in every hex format I tried.
- **Not tested on the band:** writing the files to flash, the Bluetooth chunking, and typing the time over Bluetooth have only been syntax-checked, not run on your ESP32. Please report anything odd (the Serial Monitor prints what it is doing).
- A sit-to-stand that straddles a restart is not counted, and a "longest sitting stretch" never spans a restart.
