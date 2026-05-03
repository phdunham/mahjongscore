#!/usr/bin/env bash
# Report photo counts per tile folder and flag anything thin. Run this after
# you AirDrop/organize photos into training-data/.
#
# Output: one line per tile, sorted by category, with a status marker.
#
#     1m   45 photos ✓
#     2m   14 photos ⚠ (below 20)
#     3m    0 photos ✗ (empty)
#
# Accepts JPEG/JPG/HEIC (HEIC counted but you'll want to convert later).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here"

root="training-data"
if [[ ! -d "$root" ]]; then
    echo "No $root/ directory. Run scripts/init-training-dirs.sh first." >&2
    exit 1
fi

MIN_PER_TILE="${MIN_PER_TILE:-20}"

count_images() {
    local dir="$1"
    find "$dir" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.heic' \) \
        2>/dev/null | wc -l | tr -d ' '
}

# In a deterministic order the eye can scan.
ordered_tiles=(
    1m 2m 3m 4m 5m 6m 7m 8m 9m
    1p 2p 3p 4p 5p 6p 7p 8p 9p
    1s 2s 3s 4s 5s 6s 7s 8s 9s
    Ew Sw Ww Nw
    Rd Gd Wd
    1f 2f 3f 4f 5f 6f 7f 8f
)

total=0
thin_count=0
empty_count=0

for tile in "${ordered_tiles[@]}"; do
    dir="$root/$tile"
    if [[ ! -d "$dir" ]]; then
        printf "  %-4s     —  photos ✗ (folder missing — run scripts/init-training-dirs.sh)\n" "$tile"
        empty_count=$((empty_count + 1))
        continue
    fi
    count=$(count_images "$dir")
    total=$((total + count))
    if [[ "$count" -eq 0 ]]; then
        marker="✗ (empty)"
        empty_count=$((empty_count + 1))
    elif [[ "$count" -lt "$MIN_PER_TILE" ]]; then
        marker="⚠ (below $MIN_PER_TILE)"
        thin_count=$((thin_count + 1))
    else
        marker="✓"
    fi
    printf "  %-4s  %4d  photos  %s\n" "$tile" "$count" "$marker"
done

echo ""
printf "Total: %d photos · %d/%d tiles ≥ %d photos · %d thin · %d empty\n" \
    "$total" $((42 - thin_count - empty_count)) 42 "$MIN_PER_TILE" "$thin_count" "$empty_count"

if [[ "$empty_count" -gt 0 || "$thin_count" -gt 0 ]]; then
    echo ""
    echo "Keep going — you want every tile ≥ $MIN_PER_TILE photos before training."
    exit 2
else
    echo ""
    echo "Ready to train. Open Xcode → Developer Tool → Create ML → Image Classifier,"
    echo "and point it at: $(pwd)/$root/"
fi
