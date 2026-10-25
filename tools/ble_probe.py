#!/usr/bin/env python3
"""Probe a Bluetooth LE device (the LifeTwin activity band) from a Mac, read-only by default.

Install bleak into a scratch venv first:
    python3 -m venv /tmp/ble-venv && /tmp/ble-venv/bin/pip install bleak

Usage:
    ble_probe.py                         scan 20 s; list name, address, RSSI, service UUIDs, manufacturer data
    ble_probe.py --connect "LifeTwin Band" [--seconds 60]
                                         connect; dump services/characteristics; read every readable one;
                                         subscribe to every notify/indicate one for N seconds; log raw bytes
    ble_probe.py --connect NAME --write UUID VALUE
                                         the same, plus ONE write after subscribing. VALUE is `hex:0a0b...` or
                                         `text:...` (a bare value is sent as UTF-8 text). Only when asked.
    ble_probe.py --connect "LifeTwin Band" --sync
                                         the band's real day sync (firmware 0.8, LifeTwin-band-full-code/docs/
                                         band-ble-contract.md): read Info, write the clock, subscribe to 0008,
                                         write 0D (index), then 0C + date for each of the newest 14 days; saves
                                         index.json and day_YYYY-MM-DD.json. It never writes 0E (delete).
    ble_probe.py --replay LOG.jsonl [--strip N]
                                         re-run JSON reassembly on a saved log, optionally dropping the first
                                         N bytes of every notification (a sequence/header prefix)

Every run writes to --out (default: ./ble-probe/<timestamp>/): log.jsonl (one event per line, raw hex
plus a UTF-8 decoding), services.json, and payload-NNN.json for each complete JSON value reassembled
from consecutive notifications on one characteristic. Nothing is written to the device unless --write
is given. On macOS the address is a CoreBluetooth UUID, not a MAC address.
"""

from __future__ import annotations

import argparse
import asyncio
import datetime as dt
import json
import sys
from pathlib import Path


def stamp() -> str:
    return dt.datetime.now().astimezone().isoformat(timespec="milliseconds")


class Log:
    def __init__(self, out: Path):
        out.mkdir(parents=True, exist_ok=True)
        self.out = out
        self._file = (out / "log.jsonl").open("a", encoding="utf-8")
        self.payloads = 0

    def event(self, kind: str, **fields) -> None:
        self._file.write(json.dumps({"t": stamp(), "event": kind, **fields}) + "\n")
        self._file.flush()

    def bytes_event(self, kind: str, char: str, data: bytes) -> None:
        text = data.decode("utf-8", errors="replace")
        self.event(kind, char=char, len=len(data), hex=data.hex(" "), utf8=text)
        print(f"{kind:7} {char[:8]} {len(data):4} B  {data[:24].hex(' ')}{' …' if len(data) > 24 else ''}  {text[:60]!r}")

    def payload(self, char: str, value: object, raw: bytes) -> None:
        self.payloads += 1
        path = self.out / f"payload-{self.payloads:03d}.json"
        path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        self.event("payload", char=char, len=len(raw), file=path.name)
        print(f"payload {char[:8]} {len(raw)} B  -> {path}")


class Reassembler:
    """Concatenates notifications and pulls out complete top-level JSON values ({...} or [...]).

    Bytes before the first `{`/`[` and between values are kept in the log but skipped here."""

    def __init__(self, strip: int = 0, limit: int = 4 * 1024 * 1024):
        self.strip, self.limit = strip, limit
        self.buf = bytearray()

    def feed(self, data: bytes) -> list[tuple[object, bytes]]:
        self.buf += data[self.strip:]
        found = []
        while True:
            start = next((i for i, b in enumerate(self.buf) if b in b"{["), None)
            if start is None:
                self.buf.clear()
                return found
            del self.buf[:start]
            end = _value_end(self.buf)
            if end is None:
                if len(self.buf) > self.limit:
                    self.buf.clear()
                return found
            raw = bytes(self.buf[:end])
            del self.buf[:end]
            try:
                found.append((json.loads(raw.decode("utf-8")), raw))
            except (UnicodeDecodeError, json.JSONDecodeError):
                pass  # balanced but not JSON: keep scanning after it


def _value_end(buf: bytes) -> int | None:
    depth, in_str, esc = 0, False, False
    for i, b in enumerate(buf):
        if in_str:
            if esc:
                esc = False
            elif b == 0x5C:
                esc = True
            elif b == 0x22:
                in_str = False
        elif b == 0x22:
            in_str = True
        elif b in b"{[":
            depth += 1
        elif b in b"}]":
            depth -= 1
            if depth == 0:
                return i + 1
    return None


def _manufacturer(adv) -> dict:
    return {f"0x{k:04x}": v.hex(" ") for k, v in (adv.manufacturer_data or {}).items()}


async def scan(seconds: float, log: Log) -> None:
    from bleak import BleakScanner

    print(f"Scanning {seconds:.0f} s…")
    found = await BleakScanner.discover(timeout=seconds, return_adv=True)
    rows = sorted(found.values(), key=lambda da: -(da[1].rssi or -999))
    for device, adv in rows:
        row = {
            "name": adv.local_name or device.name,
            "address": device.address,
            "rssi": adv.rssi,
            "service_uuids": adv.service_uuids,
            "manufacturer_data": _manufacturer(adv),
            "service_data": {k: v.hex(" ") for k, v in (adv.service_data or {}).items()},
            "tx_power": adv.tx_power,
        }
        log.event("advert", **row)
        print(f"{row['rssi']:>4}  {str(row['name'] or '-'):24} {row['address']}  services={row['service_uuids']} "
              f"mfr={row['manufacturer_data']}")
    print(f"{len(rows)} devices. Log: {log.out / 'log.jsonl'}")


async def _find(target: str, seconds: float):
    from bleak import BleakScanner

    found = await BleakScanner.discover(timeout=seconds, return_adv=True)
    want = target.lower()
    for device, adv in found.values():
        name = (adv.local_name or device.name or "").lower()
        if device.address.lower() == want or name == want:
            return device
    for device, adv in found.values():
        if want in (adv.local_name or device.name or "").lower():
            return device
    return None


def _write_value(value: str) -> bytes:
    if value.startswith("hex:"):
        return bytes.fromhex(value[4:].replace(" ", "").replace("0x", ""))
    if value.startswith("text:"):
        value = value[5:]
    return value.encode("utf-8")


async def connect(args, log: Log) -> None:
    from bleak import BleakClient

    device = await _find(args.connect, args.scan_seconds)
    if device is None:
        sys.exit(f"No device named or addressed {args.connect!r} found in {args.scan_seconds:.0f} s.")
    print(f"Connecting to {device.name} {device.address}…")
    async with BleakClient(device) as client:
        log.event("connected", name=device.name, address=device.address, mtu=client.mtu_size)
        print(f"Connected. MTU {client.mtu_size}")
        services = []
        for service in client.services:
            chars = []
            for c in service.characteristics:
                chars.append({
                    "uuid": c.uuid, "handle": c.handle, "properties": c.properties,
                    "descriptors": [d.uuid for d in c.descriptors],
                })
                print(f"  {service.uuid}  {c.uuid}  {','.join(c.properties)}")
            services.append({"uuid": service.uuid, "description": service.description, "characteristics": chars})
        (log.out / "services.json").write_text(json.dumps(services, indent=2) + "\n", encoding="utf-8")
        log.event("services", services=services)

        for service in client.services:
            for c in service.characteristics:
                if "read" in c.properties:
                    try:
                        log.bytes_event("read", c.uuid, bytes(await client.read_gatt_char(c)))
                    except Exception as e:  # noqa: BLE001 - log every failure and continue probing
                        log.event("read_error", char=c.uuid, error=str(e))
                        print(f"read    {c.uuid[:8]} failed: {e}")

        streams: dict[str, Reassembler] = {}

        def on_notify(char, data: bytearray) -> None:
            raw = bytes(data)
            log.bytes_event("notify", char.uuid, raw)
            for value, payload in streams[char.uuid].feed(raw):
                log.payload(char.uuid, value, payload)

        for service in client.services:
            for c in service.characteristics:
                if {"notify", "indicate"} & set(c.properties):
                    streams[c.uuid] = Reassembler()
                    try:
                        await client.start_notify(c, on_notify)
                        log.event("subscribed", char=c.uuid)
                    except Exception as e:  # noqa: BLE001
                        log.event("subscribe_error", char=c.uuid, error=str(e))
                        print(f"notify  {c.uuid[:8]} failed: {e}")

        if args.write:
            uuid, value = args.write
            data = _write_value(value)
            char = client.services.get_characteristic(uuid)
            response = char is not None and "write" in char.properties
            log.bytes_event("write", uuid, data)
            await client.write_gatt_char(uuid, data, response=response)

        print(f"Listening {args.seconds:.0f} s…")
        await asyncio.sleep(args.seconds)
        log.event("done", payloads=log.payloads)
    print(f"{log.payloads} JSON payloads. Log: {log.out / 'log.jsonl'}")


BASE = "-7b2a-4f0e-9a51-0d1e2c3b4a50"
INFO, CLOCK, CONTROL, SUMMARY = (f"4c54000{n}{BASE}" for n in (2, 3, 4, 8))
EOF = b"<EOF>"


async def sync(args, log: Log) -> None:
    import struct
    import time

    from bleak import BleakClient

    device = await _find(args.connect, args.scan_seconds)
    if device is None:
        sys.exit(f"No device named or addressed {args.connect!r} found in {args.scan_seconds:.0f} s.")
    async with BleakClient(device) as client:
        log.event("connected", name=device.name, address=device.address, mtu=client.mtu_size)
        info = bytes(await client.read_gatt_char(INFO))
        log.bytes_event("read", INFO, info)
        if len(info) < 10:
            sys.exit("Info is shorter than 10 bytes: not firmware 0.8.")
        fw = (info[0], info[1])
        print(f"Info: firmware {fw[0]}.{fw[1]}, record format {info[2]}, record size {info[3]}, "
              f"capacity {info[4] | info[5] << 8}, stored minutes {info[6] | info[7] << 8}, "
              f"posture state {info[8]:#04x} (positions saved: {bool(info[8] & 4)}), step settings {info[9]:#04x}")
        if info[2] != 2 or fw < (0, 8):
            sys.exit("This band needs firmware 0.8 or later (record format 2) for day files over Bluetooth.")

        zone_min = int(dt.datetime.now().astimezone().utcoffset().total_seconds() // 60)  # minutes east of UTC
        clock = struct.pack("<Ih", int(time.time()), zone_min)
        log.bytes_event("write", CLOCK, clock)
        await client.write_gatt_char(CLOCK, clock, response=True)
        await asyncio.sleep(0.4)

        queue: asyncio.Queue[bytes] = asyncio.Queue()

        def on_notify(char, data: bytearray) -> None:
            log.bytes_event("notify", char.uuid, bytes(data))
            queue.put_nowait(bytes(data))

        await client.start_notify(SUMMARY, on_notify)

        async def fetch(command: bytes, name: str) -> object | None:
            while not queue.empty():
                queue.get_nowait()
            log.bytes_event("write", CONTROL, command)
            await client.write_gatt_char(CONTROL, command, response=True)
            buf = bytearray()
            try:
                while True:
                    chunk = await asyncio.wait_for(queue.get(), timeout=12 if buf else 10)
                    if chunk == EOF:
                        break
                    buf += chunk
                    if buf.endswith(EOF):
                        del buf[-len(EOF):]
                        break
            except asyncio.TimeoutError:
                print(f"{name}: no <EOF> ({len(buf)} bytes, then silence); abandoned")
                return None
            path = log.out / f"{name}.json"
            path.write_bytes(bytes(buf))
            try:
                value = json.loads(buf.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as e:
                print(f"{name}: {len(buf)} bytes, not valid JSON ({e}); saved raw to {path}")
                return None
            print(f"{name}: {len(buf)} bytes -> {path}")
            return value

        index = await fetch(b"\x0d", "index")
        days = index.get("days") if isinstance(index, dict) else None
        if not isinstance(days, list):
            sys.exit("The index has no days list.")
        for day in sorted(set(days))[-14:]:
            await fetch(b"\x0c" + day.encode("ascii"), f"day_{day}")
        log.event("done", days=len(days))
    print(f"Done. Files in {log.out}. Check one with the app parser or tools/hex_to_json.py.")


def replay(path: Path, strip: int, log: Log) -> None:
    streams: dict[str, Reassembler] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        event = json.loads(line)
        if event.get("event") != "notify":
            continue
        raw = bytes.fromhex(event["hex"])
        for value, payload in streams.setdefault(event["char"], Reassembler(strip)).feed(raw):
            log.payload(event["char"], value, payload)
    print(f"{log.payloads} JSON payloads from {path}")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--connect", metavar="NAME|ADDRESS")
    p.add_argument("--seconds", type=float, default=60, help="listen time after subscribing (default 60)")
    p.add_argument("--scan-seconds", type=float, default=20, help="scan time (default 20)")
    p.add_argument("--write", nargs=2, metavar=("UUID", "VALUE"), help="one write after subscribing")
    p.add_argument("--sync", action="store_true", help="with --connect: the band's day sync (firmware 0.8)")
    p.add_argument("--replay", type=Path, metavar="LOG.jsonl")
    p.add_argument("--strip", type=int, default=0, help="with --replay: drop N leading bytes per notification")
    p.add_argument("--out", type=Path, help="output directory (default ./ble-probe/<timestamp>)")
    args = p.parse_args()
    if (args.write or args.sync) and not args.connect:
        p.error("--write and --sync need --connect")
    out = args.out or Path("ble-probe") / dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    log = Log(out)
    if args.replay:
        replay(args.replay, args.strip, log)
    elif args.sync:
        asyncio.run(sync(args, log))
    elif args.connect:
        asyncio.run(connect(args, log))
    else:
        asyncio.run(scan(args.scan_seconds, log))


if __name__ == "__main__":
    main()
