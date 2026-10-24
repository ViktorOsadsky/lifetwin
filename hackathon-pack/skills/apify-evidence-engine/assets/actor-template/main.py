"""Apify lifecycle wrapper. Cloud execution not verified in the skill package."""
import asyncio
from apify import Actor
from extract import extract


async def main():
    async with Actor:
        data = await Actor.get_input() or {}
        snapshots = data.get('snapshots', [])
        if not isinstance(snapshots, list) or not 1 <= len(snapshots) <= 20:
            raise ValueError('Provide between one and 20 snapshots')
        for snapshot in snapshots:
            rows, warnings = extract(snapshot)
            if rows:
                await Actor.push_data(rows)
            if warnings:
                Actor.log.warning('Snapshot extraction warnings: %s', ', '.join(sorted(set(warnings))))


if __name__ == '__main__':
    asyncio.run(main())
