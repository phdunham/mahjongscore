#!/usr/bin/env bash
# Walk through all 42 mahjong tile kinds and record a short burst of frames
# for each, using the TileCam Swift helper. Per tile: press any key to start
# the burst, rotate/tilt the tile for the burst duration, and TileCam writes
# every video frame to disk as a JPEG (~30 fps → ~90 frames per 3-sec burst).
#
# Usage:
#   scripts/capture-tiles.sh [-s SECS] [-f FPS] [-m MIN_FRAMES] [-o OUT_DIR]
#
# Options:
#   -s, --seconds SECS       burst duration per tile (default 3)
#   -f, --fps N              cap burst frame rate (default 10 fps → ~30 frames
#                            over a 3s burst; 0 = camera's native rate)
#   -m, --min-frames N       skip tile if it already has >= N jpegs (default 30)
#   -o, --out   DIR          output dir (default <repo>/tile-photos)
#
# Environment:
#   TILECAM_DEVICE     exact localizedName of camera (see `TileCam --list`)
#
# Controls (single keypress, no Enter needed):
#   <any other key>   start a burst of the current tile
#   n                 skip this tile
#   q                 quit
# After each burst:
#   r                 retake — delete the burst's frames and record again
#   <any other key>   next tile
#
# Photos are written to <output_dir>/<notation>/<notation>_NNNN.jpeg, numbered
# max+1 so re-running the script extends the set instead of overwriting.
set -euo pipefail

export TILECAM_DEVICE="Big River Camera"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

burst_seconds=3
burst_fps=10
min_frames=30
out_dir="$here/tile-photos"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--seconds)    burst_seconds="$2"; shift 2 ;;
        -f|--fps)        burst_fps="$2"; shift 2 ;;
        -m|--min-frames) min_frames="$2"; shift 2 ;;
        -o|--out)        out_dir="$2"; shift 2 ;;
        -h|--help)       sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)               echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# TileCam binary — build on demand.
# ---------------------------------------------------------------------------
tile_cam_bin="$here/.build/release/TileCam"
if [[ ! -x "$tile_cam_bin" ]]; then
    echo "Building TileCam…"
    (cd "$here" && swift build -c release --product TileCam)
fi
if [[ ! -x "$tile_cam_bin" ]]; then
    echo "error: TileCam binary not found at $tile_cam_bin" >&2
    exit 1
fi

device="${TILECAM_DEVICE:-}"

# ---------------------------------------------------------------------------
# TileCam coprocess over FIFOs.
# ---------------------------------------------------------------------------
cam_pid=""
cam_tmpdir=""
cam_init() {
    cam_tmpdir=$(mktemp -d -t tilecam)
    local in_fifo="$cam_tmpdir/in" out_fifo="$cam_tmpdir/out"
    mkfifo "$in_fifo" "$out_fifo"
    exec 3<>"$in_fifo"
    exec 4<>"$out_fifo"

    local args=()
    [[ -n "$device" ]] && args+=(--device "$device")
    (( burst_fps > 0 )) && args+=(--fps "$burst_fps")
    "$tile_cam_bin" "${args[@]}" <"$in_fifo" >"$out_fifo" 2>"$cam_tmpdir/err" &
    cam_pid=$!

    local line
    for _ in $(seq 1 60); do
        if IFS= read -r -t 1 -u 4 line; then
            case "$line" in
                ready*) echo "Camera ready: ${line#ready }"; return 0 ;;
                err*)   echo "  $line" >&2 ;;
                *)      echo "  unexpected from TileCam: $line" >&2 ;;
            esac
        fi
        if ! kill -0 "$cam_pid" 2>/dev/null; then
            echo "error: TileCam died during startup. stderr:" >&2
            cat "$cam_tmpdir/err" >&2 || true
            return 1
        fi
    done
    echo "error: TileCam did not signal ready in time. stderr:" >&2
    cat "$cam_tmpdir/err" >&2 || true
    return 1
}

cam_shutdown() {
    [[ -z "${cam_pid:-}" ]] && return 0
    echo "quit" >&3 2>/dev/null || true
    for _ in 1 2 3 4 5; do
        kill -0 "$cam_pid" 2>/dev/null || break
        sleep 0.1
    done
    if kill -0 "$cam_pid" 2>/dev/null; then
        kill "$cam_pid" 2>/dev/null || true
    fi
    wait "$cam_pid" 2>/dev/null || true
    exec 3>&- 2>/dev/null || true
    exec 4<&- 2>/dev/null || true
    [[ -n "$cam_tmpdir" ]] && rm -rf "$cam_tmpdir"
}

cam_read_response() {
    local _line
    if IFS= read -r -t 15 -u 4 _line; then
        echo "$_line"
        return 0
    fi
    echo ""
    return 1
}

cam_capture() {
    local path="$1" line
    echo "capture $path" >&3
    line=$(cam_read_response) || { echo "  TileCam response timeout" >&2; return 1; }
    case "$line" in
        ok*)  return 0 ;;
        err*) echo "  TileCam: ${line#err }" >&2; return 1 ;;
        *)    echo "  TileCam unexpected: $line" >&2; return 1 ;;
    esac
}

cam_burst_start() {
    local start_idx="$1" prefix="$2" dir="$3" line
    echo "burst_start $start_idx $prefix $dir" >&3
    line=$(cam_read_response) || { echo "  TileCam response timeout" >&2; return 1; }
    case "$line" in
        "ok burst_started") return 0 ;;
        err*) echo "  TileCam: ${line#err }" >&2; return 1 ;;
        *)    echo "  TileCam unexpected: $line" >&2; return 1 ;;
    esac
}

# Sets globals: BURST_COUNT, BURST_ERRORS, BURST_FIRST, BURST_LAST
cam_burst_stop() {
    local line
    echo "burst_stop" >&3
    line=$(cam_read_response) || { echo "  TileCam response timeout" >&2; return 1; }
    case "$line" in
        "ok burst "*)
            # "ok burst count=N errors=M first=i last=j"
            BURST_COUNT=$(echo "$line" | sed -E 's/.*count=([0-9]+).*/\1/')
            BURST_ERRORS=$(echo "$line" | sed -E 's/.*errors=([0-9]+).*/\1/')
            BURST_FIRST=$(echo "$line" | sed -E 's/.*first=([0-9]+).*/\1/')
            BURST_LAST=$(echo "$line" | sed -E 's/.*last=(-?[0-9]+).*/\1/')
            return 0
            ;;
        err*) echo "  TileCam: ${line#err }" >&2; return 1 ;;
        *)    echo "  TileCam unexpected: $line" >&2; return 1 ;;
    esac
}

trap cam_shutdown EXIT INT TERM

# ---------------------------------------------------------------------------
tiles=(
    "1m|1萬" "2m|2萬" "3m|3萬" "4m|4萬" "5m|5萬" "6m|6萬" "7m|7萬" "8m|8萬" "9m|9萬"
    "1p|1筒" "2p|2筒" "3p|3筒" "4p|4筒" "5p|5筒" "6p|6筒" "7p|7筒" "8p|8筒" "9p|9筒"
    "1s|1條" "2s|2條" "3s|3條" "4s|4條" "5s|5條" "6s|6條" "7s|7條" "8s|8條" "9s|9條"
    "Ew|東" "Sw|南" "Ww|西" "Nw|北"
    "Rd|中" "Gd|發" "Wd|白"
    "1f|春" "2f|夏" "3f|秋" "4f|冬"
    "5f|梅" "6f|蘭" "7f|菊" "8f|竹"
)

total=${#tiles[@]}
echo "Output directory: $out_dir"
echo "Burst duration:   ${burst_seconds}s"
if (( burst_fps > 0 )); then
    echo "Burst frame rate: ${burst_fps} fps (~$((burst_fps * burst_seconds)) frames/burst)"
else
    echo "Burst frame rate: camera native"
fi
echo "Skip threshold:   ${min_frames} frames"
if [[ -n "$device" ]]; then
    echo "Camera device:    $device"
else
    echo "Camera device:    (system default — set TILECAM_DEVICE to override)"
fi
echo "Tiles to capture: $total"
echo

cam_init

read_key() {
    local old_stty
    old_stty=$(stty -g)
    stty raw -echo
    key=$(dd bs=1 count=1 2>/dev/null || true)
    stty "$old_stty"
    printf "\n"
}

next_index() {
    local d="$1" highest
    highest=$(find "$d" -maxdepth 1 -type f -name '*.jpeg' 2>/dev/null \
        | sed 's|.*_||; s|\.jpeg$||' \
        | grep -E '^[0-9]+$' \
        | sort -n | tail -1 || true)
    echo $(( 10#${highest:-0} + 1 ))
}

# Runs one burst for $notation into $dir, showing a progress bar. Sets the
# BURST_* globals from cam_burst_stop.
run_burst() {
    local dir="$1" notation="$2" start_idx="$3"
    cam_burst_start "$start_idx" "$notation" "$dir" || return 1

    # Tenth-second countdown, overwriting a single line.
    local total_ticks=$(( burst_seconds * 10 ))
    local i=0 secs tenths
    while (( i < total_ticks )); do
        local remaining=$(( total_ticks - i ))
        secs=$(( remaining / 10 ))
        tenths=$(( remaining % 10 ))
        printf "\r  recording  %d.%ds remaining   " "$secs" "$tenths"
        sleep 0.1
        i=$((i + 1))
    done
    printf "\r  recording  done            \n"

    cam_burst_stop || return 1
    return 0
}

delete_range() {
    local dir="$1" prefix="$2" first="$3" last="$4" n
    (( last < first )) && return 0
    for (( n = first; n <= last; n++ )); do
        local f="$dir/${prefix}_$(printf '%04d' "$n").jpeg"
        [[ -f "$f" ]] && rm -- "$f"
    done
}

quit=0
for (( i = 0; i < total; i++ )); do
    (( quit )) && break
    entry="${tiles[$i]}"
    notation="${entry%%|*}"
    display="${entry##*|}"
    dir="$out_dir/$notation"
    mkdir -p "$dir"

    while true; do
        existing=$(find "$dir" -maxdepth 1 -type f -name '*.jpeg' 2>/dev/null | wc -l | tr -d ' ')
        printf "\n=== [%2d/%d] %-2s  %s   (have %d, min %d) ===\n" \
            "$((i + 1))" "$total" "$notation" "$display" "$existing" "$min_frames"

        if (( existing >= min_frames )); then
            echo "  target reached — skipping."
            break
        fi

        printf "  any key = burst %ds · [n]ext tile · [q]uit: " "$burst_seconds"
        read_key
        case "$key" in
            q|Q) echo "  quitting."; quit=1; break ;;
            n|N) echo "  skipping."; break ;;
        esac

        first_idx=$(next_index "$dir")
        if ! run_burst "$dir" "$notation" "$first_idx"; then
            echo "  burst failed — try again."
            continue
        fi

        printf "  captured %d frame(s)" "$BURST_COUNT"
        (( BURST_ERRORS > 0 )) && printf ", %d error(s)" "$BURST_ERRORS"
        printf " → %s_%04d.jpeg … %s_%04d.jpeg\n" \
            "$notation" "$BURST_FIRST" "$notation" "$BURST_LAST"

        printf "  [r]etake (delete & rerecord) · any other key = next tile · [q]uit: "
        read_key
        case "$key" in
            q|Q)
                echo "  quitting."; quit=1; break ;;
            r|R)
                echo "  deleting ${BURST_COUNT} frames; rerecording…"
                delete_range "$dir" "$notation" "$BURST_FIRST" "$BURST_LAST"
                # loop back for another burst on the same tile
                ;;
            *)
                break ;;
        esac
    done
done

echo
echo "done."
