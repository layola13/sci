#!/bin/sh
# SA (safe asm) — Remote Installer
#
# Interactive installer that lets you choose:
#   1) SA compiler only
#   2) SA compiler + plugins
#   3) Specific plugins only
#
# Each plugin lives at github.com/layola13/sa_plugin_<name>
# and is fetched from its own releases.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/layola13/sci/main/tools/install_remote.sh | sh
#   sh install_remote.sh [options]
#
# Options:
#   -h, --help             Show help
#   --version <tag>        SA compiler version (e.g. 0.0.3.3)
#   --dir <path>           Installation directory (default: ~/.sa)
#   --no-shell             Skip shell profile modification
#   --no-interactive       Skip interactive menu, install SA compiler only
#   --plugins <list>       Comma-separated plugin names (e.g. sla,sax,db)
#   --all-plugins          Install all available plugins

set -eu

# ── Configuration ───────────────────────────────────────────────────────────

GITHUB_ORG="layola13"
SA_REPO="sci"
SA_GITHUB_API="https://api.github.com/repos/${GITHUB_ORG}/${SA_REPO}/releases/latest"
SA_GITHUB_DOWNLOAD="https://github.com/${GITHUB_ORG}/${SA_REPO}/releases/download"

# Plugin registry: name|description|category
# Each plugin repo is github.com/layola13/sa_plugin_<name>
PLUGIN_REGISTRY='
sla|Sla high-level frontend (Rust-style syntax → SA)|Frontend
ts|TypeScript → SA compiler|Frontend
deno|Deno API native subset|Frontend
node|Node.js API facade|Frontend
bc2sa|LLVM bitcode → SA (experimental)|Frontend
sax|SA UI dialect (.sax → WASM + airlock)|Web
react|React-on-SAX components|Web
mui|Material UI component library|Web
vite|Dev server + .sax hot reload|Web
wgpu|Browser WebGPU sidecar|Web
3dengines|3D engine stack (Bevy alignment)|Web
http_server|HTTP server|Backend
http_client|HTTP client|Backend
db|Native columnar database|Backend
dbnet|Database network layer|Backend
matmul|Optimized GEMM matrix multiplication|Compute
vm|Dynamic VM interpreter|System
pkg|Zero-trust package manager|Platform
'

# ── Colors ──────────────────────────────────────────────────────────────────

setup_colors() {
    if [ -t 1 ]; then
        RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
        BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
        BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
    else
        RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''
        BOLD=''; DIM=''; RESET=''
    fi
}

info()    { printf "${BLUE}[i]${RESET} %s\n" "$1"; }
step()    { printf "${CYAN}[>]${RESET} %s\n" "$1"; }
success() { printf "${GREEN}[✓]${RESET} %s\n" "$1"; }
warn()    { printf "${YELLOW}[!]${RESET} %s\n" "$1"; }
error()   { printf "${RED}[✗] Error:${RESET} %s\n" "$1" >&2; exit 1; }

print_header() {
    printf "${MAGENTA}${BOLD}"
    printf "   _____         \n"
    printf "  / ___/ ____ _  \n"
    printf "  \\__ \\ / __ \`/  \n"
    printf " ___/ // /_/ /   \n"
    printf "/____/ \\__,_/    ${CYAN}SA Installer${RESET}\n"
    printf "                 safe asm — Linear Ownership & Zero-Trust\n\n"
}

# ── Platform Detection ──────────────────────────────────────────────────────

detect_platform() {
    OS_NAME="$(uname -s)"
    ARCH_NAME="$(uname -m)"

    case "$OS_NAME" in
        Linux)  OS="linux"  ;;
        Darwin) OS="darwin" ;;
        *) error "Unsupported OS: $OS_NAME (supported: Linux, macOS)" ;;
    esac

    case "$ARCH_NAME" in
        x86_64|amd64)   ARCH="x86_64"  ;;
        arm64|aarch64)  ARCH="aarch64" ;;
        *) error "Unsupported architecture: $ARCH_NAME (supported: x86_64, aarch64)" ;;
    esac
}

# ── Download Helpers ────────────────────────────────────────────────────────

detect_downloader() {
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget"
    else
        error "Neither 'curl' nor 'wget' found. Please install one."
    fi
}

download() {
    _url="$1"; _out="$2"
    if [ "$DOWNLOADER" = "curl" ]; then
        curl -fsSL --connect-timeout 15 "$_url" -o "$_out"
    else
        wget -qO "$_out" --timeout=15 "$_url"
    fi
}

download_stdout() {
    _url="$1"
    if [ "$DOWNLOADER" = "curl" ]; then
        curl -fsSL --connect-timeout 15 "$_url"
    else
        wget -qO- --timeout=15 "$_url"
    fi
}

# ── Version Resolution ──────────────────────────────────────────────────────

resolve_latest_tag() {
    _api_url="$1"
    RESPONSE="$(download_stdout "$_api_url" 2>/dev/null)" || return 1
    printf '%s' "$RESPONSE" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
}

# ── Checksum Verification ───────────────────────────────────────────────────

verify_checksum() {
    _file="$1"; _sums_file="$2"; _target_name="$3"

    EXPECTED_SHA="$(grep "$_target_name" "$_sums_file" | awk '{print $1}')"
    if [ -z "$EXPECTED_SHA" ]; then
        warn "No checksum entry for $_target_name — skipping."
        return 0
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        ACTUAL_SHA="$(sha256sum "$_file" | awk '{print $1}')"
    elif command -v shasum >/dev/null 2>&1; then
        ACTUAL_SHA="$(shasum -a 256 "$_file" | awk '{print $1}')"
    else
        warn "No SHA-256 tool available — skipping."
        return 0
    fi

    if [ "$ACTUAL_SHA" = "$EXPECTED_SHA" ]; then
        success "Checksum OK."
    else
        error "Checksum mismatch for $_target_name!\n  expected: $EXPECTED_SHA\n  actual:   $ACTUAL_SHA"
    fi
}

# ── Interactive Menu ────────────────────────────────────────────────────────

show_install_menu() {
    printf "${BOLD}What would you like to install?${RESET}\n\n"
    printf "  ${CYAN}1)${RESET} SA compiler only\n"
    printf "  ${CYAN}2)${RESET} SA compiler + select plugins\n"
    printf "  ${CYAN}3)${RESET} SA compiler + all plugins\n"
    printf "  ${CYAN}4)${RESET} Plugins only (SA already installed)\n"
    printf "\n"
    printf "  ${DIM}Enter choice [1-4, default=1]:${RESET} "
    read -r MENU_CHOICE </dev/tty || MENU_CHOICE="1"
    MENU_CHOICE="${MENU_CHOICE:-1}"
}

show_plugin_menu() {
    printf "\n${BOLD}Available plugins:${RESET}\n\n"

    _idx=0
    _last_cat=""
    printf '%s\n' "$PLUGIN_REGISTRY" | while IFS='|' read -r _name _desc _cat; do
        [ -z "$_name" ] && continue
        _idx=$((_idx + 1))
        if [ "$_cat" != "$_last_cat" ]; then
            printf "\n  ${BOLD}── %s ──${RESET}\n" "$_cat"
            _last_cat="$_cat"
        fi
        printf "  ${CYAN}%2d)${RESET} %-14s %s\n" "$_idx" "$_name" "${DIM}${_desc}${RESET}"
    done

    printf "\n  ${DIM}Enter plugin numbers separated by spaces (e.g. 1 3 5):${RESET} "
    read -r PLUGIN_CHOICES </dev/tty || PLUGIN_CHOICES=""
}

get_plugin_names_by_indices() {
    _indices="$1"
    _result=""
    _idx=0

    printf '%s\n' "$PLUGIN_REGISTRY" | while IFS='|' read -r _name _desc _cat; do
        [ -z "$_name" ] && continue
        _idx=$((_idx + 1))
        for _i in $_indices; do
            if [ "$_i" = "$_idx" ]; then
                printf '%s\n' "$_name"
            fi
        done
    done
}

get_all_plugin_names() {
    printf '%s\n' "$PLUGIN_REGISTRY" | while IFS='|' read -r _name _desc _cat; do
        [ -z "$_name" ] && continue
        printf '%s\n' "$_name"
    done
}

# ── Install SA Compiler ─────────────────────────────────────────────────────

install_sa_compiler() {
    _install_dir="$1"
    _version="$2"
    _bin_dir="$_install_dir/bin"

    mkdir -p "$_bin_dir"

    # Resolve version
    if [ -n "$_version" ]; then
        TAG="$_version"
        info "Pinned version: ${BOLD}${TAG}${RESET}"
    else
        step "Querying latest SA release..."
        TAG="$(resolve_latest_tag "$SA_GITHUB_API")" || \
            error "Failed to query GitHub API. Use --version to specify."
        [ -z "$TAG" ] && error "Could not determine latest SA version."
        info "Latest version: ${BOLD}${TAG}${RESET}"
    fi

    TARBALL_NAME="sa-${OS}-${ARCH}.tar.gz"
    DOWNLOAD_URL="${SA_GITHUB_DOWNLOAD}/${TAG}/${TARBALL_NAME}"
    CHECKSUM_URL="${SA_GITHUB_DOWNLOAD}/${TAG}/sha256sums.txt"

    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_DIR"' EXIT

    step "Downloading SA compiler (${TARBALL_NAME})..."
    if ! download "$DOWNLOAD_URL" "$TMP_DIR/$TARBALL_NAME"; then
        error "Download failed: $DOWNLOAD_URL\nNo prebuilt binary for ${OS}-${ARCH}?"
    fi
    success "Downloaded."

    # Checksum
    if download "$CHECKSUM_URL" "$TMP_DIR/sha256sums.txt" 2>/dev/null; then
        verify_checksum "$TMP_DIR/$TARBALL_NAME" "$TMP_DIR/sha256sums.txt" "$TARBALL_NAME"
    else
        warn "sha256sums.txt not available — skipping verification."
    fi

    # Extract
    step "Extracting..."
    tar -xzf "$TMP_DIR/$TARBALL_NAME" -C "$TMP_DIR"

    # Find and install binary
    if [ -f "$TMP_DIR/bin/sa" ]; then
        cp -f "$TMP_DIR/bin/sa" "$_bin_dir/sa"
    elif [ -f "$TMP_DIR/sa" ]; then
        cp -f "$TMP_DIR/sa" "$_bin_dir/sa"
    else
        FOUND="$(find "$TMP_DIR" -name "sa" -type f | head -1)"
        [ -n "$FOUND" ] && cp -f "$FOUND" "$_bin_dir/sa" || \
            error "Could not locate 'sa' binary in archive."
    fi
    chmod +x "$_bin_dir/sa"

    # Std library
    STD_SRC="$(find "$TMP_DIR" -type d -name "sa_std" | head -1)"
    if [ -n "$STD_SRC" ]; then
        mkdir -p "$_install_dir/std"
        cp -rf "$STD_SRC"/* "$_install_dir/std/"
    fi

    rm -rf "$TMP_DIR"
    trap - EXIT

    success "SA compiler ${TAG} installed."
}

# ── Install a Plugin ────────────────────────────────────────────────────────

install_plugin() {
    _plugin_name="$1"
    _install_dir="$2"
    _plugins_dir="$_install_dir/plugins"

    PLUGIN_REPO="sa_plugin_${_plugin_name}"
    PLUGIN_CLONE_URL="https://github.com/${GITHUB_ORG}/${PLUGIN_REPO}.git"
    PLUGIN_API="https://api.github.com/repos/${GITHUB_ORG}/${PLUGIN_REPO}/releases/latest"
    PLUGIN_DOWNLOAD_BASE="https://github.com/${GITHUB_ORG}/${PLUGIN_REPO}/releases/download"

    step "Installing plugin: ${BOLD}${_plugin_name}${RESET}"

    # Check if remote repo exists
    REPO_CHECK_URL="https://api.github.com/repos/${GITHUB_ORG}/${PLUGIN_REPO}"
    REPO_INFO="$(download_stdout "$REPO_CHECK_URL" 2>/dev/null)" || REPO_INFO=""
    if [ -z "$REPO_INFO" ] || printf '%s' "$REPO_INFO" | grep -q '"Not Found"'; then
        warn "  Repository ${GITHUB_ORG}/${PLUGIN_REPO} does not exist — skipping."
        return 0
    fi

    # Get latest git commit info (default branch)
    GIT_LATEST_SHA="$(printf '%s' "$REPO_INFO" | grep '"default_branch"' | head -1 | sed 's/.*"default_branch"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
    GIT_DEFAULT_BRANCH="${GIT_LATEST_SHA:-main}"

    # Check if there's a release
    PTAG="$(resolve_latest_tag "$PLUGIN_API" 2>/dev/null)" || PTAG=""
    HAS_RELEASE=0
    HAS_BINARY=0

    if [ -n "$PTAG" ]; then
        HAS_RELEASE=1
        PLUGIN_TARBALL="sa_plugin_${_plugin_name}-${OS}-${ARCH}.tar.gz"
        PLUGIN_URL="${PLUGIN_DOWNLOAD_BASE}/${PTAG}/${PLUGIN_TARBALL}"
        # Check if binary asset exists (HEAD request)
        if [ "$DOWNLOADER" = "curl" ]; then
            HTTP_CODE="$(curl -sL -o /dev/null -w '%{http_code}' --connect-timeout 10 "$PLUGIN_URL")"
            [ "$HTTP_CODE" = "200" ] && HAS_BINARY=1
        else
            download "$PLUGIN_URL" "/dev/null" 2>/dev/null && HAS_BINARY=1
        fi
    fi

    # Get latest commit date on default branch to compare with release
    if [ "$HAS_RELEASE" = "1" ]; then
        COMMITS_API="https://api.github.com/repos/${GITHUB_ORG}/${PLUGIN_REPO}/commits/${GIT_DEFAULT_BRANCH}"
        COMMIT_INFO="$(download_stdout "$COMMITS_API" 2>/dev/null)" || COMMIT_INFO=""
        COMMIT_DATE="$(printf '%s' "$COMMIT_INFO" | grep '"date"' | head -1 | sed 's/.*"date"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"

        RELEASE_API_FULL="$(download_stdout "$PLUGIN_API" 2>/dev/null)" || RELEASE_API_FULL=""
        RELEASE_DATE="$(printf '%s' "$RELEASE_API_FULL" | grep '"published_at"' | head -1 | sed 's/.*"published_at"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"

        RELEASE_IS_LATEST=1
        if [ -n "$COMMIT_DATE" ] && [ -n "$RELEASE_DATE" ]; then
            # Simple string comparison works for ISO 8601 dates
            if [ "$COMMIT_DATE" \> "$RELEASE_DATE" ]; then
                RELEASE_IS_LATEST=0
            fi
        fi
    fi

    # Decision logic
    USE_MODE=""  # "binary" or "dev"

    if [ "$HAS_BINARY" = "1" ] && [ "$RELEASE_IS_LATEST" = "1" ]; then
        # Release is up-to-date and has binary — use it
        USE_MODE="binary"
        info "  Release ${PTAG} is up-to-date, using prebuilt binary."

    elif [ "$HAS_BINARY" = "1" ] && [ "$RELEASE_IS_LATEST" = "0" ]; then
        # Release exists but repo has newer commits — ask user
        if [ -t 0 ]; then
            printf "\n"
            warn "  Plugin '${_plugin_name}' has newer commits than release ${PTAG}."
            printf "    ${CYAN}1)${RESET} Use prebuilt release ${PTAG}\n"
            printf "    ${CYAN}2)${RESET} Clone latest & build from source (--dev mode)\n"
            printf "    ${DIM}  Choice [1/2, default=2]:${RESET} "
            read -r _pchoice </dev/tty || _pchoice="2"
            _pchoice="${_pchoice:-2}"
            case "$_pchoice" in
                1) USE_MODE="binary" ;;
                *) USE_MODE="dev" ;;
            esac
        else
            # Non-interactive: prefer dev for latest
            USE_MODE="dev"
            info "  Release ${PTAG} is outdated, cloning latest (--dev)."
        fi

    else
        # No binary release at all — must clone
        if [ "$HAS_RELEASE" = "1" ]; then
            info "  Release ${PTAG} exists but no binary for ${OS}-${ARCH}."
        else
            info "  No release found."
        fi
        info "  Cloning and building from source (--dev mode)."
        USE_MODE="dev"
    fi

    # ── Binary install path ──
    if [ "$USE_MODE" = "binary" ]; then
        PTMP="$(mktemp -d)"
        step "  Downloading ${PLUGIN_TARBALL}..."
        if download "$PLUGIN_URL" "$PTMP/$PLUGIN_TARBALL"; then
            mkdir -p "$_plugins_dir/${_plugin_name}"
            tar -xzf "$PTMP/$PLUGIN_TARBALL" -C "$_plugins_dir/${_plugin_name}" 2>/dev/null || \
                tar -xzf "$PTMP/$PLUGIN_TARBALL" -C "$PTMP" 2>/dev/null

            if [ ! -f "$_plugins_dir/${_plugin_name}/sap.json" ]; then
                PEXTRACTED="$(find "$PTMP" -name "sap.json" -type f | head -1)"
                if [ -n "$PEXTRACTED" ]; then
                    cp -rf "$(dirname "$PEXTRACTED")"/* "$_plugins_dir/${_plugin_name}/"
                fi
            fi
            rm -rf "$PTMP"
            success "  Plugin ${_plugin_name} (${PTAG}) installed from release."
            return 0
        fi
        rm -rf "$PTMP"
        warn "  Download failed, falling back to clone."
        USE_MODE="dev"
    fi

    # ── Dev install path (git clone + build) ──
    if [ "$USE_MODE" = "dev" ]; then
        if ! command -v git >/dev/null 2>&1; then
            error "git is required for --dev plugin install but not found in PATH."
        fi

        DEV_DIR="$_install_dir/src/${PLUGIN_REPO}"
        step "  Cloning ${GITHUB_ORG}/${PLUGIN_REPO}..."

        if [ -d "$DEV_DIR" ]; then
            # Already cloned — pull latest
            git -C "$DEV_DIR" pull --ff-only >/dev/null 2>&1 || \
                git -C "$DEV_DIR" fetch origin && git -C "$DEV_DIR" reset --hard "origin/${GIT_DEFAULT_BRANCH}" >/dev/null 2>&1
            info "  Updated existing clone."
        else
            mkdir -p "$_install_dir/src"
            git clone --depth 1 "$PLUGIN_CLONE_URL" "$DEV_DIR" >/dev/null 2>&1 || \
                error "  Failed to clone ${PLUGIN_CLONE_URL}"
        fi

        # Build if build.zig exists
        if [ -f "$DEV_DIR/build.zig" ]; then
            if ! command -v zig >/dev/null 2>&1; then
                warn "  zig not found — cannot build. Source cloned to: $DEV_DIR"
                info "  Build manually: cd $DEV_DIR && zig build -Doptimize=ReleaseFast"
                return 0
            fi
            step "  Building (zig build -Doptimize=ReleaseFast)..."
            if (cd "$DEV_DIR" && zig build -Doptimize=ReleaseFast) >/dev/null 2>&1; then
                success "  Build succeeded."
            else
                warn "  Build failed. Source remains at: $DEV_DIR"
                return 0
            fi
        fi

        # Register with sa plugin install --dev
        SA_BIN="$_install_dir/bin/sa"
        if [ -x "$SA_BIN" ]; then
            step "  Registering plugin (sa plugin install --dev)..."
            SA_PLUGIN_DEV=1 "$SA_BIN" plugin install --dev "$DEV_DIR" 2>/dev/null && \
                success "  Plugin ${_plugin_name} installed in dev mode." || \
                warn "  'sa plugin install --dev' failed. Plugin source at: $DEV_DIR"
        else
            # sa binary not available yet — just link manually
            mkdir -p "$_plugins_dir/${_plugin_name}"
            ln -sfn "$DEV_DIR" "$_plugins_dir/${_plugin_name}/src"
            info "  Source linked to $_plugins_dir/${_plugin_name}/src"
            info "  Run 'sa plugin install --dev $DEV_DIR' after SA is in PATH."
        fi
    fi
}

# ── Shell Profile ───────────────────────────────────────────────────────────

configure_shell() {
    _sa_dir="$1"
    _bin_dir="$_sa_dir/bin"

    SHELL_PROFILE=""
    CURRENT_SHELL="$(basename "${SHELL:-sh}")"

    case "$CURRENT_SHELL" in
        zsh)  SHELL_PROFILE="$HOME/.zshrc" ;;
        bash)
            if [ -f "$HOME/.bash_profile" ]; then
                SHELL_PROFILE="$HOME/.bash_profile"
            else
                SHELL_PROFILE="$HOME/.bashrc"
            fi
            ;;
        *) [ -f "$HOME/.profile" ] && SHELL_PROFILE="$HOME/.profile" ;;
    esac

    cat > "$_sa_dir/env" <<ENVEOF
#!/bin/sh
export SA_HOME="$_sa_dir"
export SA_PLUGINS_HOME="$_sa_dir/plugins"
export PATH="$_bin_dir:\$PATH"
ENVEOF

    if [ -n "$SHELL_PROFILE" ] && [ -f "$SHELL_PROFILE" ]; then
        if grep -qF "$_sa_dir/env" "$SHELL_PROFILE" 2>/dev/null; then
            info "Shell profile already configured."
        else
            step "Adding SA to $SHELL_PROFILE"
            printf '\n# SA Compiler & Plugins\n. "%s/env"\n' "$_sa_dir" >> "$SHELL_PROFILE"
        fi
    fi

    # Fish shell
    FISH_CONF="$HOME/.config/fish/config.fish"
    if [ -d "$HOME/.config/fish" ] || command -v fish >/dev/null 2>&1; then
        mkdir -p "$(dirname "$FISH_CONF")"
        if ! grep -qF "$_bin_dir" "$FISH_CONF" 2>/dev/null; then
            printf '\n# SA Compiler\nfish_add_path %s\nset -gx SA_HOME %s\nset -gx SA_PLUGINS_HOME %s/plugins\n' \
                "$_bin_dir" "$_sa_dir" "$_sa_dir" >> "$FISH_CONF"
        fi
    fi
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
    setup_colors

    # Argument parsing
    INSTALL_DIR=""
    VERSION=""
    NO_SHELL=0
    NO_INTERACTIVE=0
    PLUGIN_LIST=""
    ALL_PLUGINS=0

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                print_header
                printf "Install the SA compiler and/or plugins.\n\n"
                printf "${BOLD}USAGE${RESET}\n"
                printf "  curl -fsSL <url>/install_remote.sh | sh\n"
                printf "  sh install_remote.sh [options]\n\n"
                printf "${BOLD}OPTIONS${RESET}\n"
                printf "  %-26s %s\n" "-h, --help"        "Show this help"
                printf "  %-26s %s\n" "--version <tag>"   "SA compiler version (e.g. 0.0.3.3)"
                printf "  %-26s %s\n" "--dir <path>"      "Install directory (default: ~/.sa)"
                printf "  %-26s %s\n" "--no-shell"        "Skip shell profile modification"
                printf "  %-26s %s\n" "--no-interactive"  "Skip menu, install SA only"
                printf "  %-26s %s\n" "--plugins <list>"  "Comma-separated plugins (e.g. sla,sax,db)"
                printf "  %-26s %s\n" "--all-plugins"     "Install all available plugins"
                printf "\n${BOLD}AVAILABLE PLUGINS${RESET}\n"
                printf '%s\n' "$PLUGIN_REGISTRY" | while IFS='|' read -r _n _d _c; do
                    [ -z "$_n" ] && continue
                    printf "  %-14s %s\n" "$_n" "$_d"
                done
                printf "\n"
                exit 0
                ;;
            --version)
                [ $# -lt 2 ] && error "--version requires a tag"
                VERSION="$2"; shift 2 ;;
            --dir)
                [ $# -lt 2 ] && error "--dir requires a path"
                INSTALL_DIR="$2"; shift 2 ;;
            --no-shell)
                NO_SHELL=1; shift ;;
            --no-interactive)
                NO_INTERACTIVE=1; shift ;;
            --plugins)
                [ $# -lt 2 ] && error "--plugins requires a comma-separated list"
                PLUGIN_LIST="$2"; shift 2 ;;
            --all-plugins)
                ALL_PLUGINS=1; shift ;;
            *)
                error "Unknown option: $1 (use --help)" ;;
        esac
    done

    print_header
    detect_platform
    detect_downloader

    info "Platform: ${BOLD}${OS}-${ARCH}${RESET}"

    INSTALL_DIR="${INSTALL_DIR:-$HOME/.sa}"

    # Determine what to install
    INSTALL_SA=1
    SELECTED_PLUGINS=""

    if [ "$ALL_PLUGINS" = "1" ]; then
        SELECTED_PLUGINS="$(get_all_plugin_names)"
    elif [ -n "$PLUGIN_LIST" ]; then
        SELECTED_PLUGINS="$(printf '%s' "$PLUGIN_LIST" | tr ',' '\n')"
    elif [ "$NO_INTERACTIVE" = "0" ] && [ -t 0 ]; then
        show_install_menu

        case "$MENU_CHOICE" in
            1)
                INSTALL_SA=1
                ;;
            2)
                INSTALL_SA=1
                show_plugin_menu
                SELECTED_PLUGINS="$(get_plugin_names_by_indices "$PLUGIN_CHOICES")"
                ;;
            3)
                INSTALL_SA=1
                SELECTED_PLUGINS="$(get_all_plugin_names)"
                ;;
            4)
                INSTALL_SA=0
                show_plugin_menu
                SELECTED_PLUGINS="$(get_plugin_names_by_indices "$PLUGIN_CHOICES")"
                ;;
            *)
                error "Invalid choice: $MENU_CHOICE"
                ;;
        esac
    fi

    printf "\n"

    # Install SA compiler
    if [ "$INSTALL_SA" = "1" ]; then
        install_sa_compiler "$INSTALL_DIR" "$VERSION"
        printf "\n"
    fi

    # Install plugins
    if [ -n "$SELECTED_PLUGINS" ]; then
        printf "${BOLD}Installing plugins...${RESET}\n\n"
        mkdir -p "$INSTALL_DIR/plugins"

        printf '%s\n' "$SELECTED_PLUGINS" | while IFS= read -r _pname; do
            [ -z "$_pname" ] && continue
            install_plugin "$_pname" "$INSTALL_DIR"
        done
        printf "\n"
    fi

    # Shell configuration
    if [ "$NO_SHELL" = "0" ]; then
        configure_shell "$INSTALL_DIR"
    fi

    # Summary
    printf "\n"
    success "Installation complete!"
    printf "\n"
    printf "  ${BOLD}SA Home:${RESET}    %s\n" "$INSTALL_DIR"
    if [ "$INSTALL_SA" = "1" ]; then
        printf "  ${BOLD}Binary:${RESET}     %s/bin/sa\n" "$INSTALL_DIR"
    fi
    if [ -n "$SELECTED_PLUGINS" ]; then
        printf "  ${BOLD}Plugins:${RESET}    %s/plugins/\n" "$INSTALL_DIR"
    fi
    printf "\n"

    if ! command -v sa >/dev/null 2>&1; then
        info "Restart your shell or run:"
        printf "    ${BOLD}source %s/env${RESET}\n" "$INSTALL_DIR"
    fi
    printf "\n"
}

main "$@"