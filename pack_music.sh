#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_SLOTS_FILE="$SCRIPT_DIR/slots.txt"
DEFAULT_OUTPUT_AUDIO_DIR="./wmusic_pack/assets/minecraft/sounds/music/game"
DEFAULT_OUTPUT_DIR="./"
PACK_ROOT="./wmusic_pack"

# ─── Help ────────────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <input_dir> [output_dir]

Distributes MP3 files evenly across Minecraft music slot names,
converting them to OGG along the way, then zips the result.

Arguments:
  <input_dir>    Directory containing source .mp3 files.
  [output_dir]   Directory where the final wmusic_pack.zip is saved.
                 Default: ./ (current directory)

  OGG files are always placed in:
    ./wmusic_pack/assets/minecraft/sounds/music/game/

Options:
  --slots-file=FILE   Path to the slot-list file.
                      Default: slots.txt next to this script.
                      Ignored when --auto is used.

  --auto              Auto-discover slot names from a Minecraft assets index
                      instead of reading a slots file. Finds the largest
                      numeric .json in ~/.minecraft/assets/indexes/ and greps
                      it for music paths under minecraft/sounds/music/game/.
                      Combine with --indexes-file= to use a specific index.

  --indexes-file=X    Index file to use with --auto. Two forms are accepted:
                        - A bare name (with or without .json extension):
                            --indexes-file=30
                            --indexes-file=30.json
                          Looks for that file in ~/.minecraft/assets/indexes/.
                        - A full or relative path:
                            --indexes-file=/path/to/my.json
                          Uses the file directly.
                      Ignored when --auto is not set.

  --pack-format=N     Set pack_format in pack.mcmeta (mutually exclusive
                      with --min-format / --max-format).
  --min-format=N      Set min_pack_format in pack.mcmeta.
  --max-format=N      Set max_pack_format in pack.mcmeta.
                      Any existing format fields are removed before writing.
                      Other fields (e.g. description) are left untouched.

  -h, --help          Show this help and exit.

Slot-list file format (slots.txt):
  One OGG path per line, optionally quoted. Paths must contain
  minecraft/sounds/music/game/ — everything up to and including "game/"
  is stripped to derive the subdirectory and slot name. Example:

    "minecraft/sounds/music/game/sweden.ogg"
    "minecraft/sounds/music/game/creative/aria_math.ogg"
    minecraft/sounds/music/game/end/the_end.ogg

  This is exactly the format produced by:
    grep -o '"minecraft/sounds/music/[^"]*"' ~/.minecraft/assets/indexes/30.json
EOF
}

# ─── Defaults ────────────────────────────────────────────────────────────────

SLOTS_FILE="$DEFAULT_SLOTS_FILE"
AUTO=0
PACK_FORMAT=""
MIN_FORMAT=""
MAX_FORMAT=""
INPUT_DIR=""
OUTPUT_DIR=""
INDEXES_FILE=""

# ─── Argument parsing ─────────────────────────────────────────────────────────

if [ "$#" -eq 0 ]; then
  usage
  exit 0
fi

POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --auto)
      AUTO=1
      ;;
    --slots-file=*)
      SLOTS_FILE="${arg#*=}"
      ;;
    --indexes-file=*)
      INDEXES_FILE="${arg#*=}"
      ;;
    --pack-format=*)
      PACK_FORMAT="${arg#*=}"
      ;;
    --min-format=*)
      MIN_FORMAT="${arg#*=}"
      ;;
    --max-format=*)
      MAX_FORMAT="${arg#*=}"
      ;;
    --*)
      echo "Error: Unknown option: $arg"
      echo "Run '$(basename "$0") --help' for usage."
      exit 1
      ;;
    *)
      POSITIONAL+=("$arg")
      ;;
  esac
done

if [ "${#POSITIONAL[@]}" -lt 1 ] || [ "${#POSITIONAL[@]}" -gt 2 ]; then
  echo "Error: Expected 1 or 2 positional arguments: <input_dir> [output_dir]"
  echo "Run '$(basename "$0") --help' for usage."
  exit 1
fi

INPUT_DIR="${POSITIONAL[0]}"
OUTPUT_AUDIO_DIR="$DEFAULT_OUTPUT_AUDIO_DIR"
OUTPUT_DIR="${POSITIONAL[1]:-$DEFAULT_OUTPUT_DIR}"

# Validate format flags
if [ -n "$PACK_FORMAT" ] && { [ -n "$MIN_FORMAT" ] || [ -n "$MAX_FORMAT" ]; }; then
  echo "Error: --pack-format cannot be combined with --min-format / --max-format."
  exit 1
fi

# ─── Parse OGG path list into SLOT_NAMES ─────────────────────────────────────
# Input: array of raw path strings (with or without quotes), e.g.:
#   "minecraft/sounds/music/game/creative/aria_math.ogg"
# Strips everything up to and including "game/", then splits into subdir+slot.
# Root-level files (no subdir under game/) go into key ".".

parse_paths_into_slots() {
  local -n _paths=$1   # nameref to input array
  declare -gA SLOT_NAMES

  declare -A TMP_SLOTS
  for raw in "${_paths[@]}"; do
    # Strip surrounding quotes if present
    path="${raw//\"/}"
    # Check path contains the expected prefix
    if [[ "$path" != *"minecraft/sounds/music/game/"* ]]; then
      continue
    fi
    # Strip everything up to and including "game/"
    rel="${path#*minecraft/sounds/music/game/}"
    # Strip .ogg extension
    rel="${rel%.ogg}"
    dir=$(dirname "$rel")
    slot=$(basename "$rel")
    if [ "$dir" = "." ]; then
      TMP_SLOTS["."]+=" $slot"
    else
      TMP_SLOTS["$dir"]+=" $slot"
    fi
  done

  for key in "${!TMP_SLOTS[@]}"; do
    SLOT_NAMES["$key"]="${TMP_SLOTS[$key]# }"
  done
}

# ─── Load slot names ──────────────────────────────────────────────────────────

declare -A SLOT_NAMES

if [ "$AUTO" -eq 1 ]; then
  echo "Auto-discovering slot names from Minecraft assets..."

  INDEXES_DIR="$HOME/.minecraft/assets/indexes"

  if [ -n "$INDEXES_FILE" ]; then
    # If it looks like a path (contains a slash), use it directly.
    # Otherwise treat it as a bare name inside the default indexes directory.
    if [[ "$INDEXES_FILE" == */* ]]; then
      INDEX_FILE="$INDEXES_FILE"
    else
      # Strip .json suffix if provided, then add it back for consistency
      INDEX_NAME="${INDEXES_FILE%.json}"
      INDEX_FILE="$INDEXES_DIR/${INDEX_NAME}.json"
    fi
    if [ ! -f "$INDEX_FILE" ]; then
      echo "Error: Index file not found: $INDEX_FILE"
      exit 1
    fi
    echo "Using index: $INDEX_FILE (manually specified)"
  else
    if [ ! -d "$INDEXES_DIR" ]; then
      echo "Error: Minecraft assets index directory not found: $INDEXES_DIR"
      exit 1
    fi

    # Find the index file with the largest numeric stem.
    # The stem number is the assets index version and increases with each
    # Minecraft release — so the largest one matches the newest installed version.
    LATEST_INDEX=$(ls "$INDEXES_DIR"/*.json 2>/dev/null \
      | sed 's|.*/||; s|\.json$||' \
      | grep -E '^[0-9]+$' \
      | sort -n \
      | tail -1)

    if [ -z "$LATEST_INDEX" ]; then
      echo "Error: No numeric .json index files found in $INDEXES_DIR"
      echo "Use --indexes-file= to point to an index file manually."
      exit 1
    fi

    INDEX_FILE="$INDEXES_DIR/${LATEST_INDEX}.json"
    echo "Using index: $INDEX_FILE"
  fi

  mapfile -t RAW_PATHS < <(
    grep -o '"minecraft/sounds/music/[^"]*"' "$INDEX_FILE" | sort -u
  )

  if [ "${#RAW_PATHS[@]}" -eq 0 ]; then
    echo "Error: No music paths found in $INDEX_FILE"
    exit 1
  fi

  echo "Found ${#RAW_PATHS[@]} music entries."
  parse_paths_into_slots RAW_PATHS

else
  if [ ! -f "$SLOTS_FILE" ]; then
    echo "Error: Slots file not found: $SLOTS_FILE"
    echo "Create it or use --auto to discover slots automatically."
    echo "Run '$(basename "$0") --help' for file format details."
    exit 1
  fi

  mapfile -t RAW_PATHS < <(grep -v '^\s*#' "$SLOTS_FILE" | grep -v '^\s*$')

  if [ "${#RAW_PATHS[@]}" -eq 0 ]; then
    echo "Error: No paths found in $SLOTS_FILE"
    exit 1
  fi

  parse_paths_into_slots RAW_PATHS
  echo "Loaded ${#SLOT_NAMES[@]} subdirectory group(s) from $SLOTS_FILE"
fi

if [ "${#SLOT_NAMES[@]}" -eq 0 ]; then
  echo "Error: Could not find any minecraft/sounds/music/game/ paths."
  exit 1
fi

# ─── Collect MP3 files ────────────────────────────────────────────────────────

mapfile -t MP3_FILES < <(find "$INPUT_DIR" -maxdepth 1 -name "*.mp3" | sort)
MP3_COUNT=${#MP3_FILES[@]}

if [ "$MP3_COUNT" -eq 0 ]; then
  echo "Error: No .mp3 files found in $INPUT_DIR"
  exit 1
fi

echo "Found $MP3_COUNT MP3 file(s): ${MP3_FILES[*]}"

# ─── Convert MP3 → OGG ───────────────────────────────────────────────────────

TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

echo ""
echo "Converting to OGG..."
OGG_FILES=()
for i in "${!MP3_FILES[@]}"; do
  mp3="${MP3_FILES[$i]}"
  ogg="$TMP_DIR/track_$i.ogg"
  echo "  $(basename "$mp3") -> track_$i.ogg"
  ffmpeg -i "$mp3" -c:a libvorbis -ac 1 -ar 44100 -q:a 4 -map_metadata -1 "$ogg" -y -loglevel error
  OGG_FILES+=("$ogg")
done

# ─── Distribute OGG files into slot names ─────────────────────────────────────

distribute() {
  local subdir="$1"
  local slots_str="${SLOT_NAMES[$subdir]}"
  read -ra SLOTS <<< "$slots_str"
  local slot_count=${#SLOTS[@]}
  local ogg_count=${#OGG_FILES[@]}

  if [ "$subdir" = "." ]; then
    local dest="$OUTPUT_AUDIO_DIR"
  else
    local dest="$OUTPUT_AUDIO_DIR/$subdir"
  fi

  mkdir -p "$dest"
  echo ""
  echo "[$subdir] slots: $slot_count, tracks: $ogg_count"

  for i in "${!SLOTS[@]}"; do
    local slot="${SLOTS[$i]}"
    local ogg_idx=$((i % ogg_count))
    local src="${OGG_FILES[$ogg_idx]}"
    local dst="$dest/${slot}.ogg"
    cp "$src" "$dst"
    echo "  ${slot}.ogg <- track_${ogg_idx}.ogg"
  done
}

# ─── Clean output audio dir ───────────────────────────────────────────────────

if [ -d "$OUTPUT_AUDIO_DIR" ]; then
  echo ""
  echo "Cleaning $OUTPUT_AUDIO_DIR ..."
  rm -rf "$OUTPUT_AUDIO_DIR"
fi
mkdir -p "$OUTPUT_AUDIO_DIR"

for subdir in "${!SLOT_NAMES[@]}"; do
  distribute "$subdir"
done

# ─── Update pack.mcmeta ───────────────────────────────────────────────────────

MCMETA="$PACK_ROOT/pack.mcmeta"

update_mcmeta() {
  if [ ! -f "$MCMETA" ]; then
    echo ""
    echo "Warning: $MCMETA not found, skipping format update."
    return
  fi

  python3 - "$MCMETA" "$PACK_FORMAT" "$MIN_FORMAT" "$MAX_FORMAT" <<'PYEOF'
import sys, json

path        = sys.argv[1]
pack_format = sys.argv[2]
min_format  = sys.argv[3]
max_format  = sys.argv[4]

with open(path) as f:
    data = json.load(f)

pack = data.setdefault("pack", {})

for field in ("pack_format", "min_pack_format", "max_pack_format"):
    pack.pop(field, None)

if pack_format:
    pack["pack_format"] = int(pack_format)
elif min_format or max_format:
    if min_format:
        pack["min_pack_format"] = int(min_format)
    if max_format:
        pack["max_pack_format"] = int(max_format)

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"Updated {path}: pack section = {json.dumps(pack)}")
PYEOF
}

if [ -n "$PACK_FORMAT" ] || [ -n "$MIN_FORMAT" ] || [ -n "$MAX_FORMAT" ]; then
  update_mcmeta
fi

# ─── Zip the pack ────────────────────────────────────────────────────────────

echo ""
echo "Packaging wmusic_pack.zip..."

mkdir -p "$OUTPUT_DIR"
ZIP_PATH="$(realpath "$OUTPUT_DIR")/wmusic_pack.zip"

# Remove stale zip if it exists
rm -f "$ZIP_PATH"

# zip from inside PACK_ROOT so archive paths start with the pack contents,
# not the wmusic_pack/ wrapper directory itself
(cd "$PACK_ROOT" && zip -r "$ZIP_PATH" .)

echo "Created: $ZIP_PATH"

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "Done! OGG files placed in $OUTPUT_AUDIO_DIR"
echo "      Zip saved to $ZIP_PATH"
