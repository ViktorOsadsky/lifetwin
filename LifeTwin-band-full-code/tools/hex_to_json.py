#!/usr/bin/env python3
"""Turn the hex that nRF Connect shows into a .json day-summary file.

Usage:
    python hex_to_json.py                 # then paste the value(s) copied from nRF Connect, finish with an empty line
    python hex_to_json.py copied.txt      # or read them from a text file

Accepted: "0x7B22...", "7B 22 ...", "7B-22-...", "7B,22,...", several lines (one per notification chunk).
Only paste the VALUES (not the whole log). The script stops at <EOF>, checks it is valid JSON,
and writes lifetwin-band-day-YYYY-MM-DD.json in the current folder."""
import sys, re, json

def decode(text):
    text = re.sub(r'0x', ' ', text)                 # drop 0x prefixes
    pairs = re.findall(r'(?<![0-9A-Fa-f])([0-9A-Fa-f]{2})(?![0-9A-Fa-f])', re.sub(r'[^0-9A-Fa-f]+', ' ', text))
    if not pairs:                                    # maybe one long unbroken hex string per line
        pairs = [h[i:i+2] for h in re.findall(r'[0-9A-Fa-f]{4,}', text) for i in range(0, len(h) - 1, 2)]
    raw = bytes(int(p, 16) for p in pairs)
    s = raw.decode('utf-8', errors='replace')
    if '<EOF>' in s: s = s.split('<EOF>')[0]
    start = s.find('{')
    if start < 0: raise ValueError('no JSON found in what was pasted (it should start with {"schema")')
    end = s.rfind('}')
    return s[start:end + 1]

def main():
    if len(sys.argv) > 1: text = open(sys.argv[1], encoding='utf-8', errors='ignore').read()
    else:
        print('Paste the value(s) from nRF Connect, then press Enter on an empty line:')
        lines = []
        for line in sys.stdin:
            if not line.strip() and lines: break
            lines.append(line)
        text = '\n'.join(lines)
    j = decode(text); data = json.loads(j)
    name = f"lifetwin-band-day-{data.get('date', 'unknown')}.json"
    open(name, 'w', encoding='utf-8').write(json.dumps(data, indent=2) + '\n')
    print(f'Saved {name}  ({"headline only: " if data.get("headline_only") else ""}{data["coverage"]["minutes_recorded"]} minutes, {data["steps"]} steps)')

if __name__ == '__main__': main()
