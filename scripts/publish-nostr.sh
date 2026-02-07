#!/bin/bash
# Publish a blog post as a NIP-23 long-form event on Nostr
# Usage: ./scripts/publish-nostr.sh src/content/posts/my-post.md
#
# Requires: nak CLI, python3
# Signs with Koda's nsec from ~/.config/nostr/koda.json

set -euo pipefail

POST_FILE="${1:?Usage: publish-nostr.sh <path-to-post.md>}"
KODA_KEY_FILE="$HOME/.config/nostr/koda.json"
RELAYS="wss://nos.lol wss://relay.damus.io"

if [ ! -f "$POST_FILE" ]; then
  echo "❌ File not found: $POST_FILE"
  exit 1
fi

SK_HEX=$(python3 -c "import json; print(json.load(open('$KODA_KEY_FILE'))['sk_hex'])")
SLUG=$(basename "$POST_FILE" .md)

# Use python to parse frontmatter and build the nak command
python3 - "$POST_FILE" "$SK_HEX" "$SLUG" "$RELAYS" << 'PYEOF'
import sys, subprocess, re

post_file = sys.argv[1]
sk_hex = sys.argv[2]
slug = sys.argv[3]
relays = sys.argv[4].split()

with open(post_file, 'r') as f:
    raw = f.read()

# Parse frontmatter
parts = raw.split('---', 2)
if len(parts) < 3:
    print("❌ No frontmatter found")
    sys.exit(1)

fm = parts[1].strip()
content = parts[2].strip()

# Extract fields
title = ""
summary = ""
date_str = ""
tags = []

for line in fm.split('\n'):
    if line.startswith('title:'):
        title = line.split(':', 1)[1].strip().strip('"')
    elif line.startswith('description:'):
        summary = line.split(':', 1)[1].strip().strip('"')
    elif line.startswith('date:'):
        date_str = line.split(':', 1)[1].strip()
    elif line.startswith('tags:'):
        tag_str = line.split(':', 1)[1].strip()
        tags = [t.strip().strip('"') for t in tag_str.strip('[]').split(',')]

# Convert date to timestamp
from datetime import datetime
published_at = str(int(datetime.strptime(date_str, '%Y-%m-%d').timestamp()))

print(f"📝 Publishing: {title}")
print(f"   Slug: {slug}")
print(f"   Date: {date_str}")
print(f"   Tags: {', '.join(tags)}")
print()

# Build nak command
cmd = ['nak', 'event', '-k', '30023']
cmd += ['-t', f'd={slug}']
cmd += ['-t', f'title={title}']
cmd += ['-t', f'summary={summary}']
cmd += ['-t', f'published_at={published_at}']
for tag in tags:
    if tag:
        cmd += ['-t', f't={tag}']
cmd += ['-c', content]
cmd += ['--sec', sk_hex]
cmd += relays

result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
if result.stdout:
    print(result.stdout)
if result.stderr:
    print(result.stderr)

print(f"✅ Published to Nostr as NIP-23 long-form event")
print(f"   View: https://habla.news/p/npub18p9nwam7647k9yftnutqffmevatrvum088400vrl338v6ak7jvnsuh789a/{slug}")
PYEOF
