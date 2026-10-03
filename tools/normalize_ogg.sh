#!/usr/bin/env bash
# Peak-normalize each ogg to TARGET dBFS, re-encoding at the engine's required
# 44.1 kHz (xrSound rejects any other rate), then re-inject the X-Ray
# ogg-comment block that re-encoding strips. Needs ffmpeg + python3 on PATH.
set -euo pipefail
TARGET=${II_PEAK_TARGET:--7.0}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for f in "$@"; do
	peak=$(ffmpeg -hide_banner -nostats -i "$f" -af volumedetect -f null - 2>&1 \
		| grep max_volume | tail -1 | sed 's/.*max_volume: //; s/ dB//')
	gain=$(awk -v t="$TARGET" -v p="$peak" 'BEGIN{printf "%.2f", t-p}')
	# Re-encoding is lossy, so leave a file that is already on target alone and
	# just make sure its X-Ray block is present.
	if awk -v g="$gain" 'BEGIN{exit !(g < 0.5 && g > -0.5)}'; then
		python3 "$here/xray_ogg_tag.py" "$f" >/dev/null
		printf '%-36s %+6s dB -> on target, kept\n' "$(basename "$f")" "$gain"
		continue
	fi
	ffmpeg -hide_banner -loglevel error -y -i "$f" \
		-af "volume=${gain}dB" -c:a libvorbis -b:a 96k -ar 44100 -ac 1 "$tmp/out.ogg"
	mv "$tmp/out.ogg" "$f"
	python3 "$here/xray_ogg_tag.py" "$f" >/dev/null
	new=$(ffmpeg -hide_banner -nostats -i "$f" -af volumedetect -f null - 2>&1 \
		| grep max_volume | sed 's/.*max_volume: //')
	printf '%-36s %+6s dB -> peak %s\n' "$(basename "$f")" "$gain" "$new"
done
