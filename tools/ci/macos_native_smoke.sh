#!/bin/bash

set -euo pipefail

usage() {
    printf 'usage: %s [--sa-path PATH] [--runtime-root PATH] [--demo-path PATH] [--evidence-path PATH]\n' "$0" >&2
}

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd -P)
sa_path="zig-out/bin/sa"
runtime_root=${SA_STATIC_ROOT:-zig-out}
demo_path="demos/rosetta/01_hello_world/main.sa"
evidence_path=${SA_NATIVE_SMOKE_EVIDENCE:-}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --sa-path)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            sa_path=$2
            shift 2
            ;;
        --runtime-root)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            runtime_root=$2
            shift 2
            ;;
        --demo-path)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            demo_path=$2
            shift 2
            ;;
        --evidence-path)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            evidence_path=$2
            shift 2
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

resolve_file() {
    base=$1
    input=$2
    case "$input" in
        /*) candidate=$input ;;
        *) candidate=$base/$input ;;
    esac
    if [ ! -f "$candidate" ]; then
        printf 'Required file is missing: %s\n' "$candidate" >&2
        return 1
    fi
    candidate_dir=$(CDPATH= cd -- "$(dirname "$candidate")" && pwd -P)
    printf '%s/%s\n' "$candidate_dir" "$(basename "$candidate")"
}

resolve_dir() {
    base=$1
    input=$2
    case "$input" in
        /*) candidate=$input ;;
        *) candidate=$base/$input ;;
    esac
    if [ ! -d "$candidate" ]; then
        printf 'Required directory is missing: %s\n' "$candidate" >&2
        return 1
    fi
    CDPATH= cd -- "$candidate" && pwd -P
}

capture_success() {
    action=$1
    shift
    if captured_output=$("$@" 2>&1); then
        return 0
    else
        status=$?
    fi
    printf '%s failed with exit code %s.\n%s\n' "$action" "$status" "$captured_output" >&2
    return "$status"
}

assert_macho() {
    artifact=$1
    expected_arch=$2
    description=$(/usr/bin/file -b "$artifact")
    case "$description" in
        *"Mach-O 64-bit executable"*) ;;
        *)
            printf 'Expected a Mach-O 64-bit executable at %s, got: %s\n' "$artifact" "$description" >&2
            return 1
            ;;
    esac
    artifact_arch=$(/usr/bin/lipo -archs "$artifact")
    if [ "$artifact_arch" != "$expected_arch" ]; then
        printf 'Mach-O architecture mismatch for %s: expected %s, got %s\n' "$artifact" "$expected_arch" "$artifact_arch" >&2
        return 1
    fi
}

source_sa=$(resolve_file "$repo_root" "$sa_path")
source_demo=$(resolve_file "$repo_root" "$demo_path")
runtime_root_path=$(resolve_dir "$repo_root" "$runtime_root")
runtime_archive=$(resolve_file "$runtime_root_path" "lib/libsa_std.a")
runtime_header=$(resolve_file "$runtime_root_path" "include/sa_std.h")
source_std_root=$(resolve_dir "$repo_root" "sa_std")

if ! /usr/bin/ar -t "$runtime_archive" >/dev/null; then
    printf 'Static runtime archive is unreadable: %s\n' "$runtime_archive" >&2
    exit 1
fi

temp_parent=${TMPDIR:-/tmp}
temp_parent=${temp_parent%/}
[ -n "$temp_parent" ] || temp_parent=/tmp
unicode_word=$(printf '\346\265\213\350\257\225')
temp_root=$(mktemp -d "$temp_parent/sa macOS smoke $unicode_word.XXXXXX")
installer_release_root=$(mktemp -d "$temp_parent/sa_installer_release.XXXXXX")
http_server_pid=

cleanup() {
    status=$?
    trap - EXIT HUP INT TERM
    CDPATH= cd -- "$repo_root" 2>/dev/null || true
    if [ -n "${http_server_pid:-}" ]; then
        kill "$http_server_pid" 2>/dev/null || true
        wait "$http_server_pid" 2>/dev/null || true
    fi
    if [ -n "${temp_root:-}" ] && [ -d "$temp_root" ]; then
        rm -rf -- "$temp_root"
    fi
    if [ -n "${installer_release_root:-}" ] && [ -d "$installer_release_root" ]; then
        rm -rf -- "$installer_release_root"
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

expected_arch=$(uname -m)
archive_payload_name="sa-macos-$expected_arch"
release_root="$temp_root/release payload"
bin_root="$release_root/bin"
std_root="$release_root/std"
sa="$bin_root/sa"
archive_payload_root="$temp_root/$archive_payload_name"
archive_path="$temp_root/$archive_payload_name.tar.gz"
archive_extract_root="$temp_root/archive extracted"
temp_demo="$temp_root/hello main.sa"
native_output="$temp_root/hello output"
wasm_output="$temp_root/hello output.wasm"
installer_root="$temp_root/installed via install.sh"
http_installer_root="$temp_root/installed via install.sh http"
http_port_file="$temp_root/release_http_port"
home_root="$temp_root/isolated home"
process_temp_root="$temp_root/isolated temp"
plugins_root="$temp_root/isolated plugins"
package_project_root="$temp_root/offline package project"
package_source_root="$package_project_root/github.com/example/pkg"
package_source="$package_source_root/index.sa"
package_main="$package_project_root/main.sa"
vendor_package="$package_project_root/sa_vendor/github.com/example/pkg/index.sa"
staged_std_probe_dir="$std_root/ci_smoke"
staged_std_iface="$staged_std_probe_dir/staged_only.sai"

mkdir -p "$bin_root" "$std_root" "$home_root" "$process_temp_root" "$plugins_root" "$package_source_root" "$staged_std_probe_dir"
cp "$source_sa" "$sa"
chmod +x "$sa"
cp -R "$source_std_root/." "$std_root/"
cp "$runtime_archive" "$std_root/libsa_std.a"
cp "$runtime_header" "$std_root/sa_std.h"

printf '%s\n' '@pkg_value() -> i32:' 'return 42' > "$package_source"
printf '%s\n' '@import "github.com/example/pkg"' '@main() -> i32:' 'return 0' > "$package_main"
printf '%s\n' '// This file exists only in the staged SA_STD_DIR.' > "$staged_std_iface"
{
    printf '%s\n' '@import "sa_std/ci_smoke/staged_only.sai"'
    cat "$source_demo"
} > "$temp_demo"

mkdir -p "$archive_payload_root" "$archive_extract_root"
cp -R "$release_root/." "$archive_payload_root/"
(cd "$temp_root" && tar -czf "$archive_path" "$archive_payload_name")
if [ ! -s "$archive_path" ]; then
    printf 'Native archive was not created: %s\n' "$archive_path" >&2
    exit 1
fi
tar -tzf "$archive_path" >/dev/null
cp "$archive_path" "$installer_release_root/$archive_payload_name.tar.gz"
(cd "$installer_release_root" && shasum -a 256 "$archive_payload_name.tar.gz" > "$archive_payload_name.tar.gz.sha256")
tar -xzf "$archive_path" -C "$archive_extract_root"
release_root="$archive_extract_root/$archive_payload_name"
bin_root="$release_root/bin"
std_root="$release_root/std"
sa="$bin_root/sa"
for required_path in "$sa" "$std_root/libsa_std.a" "$std_root/sa_std.h" "$std_root/io/print.sai"; do
    if [ ! -s "$required_path" ]; then
        printf 'Extracted native archive is missing %s\n' "$required_path" >&2
        exit 1
    fi
done
chmod +x "$sa"

export HOME="$home_root"
export USERPROFILE="$home_root"
export TMPDIR="$process_temp_root"
export TEMP="$process_temp_root"
export TMP="$process_temp_root"
export SA_PLUGINS_HOME="$plugins_root"
export SA_STD_DIR="$std_root"
unset SA_DAEMON_SOCKET SA_AGENT_ID SA_AGENT_GENERATION SA_PLUGINS_PATH SA_PLUGINS_WORKSPACE

cd "$package_project_root"
assert_macho "$sa" "$expected_arch"

capture_success "staged sa version" "$sa" version
if ! printf '%s\n' "$captured_output" | grep -Eq '^sa[[:space:]]+[^[:space:]]+$'; then
    printf 'Unexpected version output: %s\n' "$captured_output" >&2
    exit 1
fi
staged_version_output=$captured_output

capture_success "staged sa help" "$sa" help
if ! printf '%s\n' "$captured_output" | grep -Eq 'usage:[[:space:]]+sa'; then
    printf 'Unexpected help output: %s\n' "$captured_output" >&2
    exit 1
fi

capture_success "staged sa check" "$sa" check "$temp_demo"
capture_success "staged sa build-exe" "$sa" build-exe "$temp_demo" -o "$native_output"
if [ ! -x "$native_output" ]; then
    printf 'sa build-exe did not create an executable at %s\n' "$native_output" >&2
    exit 1
fi
assert_macho "$native_output" "$expected_arch"
capture_success "generated Hello executable" "$native_output"
if [ "$captured_output" != "hello, saasm" ]; then
    printf 'Unexpected generated program output: %s\n' "$captured_output" >&2
    exit 1
fi

capture_success "staged sa build-wasm" "$sa" build-wasm "$temp_demo" -o "$wasm_output" --target wasm32
if [ ! -s "$wasm_output" ]; then
    printf 'sa build-wasm did not create %s\n' "$wasm_output" >&2
    exit 1
fi
wasm_magic=$(/usr/bin/od -An -tx1 -N4 "$wasm_output" | /usr/bin/tr -d '[:space:]')
if [ "$wasm_magic" != "0061736d" ]; then
    printf 'Unexpected WebAssembly magic: %s\n' "$wasm_magic" >&2
    exit 1
fi

capture_success "offline package install" "$sa" pkg install --offline github.com/example/pkg
if [ ! -f "$vendor_package" ]; then
    printf 'Offline package install did not create %s\n' "$vendor_package" >&2
    exit 1
fi
rm -rf -- "$package_project_root/github.com"
capture_success "offline package resolve" "$sa" check "$package_main" --offline

if missing_output=$("$sa" pkg install --offline github.com/example/missing --json 2>&1); then
    missing_status=0
else
    missing_status=$?
fi
if [ "$missing_status" -ne 1 ]; then
    printf 'Missing offline package returned %s, expected 1.\n%s\n' "$missing_status" "$missing_output" >&2
    exit 1
fi
if ! printf '%s\n' "$missing_output" | grep -Eq '"name"[[:space:]]*:[[:space:]]*"SourceNotFound"'; then
    printf 'Missing offline package did not report SourceNotFound.\n%s\n' "$missing_output" >&2
    exit 1
fi

capture_success "install.sh local release archive" env \
    SA_RELEASE_URL="file://$installer_release_root" \
    HOME="$home_root" \
    USERPROFILE="$home_root" \
    TMPDIR="$process_temp_root" \
    TEMP="$process_temp_root" \
    TMP="$process_temp_root" \
    sh "$repo_root/tools/install.sh" --dir "$installer_root" --no-shell
installed_sa="$installer_root/bin/sa"
installed_std_root="$installer_root/std"
for required_path in "$installed_sa" "$installed_std_root/libsa_std.a" "$installed_std_root/sa_std.h" "$installed_std_root/io/print.sai"; do
    if [ ! -s "$required_path" ]; then
        printf 'install.sh local release install is missing %s\n' "$required_path" >&2
        exit 1
    fi
done
if [ ! -L "$installer_root/bin/saasm" ]; then
    printf 'install.sh local release install did not create the saasm symlink\n' >&2
    exit 1
fi
capture_success "installed sa version" "$installed_sa" version
if ! printf '%s\n' "$captured_output" | grep -Eq '^sa[[:space:]]+[^[:space:]]+$'; then
    printf 'Unexpected installed version output: %s\n' "$captured_output" >&2
    exit 1
fi
installed_version_output=$captured_output
capture_success "installed sa check" env SA_STD_DIR="$installed_std_root" "$installed_sa" check "$temp_demo"

rm -f "$http_port_file"
python3 - "$installer_release_root" "$http_port_file" <<'PY' &
import http.server
import socketserver
import sys

root = sys.argv[1]
port_file = sys.argv[2]

class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=root, **kwargs)

    def log_message(self, format, *args):
        pass

class Server(socketserver.TCPServer):
    allow_reuse_address = True

with Server(("127.0.0.1", 0), Handler) as httpd:
    with open(port_file, "w", encoding="ascii") as handle:
        handle.write(str(httpd.server_address[1]))
    httpd.serve_forever()
PY
http_server_pid=$!
attempt=0
while [ "$attempt" -lt 100 ] && [ ! -s "$http_port_file" ]; do
    if ! kill -0 "$http_server_pid" 2>/dev/null; then
        printf 'release HTTP server exited before writing its port\n' >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep 0.1
done
if [ ! -s "$http_port_file" ]; then
    printf 'release HTTP server did not report a port\n' >&2
    exit 1
fi
release_http_url="http://127.0.0.1:$(cat "$http_port_file")"
capture_success "install.sh HTTP release archive" env \
    SA_RELEASE_URL="$release_http_url" \
    HOME="$home_root" \
    USERPROFILE="$home_root" \
    TMPDIR="$process_temp_root" \
    TEMP="$process_temp_root" \
    TMP="$process_temp_root" \
    sh "$repo_root/tools/install.sh" --dir "$http_installer_root" --no-shell
http_installed_sa="$http_installer_root/bin/sa"
http_installed_std_root="$http_installer_root/std"
for required_path in "$http_installed_sa" "$http_installed_std_root/libsa_std.a" "$http_installed_std_root/sa_std.h" "$http_installed_std_root/io/print.sai"; do
    if [ ! -s "$required_path" ]; then
        printf 'install.sh HTTP release install is missing %s\n' "$required_path" >&2
        exit 1
    fi
done
capture_success "HTTP installed sa version" "$http_installed_sa" version
if ! printf '%s\n' "$captured_output" | grep -Eq '^sa[[:space:]]+[^[:space:]]+$'; then
    printf 'Unexpected HTTP installed version output: %s\n' "$captured_output" >&2
    exit 1
fi
http_installed_version_output=$captured_output
capture_success "HTTP installed sa check" env SA_STD_DIR="$http_installed_std_root" "$http_installed_sa" check "$temp_demo"

if [ -n "$evidence_path" ]; then
    evidence_dir=$(dirname "$evidence_path")
    mkdir -p "$evidence_dir"
    {
        printf '{\n'
        printf '  "platform": "macos",\n'
        printf '  "arch": "%s",\n' "$expected_arch"
        printf '  "zig_target": "%s",\n' "${ZIG_TARGET:-}"
        printf '  "archive": "%s.tar.gz",\n' "$archive_payload_name"
        printf '  "github_sha": "%s",\n' "${GITHUB_SHA:-}"
        printf '  "github_run_id": "%s",\n' "${GITHUB_RUN_ID:-}"
        printf '  "github_run_attempt": "%s",\n' "${GITHUB_RUN_ATTEMPT:-}"
        printf '  "installer_transports": ["file", "http"],\n'
        printf '  "staged_version": "%s",\n' "$staged_version_output"
        printf '  "installed_version": "%s",\n' "$installed_version_output"
        printf '  "http_installed_version": "%s",\n' "$http_installed_version_output"
        printf '  "wasm_magic": "%s",\n' "$wasm_magic"
        printf '  "native_smoke": "passed"\n'
        printf '}\n'
    } > "$evidence_path"
fi

printf 'macOS native compiler smoke passed.\n'
