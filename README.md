# 📦 extractor.lua

![LuaJIT](https://img.shields.io/badge/LuaJIT-2.1-000080?logo=lua&logoColor=white)
![libarchive](https://img.shields.io/badge/libarchive-3.x-4c9a2a)
![FFI](https://img.shields.io/badge/binding-LuaJIT%20FFI-orange)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey)

An archive extractor written in Lua that calls **libarchive** directly through **LuaJIT's FFI**, with no intermediate C modules. A single script opens `.zip`, `.tar.gz`, `.tar.xz`, `.tar.bz2`, `.rar`, `.7z` and the other formats libarchive recognizes.

---

## ✨ Features

- 🔍 Auto-detects the compression filter (gzip, bzip2, xz, zstd...) and the container format (zip, tar, rar, 7z...)
- 📂 Recreates the original folder structure
- 🛡️ Blocks *zip slip*: entries with absolute paths or `..` components are skipped
- ⚠️ Reports non-fatal libarchive warnings without stopping the extraction
- 🧾 Prints the name and size of each extracted entry
- 📚 Accepts several archives in a single call

## 🧠 How it works

The script declares libarchive's C signatures with `ffi.cdef` and loads the system library with `ffi.load("archive")`. From there it follows the read lifecycle described in the official documentation:

```
archive_read_new()
  └─ archive_read_support_filter_all() / archive_read_support_format_all()
       └─ archive_read_open_filename()
            └─ loop: archive_read_next_header() → archive_read_data()
                 └─ archive_read_close() → archive_read_free()
```

Each entry is written to disk in 8 KB chunks, using a buffer allocated with `ffi.new("char[?]", 8192)`.

### Return codes

| Code | Value | What the script does |
|---|---|---|
| `ARCHIVE_EOF` | 1 | Ends the loop |
| `ARCHIVE_OK` | 0 | Extracts the entry |
| `ARCHIVE_WARN` | -20 | Prints the warning and extracts the entry anyway |
| anything lower | < -20 | Prints the error and stops reading that archive |

## 🛠️ Requirements

| Dependency | Why |
|---|---|
| **LuaJIT 2.x** | The `ffi` library only exists in LuaJIT. Standard Lua (5.1 to 5.4) **cannot** run this script |
| **libarchive** (with the `libarchive.so` link) | The C library that reads the formats |
| Unix-like system | The script calls `mkdir -p` through `os.execute` |

> ℹ️ On Debian/Ubuntu, the `libarchive13` package only ships `libarchive.so.13`. `ffi.load("archive")` looks for `libarchive.so`, which comes with `libarchive-dev`.

### Installing dependencies manually

```bash
# Debian / Ubuntu
sudo apt install luajit libarchive-dev

# Fedora
sudo dnf install luajit libarchive-devel

# Arch Linux
sudo pacman -S luajit libarchive

# Alpine
sudo apk add luajit libarchive-dev

# macOS (Homebrew)
brew install luajit libarchive
```

## 🚀 Usage

```bash
luajit extractor.lua file.zip
luajit extractor.lua project.tar.gz backup.tar.xz photos.rar
```

Files are extracted into the **current directory**.

Sample output, including an archive with malicious paths:

```
=== Reading file: good.tar.gz ===
Extracting: proj/src/main.lua (12 bytes)
Extracting: proj/it's dir/a.txt (11 bytes)
Processing finished successfully.

=== Reading file: evil.tar ===
Skipping unsafe path: ../escaped.txt
Skipping unsafe path: /tmp/abs_escape.txt
Skipping unsafe path: ok/../../escaped2.txt
Extracting: safe.txt (5 bytes)
Processing finished successfully.
```

## 📥 Install script (optional)

To avoid typing `luajit extractor.lua` every time, the `install.sh` below installs the dependencies and creates a `lextract` command in `~/.local/bin`. Save it in the same folder as `extractor.lua`:

```sh
#!/usr/bin/env sh
# install.sh: installs dependencies and creates the "lextract" command
set -e

install_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y luajit libarchive-dev
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y luajit libarchive-devel
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm luajit libarchive
  elif command -v apk >/dev/null 2>&1; then
    sudo apk add luajit libarchive-dev
  elif command -v brew >/dev/null 2>&1; then
    brew install luajit libarchive
  else
    echo "Package manager not recognized. Install LuaJIT and libarchive manually." >&2
    exit 1
  fi
}

install_deps

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

# On macOS, Homebrew's libarchive is not on the default library path
LIB_HINT=""
if [ "$(uname)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
  LIB_HINT="export DYLD_FALLBACK_LIBRARY_PATH=\"$(brew --prefix libarchive)/lib\""
fi

cat > "$BIN_DIR/lextract" <<EOF
#!/usr/bin/env sh
$LIB_HINT
exec luajit "$SCRIPT_DIR/extractor.lua" "\$@"
EOF
chmod +x "$BIN_DIR/lextract"

echo "Done. Usage: lextract file.zip"
echo "If the command is not found, add $BIN_DIR to your PATH."
```

```bash
chmod +x install.sh
./install.sh
lextract file.tar.gz
```

> ⚠️ macOS support in the install script has not been tested.

## ⚠️ Known limitations

- 🔗 Symbolic links, permissions and modification times are not preserved. Symlink entries become empty regular files.
- 🗂️ The path check only inspects the names inside the archive. If a folder in the current directory is already a symlink pointing elsewhere, writes will follow it.
- 🪟 Does not run on Windows because it depends on `mkdir -p`.

For full-featured extraction, libarchive offers the `archive_write_disk` API with the `ARCHIVE_EXTRACT_SECURE_*` flags, shown in the "A Complete Extractor" example on the official wiki.

## 📖 What I learned

This project came together after reading the [libarchive examples page](https://github.com/libarchive/libarchive/wiki/Examples) many times. The main lesson: the documentation already had the answer; the work was learning to read it and translating the C examples into FFI calls in Lua.

## 🔗 References

- [libarchive: Examples (official wiki)](https://github.com/libarchive/libarchive/wiki/Examples)
- [libarchive: archive.h (return codes)](https://github.com/libarchive/libarchive/blob/master/libarchive/archive.h)
- [libarchive: project site](https://libarchive.org/)
- [LuaJIT: FFI Library](https://luajit.org/ext_ffi.html)
- [LuaJIT: ffi.* API](https://luajit.org/ext_ffi_api.html)
