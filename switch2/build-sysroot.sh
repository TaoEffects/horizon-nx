#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
toolkit_dir="${HORIZON_TOOLKIT_DIR:-$root/../horizon-switch-toolkit/switch}"
libc_patch="$toolkit_dir/patches/libc-0.2.191"
target=aarch64-switch-horizon
toolchain="${RUST_NIGHTLY:-nightly-2026-07-02}"
export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
export PATH="$DEVKITPRO/devkitA64/bin:$PATH"
export RUSTC_BOOTSTRAP=1
export RUST_TARGET_PATH="$root/switch2"

# build-std ignores the workspace's [patch.crates-io], so without a patched copy
# of rust-src, std builds against crates.io libc (3DS ARM32 struct stat/dirent
# layouts), breaking Path::is_dir/is_file/exists and DirEntry::file_type.
sysroot="$(rustc +"$toolchain" --print sysroot)"
std_src="$sysroot/lib/rustlib/src/rust/library"
std_dest="$root/target/switch2-rust-src"
std_stamp="$std_dest/.prepared"
std_want="$(rustc +"$toolchain" -V) $libc_patch v1"
if [ ! -f "$std_stamp" ] || [ "$(cat "$std_stamp")" != "$std_want" ]; then
    [ -d "$std_src" ] || { echo "error: no rust-src in $sysroot" >&2; exit 1; }
    [ -d "$libc_patch" ] || { echo "error: missing patched libc at $libc_patch" >&2; exit 1; }
    rm -rf "$std_dest"
    mkdir -p "$std_dest"
    cp -r "$std_src" "$std_dest/library"
    python3 - "$std_dest/library" "$libc_patch" <<'PY'
import pathlib, re, sys

lib_dir = pathlib.Path(sys.argv[1])
libc_patch = sys.argv[2]

cargo_toml = lib_dir / "Cargo.toml"
toml_text = cargo_toml.read_text()
patch_line = f'libc = {{ path = "{libc_patch}" }}\n'
if 'libc = { path =' not in toml_text:
    marker = "windows-sys = { path = 'windows-sys' }\n"
    if marker not in toml_text:
        raise SystemExit("error: could not find patch marker in library/Cargo.toml")
    toml_text = toml_text.replace(marker, marker + patch_line, 1)
    cargo_toml.write_text(toml_text)

cargo_lock = lib_dir / "Cargo.lock"
lock_text = cargo_lock.read_text()
lock_text = re.sub(
    r'(\[\[package\]\]\nname = "libc"\nversion = "[^"]+"\n)source = "[^"]+"\n(checksum = "[^"]+"\n)?',
    r"\1",
    lock_text,
)
cargo_lock.write_text(lock_text)

sock_mod = lib_dir / "std/src/sys/net/connection/socket/mod.rs"
sock_text = sock_mod.read_text()
old_sock = """        sock.set_nonblocking(false)?;
        sock.poll_connected(timeout)?;"""
new_sock = """        #[cfg(target_os = "horizon")]
        {
            sock.poll_connected(timeout)?;
            sock.set_nonblocking(false)?;
        }
        #[cfg(not(target_os = "horizon"))]
        {
            sock.set_nonblocking(false)?;
            sock.poll_connected(timeout)?;
        }"""
if old_sock in sock_text:
    sock_mod.write_text(sock_text.replace(old_sock, new_sock, 1))
PY
    if grep -A2 '^name = "libc"' "$std_dest/library/Cargo.lock" | grep -q '^source'; then
        echo "error: std would build against crates.io libc instead of $libc_patch" >&2
        exit 1
    fi
    echo "$std_want" > "$std_stamp"
fi
export __CARGO_TESTS_ONLY_SRC_ROOT="$std_dest/library"

export RUSTFLAGS="-Zunstable-options ${RUSTFLAGS:-} -C link-arg=-specs=$DEVKITPRO/libounce/switch.specs -C link-arg=-Wl,--wrap=threadCreate -C link-arg=-Wl,--wrap=fchmod -C link-arg=-Wl,--wrap=fcntl -C link-arg=-Wl,--wrap=rename -C link-arg=-Wl,--wrap=rmdir -C link-arg=-Wl,--wrap=_open_r -C link-arg=-Wl,--wrap=fsFsGetFileTimeStampRaw -C link-arg=-Wl,--wrap=fsFileWrite -C link-arg=-Wl,--wrap=fsFileSetSize -C link-arg=-Wl,--wrap=pthread_key_create -C link-arg=-Wl,--wrap=pthread_key_delete -C link-arg=-Wl,--wrap=pthread_getspecific -C link-arg=-Wl,--wrap=pthread_setspecific -C link-arg=-Wl,--start-group -C link-arg=-lvulkan -C link-arg=-lstdc++ -C link-arg=-lnx -C link-arg=-lsysbase -C link-arg=-lc -C link-arg=-lm -C link-arg=-lgcc -C link-arg=-Wl,--end-group"

# Native dependencies (notably ring) are built by cc-rs. Point them at the
# same bare-metal AArch64 toolchain as libounce instead of the host compiler.
export CC_aarch64_switch_horizon="$DEVKITPRO/devkitA64/bin/aarch64-none-elf-gcc"
export CXX_aarch64_switch_horizon="$DEVKITPRO/devkitA64/bin/aarch64-none-elf-g++"
export AR_aarch64_switch_horizon="$DEVKITPRO/devkitA64/bin/aarch64-none-elf-ar"
export CFLAGS_aarch64_switch_horizon="-mtp=soft -fPIE -D__SWITCH__ -D__SWITCH2__ -I$DEVKITPRO/libounce/include -I$DEVKITPRO/portlibs/switch2/include"

cargo +"$toolchain" build --release \
  -Zbuild-std=core,alloc,std,panic_abort \
  --target "$target" \
  -p horizon-client \
  --bin horizon-client \
  --no-default-features \
  --features switch2,controllers
