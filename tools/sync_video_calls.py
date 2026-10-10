"""Vendor the call feature into the independently built Professional app.

Usage: python3 tools/sync_video_calls.py [--check]
The Patient repository is the source of truth for lib/video_calls.
"""
import argparse
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
destination = root.parent / 'i_entier_professionnel' / 'lib' / 'video_calls'
if not destination.parent.exists():
    raise SystemExit('Professional repository not found beside Patient repository.')
if not args.check:
    destination.mkdir(exist_ok=True)
for source in sorted((root / 'lib' / 'video_calls').glob('*.dart')):
    target = destination / source.name
    if args.check:
        if not target.exists() or source.read_bytes() != target.read_bytes():
            raise SystemExit(f'Out of sync: {target}')
    else:
        target.write_bytes(source.read_bytes())
print('Video call modules are synchronized.')
