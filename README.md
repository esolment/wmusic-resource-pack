# WMusic Pack

Replace every piece of in-game Minecraft music with your own tracks — overworld, nether, end, creative, biomes, all of it — using a single script and a folder of MP3 files.

The script converts your MP3s to the OGG Vorbis format Minecraft expects, distributes them evenly across every music slot in the game, packages everything into a ready-to-use resource pack zip, and optionally patches the `pack.mcmeta` format version so the game doesn't complain about pack compatibility.

> **Platform note:** The script requires a Bash shell and `ffmpeg`. On **Linux** and **macOS** this works out of the box. On **Windows** you need WSL (Windows Subsystem for Linux) or Git Bash with ffmpeg available on the path — the native Windows command prompt and PowerShell are not supported.

---

## Quick start

### 1. Clone the repository

```bash
git clone https://github.com/esolment/wmusic-resource-pack.git
cd wmusic-resource-pack
```

### 2. Build the pack

Point the script at a folder containing your `.mp3` files and add `--auto` so it discovers all music slots directly from your Minecraft installation:

```bash
bash wmusic_pack.sh --auto ~/Music/my-tracks/
```

This will:
- auto-detect all Minecraft music slots from `~/.minecraft/assets/indexes/`
- convert your MP3s to OGG and distribute them across every slot
- write the result to `./wmusic_pack/`
- produce `./wmusic_pack.zip` ready to drop into Minecraft

### 3. Enable the resource pack in Minecraft

1. Copy or move `wmusic_pack.zip` into your `.minecraft/resourcepacks/` folder.
2. In Minecraft, open **Options → Resource Packs**.
3. Enable **WMusic Pack** and drag it **above** the default Minecraft pack in the list — priority goes top to bottom, so your pack must sit higher than the vanilla one.
4. Click **Done**. The new music plays immediately on the next track change.

---

## Full reference

### Usage

```
bash wmusic_pack.sh [OPTIONS] <input_dir> [output_dir]
```

| Argument | Description |
|---|---|
| `<input_dir>` | Directory containing your source `.mp3` files (non-recursive, top-level only). |
| `[output_dir]` | Directory where `wmusic_pack.zip` is saved. Default: `./` |

OGG files are always written to `./wmusic_pack/assets/minecraft/sounds/music/game/` and that directory is wiped clean at the start of each run.

Running the script with no arguments prints this reference.

---

### Options

#### `--auto`

Auto-discover all music slot names from your Minecraft assets index instead of reading `slots.txt`. The script finds the highest-numbered `.json` file in `~/.minecraft/assets/indexes/` and extracts every path under `minecraft/sounds/music/game/` from it.

```bash
bash wmusic_pack.sh --auto ~/Music/my-tracks/
```

Use this when you want to stay in sync with whatever version of Minecraft you currently have installed. The slots file is ignored when `--auto` is active.

---

#### `--slots-file=FILE`

Path to a custom slots file. Defaults to `slots.txt` in the same directory as the script. Ignored when `--auto` is used.

```bash
bash wmusic_pack.sh --slots-file=~/my-slots.txt ~/Music/my-tracks/
```

**Slots file format** — one OGG path per line, quotes optional, comments with `#`:

```
# This is exactly the output format of the grep command above
"minecraft/sounds/music/game/sweden.ogg"
"minecraft/sounds/music/game/creative/aria_math.ogg"
minecraft/sounds/music/game/end/the_end.ogg
```

Everything up to and including `game/` is stripped internally; the remainder determines the subdirectory and slot name. The included `slots.txt` covers all vanilla slots as of recent releases and can be used as-is or trimmed to only the slots you care about.

---

#### `--pack-format=N`, `--min-format=N`, `--max-format=N`

Patch the `pack_format` field in `./wmusic_pack/pack.mcmeta` to match your target Minecraft version. Any existing format fields are replaced; all other fields (like `description`) are left untouched.

Use `--pack-format` for a single value (older format):

```bash
bash wmusic_pack.sh --auto --pack-format=34 ~/Music/my-tracks/
```

Use `--min-format` and `--max-format` for a version range (1.20.2+):

```bash
bash wmusic_pack.sh --auto --min-format=75 --max-format=75 ~/Music/my-tracks/
```

Result in `pack.mcmeta`:

```json
{
  "pack": {
    "description": "WMusic Pack",
    "min_pack_format": 75,
    "max_pack_format": 75
  }
}
```

`--pack-format` and `--min-format`/`--max-format` are mutually exclusive.

---

#### `-h`, `--help`

Print the usage reference and exit.

---

### How tracks are distributed

If you provide fewer MP3 files than there are music slots, tracks are distributed in round-robin order — evenly cycling through your files. With one file, every slot gets that one track. With three files and thirty slots, the pattern repeats `0 1 2 0 1 2 …`. This means every biome and dimension gets music; nothing is left silent.

---

### Dependencies

| Tool | Purpose |
|---|---|
| `bash` 4.0+ | Script runtime (macOS ships bash 3 — use Homebrew bash or WSL) |
| `ffmpeg` | MP3 → OGG conversion |
| `zip` | Pack archiving |
| `python3` | `pack.mcmeta` patching (only needed with format flags) |
