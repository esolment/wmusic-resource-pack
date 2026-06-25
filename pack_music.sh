#!/bin/bash

set -e

if [ "$#" -ne 2 ]; then
  echo "Использование: $0 <папка с mp3> <папка выхода>"
  exit 1
fi

INPUT_DIR="$1"
OUTPUT_DIR="$2"

# Имена треков для каждой папки
declare -A SLOT_NAMES
SLOT_NAMES["."]="a_familiar_room an_ordinary_day ancestry below_and_above broken_clocks bromeliad clark comforting_memories crescent_dunes danny deeper dry_hands echo_in_the_wind eld_unknown endless featherfall fireflies floating_dream haggstrom infinite_amethyst key komorebi left_to_bloom lilypad living_mice mice_on_venus minecraft one_more_day os_piano oxygene pokopoko puzzlebox stand_tall subwoofer_lullaby sweden watcher wending wet_hands yakusoku"
SLOT_NAMES["creative"]="aria_math biome_fest blind_spots dreiton haunt_muskie taswell"
SLOT_NAMES["end"]="alpha boss the_end"
SLOT_NAMES["nether"]="ballad_of_the_cats concrete_halls dead_voxel warmth"
SLOT_NAMES["nether/crimson_forest"]="chrysopoeia"
SLOT_NAMES["nether/nether_wastes"]="rubedo"
SLOT_NAMES["nether/soulsand_valley"]="so_below"
SLOT_NAMES["swamp"]="aerie firebugs labyrinthine"
SLOT_NAMES["water"]="axolotl dragon_fish shuniji"

# Собираем mp3 файлы
mapfile -t MP3_FILES < <(find "$INPUT_DIR" -maxdepth 1 -name "*.mp3" | sort)
MP3_COUNT=${#MP3_FILES[@]}

if [ "$MP3_COUNT" -eq 0 ]; then
  echo "Ошибка: mp3 файлы не найдены в $INPUT_DIR"
  exit 1
fi

echo "Найдено $MP3_COUNT mp3 файл(ов): ${MP3_FILES[*]}"

# Конвертируем mp3 -> ogg во временную папку
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

echo ""
echo "Конвертация в ogg..."
OGG_FILES=()
for i in "${!MP3_FILES[@]}"; do
  mp3="${MP3_FILES[$i]}"
  ogg="$TMP_DIR/track_$i.ogg"
  echo "  $(basename "$mp3") -> track_$i.ogg"
  ffmpeg -i "$mp3" -c:a libvorbis -ac 1 -ar 44100 -q:a 4 -map_metadata -1 "$ogg" -y -loglevel error
  OGG_FILES+=("$ogg")
done

# Функция: распределить N файлов по слотам равномерно
distribute() {
  local subdir="$1"
  local slots_str="${SLOT_NAMES[$subdir]}"
  read -ra SLOTS <<< "$slots_str"
  local slot_count=${#SLOTS[@]}
  local ogg_count=${#OGG_FILES[@]}

  if [ "$subdir" == "." ]; then
    local dest="$OUTPUT_DIR"
  else
    local dest="$OUTPUT_DIR/$subdir"
  fi
  mkdir -p "$dest"

  echo ""
  echo "[$subdir] слотов: $slot_count, треков: $ogg_count"

  for i in "${!SLOTS[@]}"; do
    local slot="${SLOTS[$i]}"
    # Равномерное распределение: берём трек с индексом i mod ogg_count
    local ogg_idx=$((i % ogg_count))
    local src="${OGG_FILES[$ogg_idx]}"
    local dst="$dest/${slot}.ogg"
    cp "$src" "$dst"
    echo "  ${slot}.ogg <- track_${ogg_idx}.ogg"
  done
}

# Создаём все папки и распределяем
for subdir in "." "creative" "end" "nether" "nether/crimson_forest" "nether/nether_wastes" "nether/soulsand_valley" "swamp" "water"; do
  distribute "$subdir"
done

echo ""
echo "Готово! Файлы размещены в $OUTPUT_DIR"
