#!/usr/bin/env bash
# Skill Bridge 1.0 - copy selected local skills between Claude Code and Codex.
# Linux / Bash 4.4+. No sudo, Python, Node, or network access needed.
# Install: bash skill-bridge.sh --install
# Run: skillsync
# Docs checked 2026-10-02:
# https://learn.chatgpt.com/docs/build-skills
# https://code.claude.com/docs/en/skills

# Keep this check POSIX so `sh skill-bridge.sh` reaches the message.
if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
    printf 'This script needs Bash 4 or later. Run it with bash, not sh.\n' >&2
    exit 1
fi

set -Eeuo pipefail
shopt -s nullglob

SB_CLAUDE_ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
SB_CODEX_ROOT="$HOME/.agents/skills"
SB_CODEX_LEGACY="${CODEX_HOME:-$HOME/.codex}/skills"
SB_STATE_ROOT="${SKILL_BRIDGE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/skill-bridge}"
SB_MODE=menu
SB_PLAIN=0
SB_STAGE=''
SB_ACTIVE_DEST=''
SB_COMMITTED=0
SB_LOCKED=0
declare -a SB_SKILLS=() SB_LABELS=() SB_SELECTED=()
declare -A SB_VISITED=()

say() { printf '%s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
exists() { [[ -e "$1" || -L "$1" ]]; }
inside() { [[ "$1" == "$2" || "$1" == "$2/"* ]]; }

cleanup_stage() {
    [[ -n "$SB_STAGE" && -d "$SB_STAGE" ]] || return 0
    if exists "$SB_STAGE/previous" && (( ! SB_COMMITTED )); then
        if ! exists "$SB_ACTIVE_DEST"; then
            if ! mv -T -- "$SB_STAGE/previous" "$SB_ACTIVE_DEST"; then
                printf 'Restore the previous skill from: %s/previous\n' "$SB_STAGE" >&2
                SB_STAGE=''
                return 0
            fi
        else
            printf 'Previous skill retained for recovery: %s/previous\n' "$SB_STAGE" >&2
            SB_STAGE=''
            return 0
        fi
    fi
    rm -rf -- "$SB_STAGE"
    SB_STAGE=''
    SB_ACTIVE_DEST=''
    SB_COMMITTED=0
}
trap cleanup_stage EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

help_text() {
    cat <<'HELP'
Skill Bridge - Claude Code <-> Codex

INSTALL ONCE (no sudo):
  bash skill-bridge.sh --install       Detect Bash or Zsh from $SHELL
  bash skill-bridge.sh --install bash  Explicitly use ~/.bashrc
  bash skill-bridge.sh --install zsh   Use ${ZDOTDIR:-$HOME}/.zshrc
  Then open a new terminal and run: skillsync

USAGE:
  skillsync                       Open the menu
  skillsync --to-codex             Select Claude skills to copy to Codex
  skillsync --to-claude            Select Codex skills to copy to Claude
  skillsync --list                 List skills on both sides
  skillsync --paths                Show the folders in use
  skillsync --plain                Use numbered selection, even with fzf
  skillsync --project /path/repo   Use that project's skill folders
  skillsync --claude-dir /path    Override the Claude skills parent folder
  skillsync --codex-dir /path     Override Codex source AND destination
  skillsync --help

DEFAULT FOLDERS:
  Claude:       ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills
  Codex writes: $HOME/.agents/skills
  Codex reads:  the write folder AND ${CODEX_HOME:-$HOME/.codex}/skills
  Backups:      ${XDG_STATE_HOME:-$HOME/.local/state}/skill-bridge/backups
  Override the state folder with SKILL_BRIDGE_STATE_DIR if needed.

For an older Codex installation, explicitly choose its directory:
  skillsync --codex-dir "$HOME/.codex/skills"

--project uses .claude/skills and .agents/skills inside the given folder,
and also reads its .codex/skills. Directory flags apply left to right.
Hidden folders (including .system and .git) are excluded from discovery.
Personal/project skills are scanned; plugin caches and old .claude/commands
files are not scanned automatically. Point a directory flag at a plugin's
skills folder if you intentionally want to copy its standalone skills.

SELECTION:
  Without fzf: enter numbers, comma/space lists, ranges, or "all".
               Example: 1 3 5-7       Enter or q cancels.
  With fzf:    type to filter, Tab to select several, Enter to accept;
               Ctrl-A selects all matches, Ctrl-D deselects, Esc cancels.
               fzf is optional; nothing is installed automatically.

BEHAVIOR:
  Copies the WHOLE skill folder, including scripts and supporting files.
  The source stays in place. This is a manual copy, not automatic syncing.
  Existing destinations: skip (default) or replace after a backup.
  Replacements do not merge folders, so removed files do not linger.
  Backups stay outside the scanned skill folders. Their paths are printed.
  A directory symlink used as the source is copied as a real directory.
  Symlinks inside a skill are preserved; external relative links may need
  adjustment after copying. Internal symlinks are reported before transfer.

  This transfers files; it does not translate tool names, Claude-specific
  variables/hooks/frontmatter, or install a plugin's MCP dependencies.
  Skills relying on those features need adaptation in the other tool.
  If a skill does not appear, check its SKILL.md name/description and open
  a new session in the destination tool. Different folders declaring the
  same skill name can still cause duplicates; review --list.

UNINSTALL:
  Remove ~/.local/bin/skill-bridge and the "alias skillsync=..." line added
  to your shell rc file. Skills and backups are kept.
HELP
}

install_script() {
    local target_shell="${1:-${SHELL##*/}}" rc_file alias_line self_path binary stamp
    case "$target_shell" in
        bash) rc_file="$HOME/.bashrc" ;;
        zsh) rc_file="${ZDOTDIR:-$HOME}/.zshrc" ;;
        *) fail 'Use --install bash or --install zsh to choose your shell.' ;;
    esac
    alias_line="alias skillsync='\"\$HOME/.local/bin/skill-bridge\"'"
    self_path=$(realpath -e -- "${BASH_SOURCE[0]}")
    binary="$HOME/.local/bin/skill-bridge"
    mkdir -p -- "$HOME/.local/bin" "$(dirname -- "$rc_file")" "$SB_STATE_ROOT/setup-backups"
    stamp=$(date -u +%Y%m%dT%H%M%S)-$$
    if [[ -e "$rc_file" ]] && grep -Eq '^[[:space:]]*(alias[[:space:]]+skillsync=|skillsync[[:space:]]*\(\))' "$rc_file" &&
       ! grep -Fxq -- "$alias_line" "$rc_file"; then
        fail "An existing skillsync alias/function is in $rc_file. Rename it first."
    fi
    if [[ "$self_path" != "$(realpath -m -- "$binary")" ]]; then
        if exists "$binary"; then
            [[ ! -d "$binary" ]] || fail "$binary is a directory."
            cp -a -- "$binary" "$SB_STATE_ROOT/setup-backups/skill-bridge-$stamp"
        fi
        local temp_binary
        temp_binary=$(mktemp -- "$HOME/.local/bin/.skill-bridge-install.XXXXXX")
        if ! install -m 0755 -- "$self_path" "$temp_binary" || ! mv -T -- "$temp_binary" "$binary"; then
            rm -f -- "$temp_binary"
            fail 'Could not install the command.'
        fi
    fi
    if [[ ! -e "$rc_file" ]] || ! grep -Fxq -- "$alias_line" "$rc_file"; then
        if exists "$rc_file"; then
            cp -pL -- "$rc_file" "$SB_STATE_ROOT/setup-backups/$(basename -- "$rc_file")-$stamp"
        fi
        printf '\n# Skill Bridge: copy selected Claude Code / Codex skills\n%s\n' "$alias_line" >> "$rc_file"
    fi
    printf 'Installed: %s\nAlias: skillsync\n\n' "$binary"
    printf 'Open a new terminal, or run: source %q\nThen run: skillsync\n' "$rc_file"
}

require_value() { (( $# >= 2 )) && [[ -n "$2" ]] || fail "$1 requires a folder."; }
while (( $# )); do
    case "$1" in
        --help|-h) help_text; exit 0 ;;
        --install)
            shift
            (( $# <= 1 )) || fail 'Usage: --install [bash|zsh]'
            install_script "${1:-${SHELL##*/}}"
            exit 0 ;;
        --to-codex) SB_MODE=to-codex ;;
        --to-claude) SB_MODE=to-claude ;;
        --list) SB_MODE=list ;;
        --paths) SB_MODE=paths ;;
        --plain) SB_PLAIN=1 ;;
        --project)
            require_value "$@"
            [[ -d "$2" ]] || fail "Project folder does not exist: $2"
            SB_CLAUDE_ROOT="$2/.claude/skills"
            SB_CODEX_ROOT="$2/.agents/skills"
            SB_CODEX_LEGACY="$2/.codex/skills"
            shift ;;
        --claude-dir) require_value "$@"; SB_CLAUDE_ROOT="$2"; shift ;;
        --codex-dir) require_value "$@"; SB_CODEX_ROOT="$2"; SB_CODEX_LEGACY=''; shift ;;
        *) fail "Unknown option: $1 (use --help)" ;;
    esac
    shift
done

for sb_command in realpath cp mv mktemp find sort awk grep flock; do
    command -v "$sb_command" >/dev/null || fail "Missing command: $sb_command"
done
SB_CLAUDE_ROOT=$(realpath -m -- "$SB_CLAUDE_ROOT")
SB_CODEX_ROOT=$(realpath -m -- "$SB_CODEX_ROOT")
SB_STATE_ROOT=$(realpath -m -- "$SB_STATE_ROOT")
if [[ -n "$SB_CODEX_LEGACY" ]]; then
    SB_CODEX_LEGACY=$(realpath -m -- "$SB_CODEX_LEGACY")
fi

show_paths() {
    printf '\nClaude skills:       %s\nCodex copy target:   %s\n' "$SB_CLAUDE_ROOT" "$SB_CODEX_ROOT"
    if [[ -n "$SB_CODEX_LEGACY" && "$SB_CODEX_LEGACY" != "$SB_CODEX_ROOT" ]]; then
        printf 'Also read for Codex: %s\n' "$SB_CODEX_LEGACY"
    fi
    printf 'Backups:            %s/backups\n' "$SB_STATE_ROOT"
}

# Discover nested collections, but stop at each skill boundary. Canonical
# paths deduplicate linked copies and prevent symlink traversal loops.
scan_dir() {
    local root="$1" label="$2" depth="${3:-0}" child physical
    [[ -d "$root" ]] || return 0
    physical=$(realpath -e -- "$root") || return 0
    [[ -z "${SB_VISITED[$physical]+x}" ]] || return 0
    SB_VISITED["$physical"]=1
    if (( depth > 30 )); then
        printf 'Skipped deeply nested directory: %q\n' "$root" >&2
        return 0
    fi
    for child in "$root"/*; do
        [[ -d "$child" ]] || continue
        # Newlines/tabs would break terminal selection rows. Other spaces work.
        if [[ "$child" == *$'\n'* || "$child" == *$'\t'* || "$child" =~ [[:cntrl:]] ]]; then
            printf 'Skipped path with terminal control characters: %q\n' "$child" >&2
            continue
        fi
        if [[ -f "$child/SKILL.md" ]]; then
            physical=$(realpath -e -- "$child") || continue
            [[ -z "${SB_VISITED[$physical]+x}" ]] || continue
            SB_VISITED["$physical"]=1
            SB_SKILLS+=("$child")
            SB_LABELS+=("$label")
        else
            scan_dir "$child" "$label" "$((depth + 1))"
        fi
    done
}

discover() {
    SB_SKILLS=(); SB_LABELS=(); SB_SELECTED=(); SB_VISITED=()
    if [[ "$1" == claude ]]; then
        scan_dir "$SB_CLAUDE_ROOT" 'Claude'
    else
        scan_dir "$SB_CODEX_ROOT" 'Codex'
        if [[ -n "$SB_CODEX_LEGACY" && "$SB_CODEX_LEGACY" != "$SB_CODEX_ROOT" ]]; then
            scan_dir "$SB_CODEX_LEGACY" 'Codex legacy'
        fi
    fi
}

print_rows() {
    local i
    for i in "${!SB_SKILLS[@]}"; do
        printf '%3d  %-26s [%s] %s\n' "$((i + 1))" "${SB_SKILLS[i]##*/}" "${SB_LABELS[i]}" "${SB_SKILLS[i]}"
    done
}

list_skills() {
    local side
    for side in claude codex; do
        printf '\n%s skills\n' "${side^}"
        discover "$side"
        print_rows
        (( ${#SB_SKILLS[@]} )) || say '  No skill folders found.'
    done
}

choose_skills() {
    local answer token first last idx invalid picked row
    local -a tokens=()
    local -A chosen=()
    SB_SELECTED=()
    if (( ! SB_PLAIN )) && [[ -t 0 && -t 1 ]] && command -v fzf >/dev/null; then
        # Ignore user fzf overrides so selection IDs and keys stay predictable.
        picked=$(print_rows | FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE=/dev/null \
            fzf --multi --layout=reverse --height=80% --border \
                --prompt='Skills > ' --bind='ctrl-a:select-all,ctrl-d:deselect-all' \
                --header='Type to filter | Tab: select | Enter: accept | Esc: cancel') || return 1
        while IFS= read -r row; do
            read -r idx _ <<< "$row"
            [[ "$idx" =~ ^[0-9]+$ ]] || continue
            SB_SELECTED+=("$((10#$idx - 1))")
        done <<< "$picked"
        (( ${#SB_SELECTED[@]} > 0 ))
        return
    fi
    print_rows
    say 'Select: 1 3 5-7, or all. Enter/q cancels.'
    while true; do
        printf '> '
        IFS= read -r answer || return 1
        answer="${answer//,/ }"
        tokens=(); read -r -a tokens <<< "$answer"
        (( ${#tokens[@]} )) || return 1
        [[ "${answer,,}" != q ]] || return 1
        chosen=(); invalid=0
        if [[ "${answer,,}" == all ]]; then
            SB_SELECTED=("${!SB_SKILLS[@]}")
            return 0
        fi
        for token in "${tokens[@]}"; do
            if [[ "$token" =~ ^([0-9]{1,6})(-([0-9]{1,6}))?$ ]]; then
                first=$((10#${BASH_REMATCH[1]}))
                last=$((10#${BASH_REMATCH[3]:-${BASH_REMATCH[1]}}))
                if (( first < 1 || last < first || last > ${#SB_SKILLS[@]} )); then
                    invalid=1; break
                fi
                for ((idx=first; idx<=last; idx++)); do chosen[$((idx - 1))]=1; done
            else
                invalid=1; break
            fi
        done
        if (( invalid )); then say 'Invalid selection. Use the displayed numbers.'; continue; fi
        # Keep display order and remove repeated selections.
        SB_SELECTED=()
        for idx in "${!SB_SKILLS[@]}"; do
            [[ -z "${chosen[$idx]+x}" ]] || SB_SELECTED+=("$idx")
        done
        (( ${#SB_SELECTED[@]} > 0 )) && return 0
    done
}

confirm() {
    local answer
    printf '%s [y/N] ' "$1"
    IFS= read -r answer || return 1
    [[ "${answer,,}" == y || "${answer,,}" == yes ]]
}

acquire_lock() {
    (( SB_LOCKED )) && return 0
    mkdir -p -- "$SB_STATE_ROOT" || fail 'Could not create the state folder.'
    exec 9> "$SB_STATE_ROOT/transfer.lock" || fail 'Could not open the transfer lock.'
    flock -n 9 || fail 'Another Skill Bridge transfer is running.'
    SB_LOCKED=1
}

# Return 0=copied, 1=skipped, 2=failed, 3=quit remaining transfers.
copy_skill() {
    local source="$1" destination_root="$2" base destination physical_source physical_dest answer backup_dir link had_destination=0
    base="${source##*/}"
    destination="$destination_root/$base"
    [[ -f "$source/SKILL.md" ]] || { say "Failed: source disappeared: $source"; return 2; }
    physical_source=$(realpath -e -- "$source") || return 2
    physical_dest=$(realpath -m -- "$destination") || return 2
    if [[ "$physical_source" == "$physical_dest" ]]; then
        say "Skipped $base: both tools already point to the same folder."
        return 1
    fi
    if inside "$physical_dest" "$physical_source" || inside "$physical_source" "$physical_dest" ||
       inside "$SB_STATE_ROOT" "$physical_source" || inside "$SB_STATE_ROOT" "$physical_dest"; then
        say "Failed $base: source, destination, or backup folders overlap."
        return 2
    fi
    if exists "$destination"; then
        had_destination=1
        printf '\nAlready exists: %s\n' "$destination"
        printf '[s] Skip (default), [r] Replace with backup, [q] Quit: '
        IFS= read -r answer || return 3
        case "${answer,,}" in
            r|replace) ;;
            q|quit) return 3 ;;
            *) say "Skipped: $base"; return 1 ;;
        esac
    fi
    # Report symlinks without following them or executing any skill code.
    link=$(find -H "$source" -type l -print -quit) || return 2
    if [[ -n "$link" ]]; then
        printf 'Note: %s contains symlinks; their targets are preserved as written.\n' "$base"
    fi
    if ! mkdir -p -- "$destination_root"; then return 2; fi
    SB_STAGE=$(mktemp -d -- "$(dirname -- "$destination_root")/.skill-bridge-stage.XXXXXX") || return 2
    SB_ACTIVE_DEST="$destination"
    SB_COMMITTED=0
    # Dereference the source folder itself, but preserve symlinks inside it.
    if ! cp -a -- "$source/." "$SB_STAGE/new"; then
        say "Failed to stage: $base"; cleanup_stage; return 2
    fi
    if [[ ! -f "$SB_STAGE/new/SKILL.md" ]]; then
        say "Failed: staged $base has no readable SKILL.md."; cleanup_stage; return 2
    fi
    if exists "$destination"; then
        if (( ! had_destination )); then
            say "Failed $base: another process created the destination; no overwrite performed."
            cleanup_stage; return 2
        fi
        # Keep a durable backup BEFORE moving the old destination aside.
        if ! mkdir -p -- "$SB_STATE_ROOT/backups"; then cleanup_stage; return 2; fi
        backup_dir=$(mktemp -d -- "$SB_STATE_ROOT/backups/$(date -u +%Y%m%dT%H%M%S).XXXXXX") || { cleanup_stage; return 2; }
        if ! cp -a -- "$destination" "$backup_dir/$base"; then
            say "Backup failed; original kept at $destination"
            cleanup_stage; return 2
        fi
        printf 'Backup: %s/%s\n' "$backup_dir" "$base"
        if ! mv -T -- "$destination" "$SB_STAGE/previous"; then cleanup_stage; return 2; fi
    fi
    # -n prevents replacing a destination unexpectedly created by another tool.
    if ! mv -Tn -- "$SB_STAGE/new" "$destination" || exists "$SB_STAGE/new"; then
        say "Failed to install $base; restoring the previous destination where possible."
        cleanup_stage; return 2
    fi
    SB_COMMITTED=1
    cleanup_stage
    say "Copied: $destination"
    return 0
}

transfer() {
    local side="$1" destination_root idx code copied=0 skipped=0 failed=0 quit=0
    if [[ "$side" == claude ]]; then destination_root="$SB_CODEX_ROOT"; else destination_root="$SB_CLAUDE_ROOT"; fi
    discover "$side"
    if (( ! ${#SB_SKILLS[@]} )); then
        say "No $side skills found. Use --paths or override the skills folder."
        return 0
    fi
    printf '\nCopy from %s to: %s\n\n' "${side^}" "$destination_root"
    choose_skills || { say 'Cancelled.'; return 0; }
    say ''
    for idx in "${SB_SELECTED[@]}"; do
        printf '  %s -> %s/%s\n' "${SB_SKILLS[idx]}" "$destination_root" "${SB_SKILLS[idx]##*/}"
        if [[ "$side" == claude && -n "$SB_CODEX_LEGACY" && "$SB_CODEX_LEGACY" != "$SB_CODEX_ROOT" ]] &&
           exists "$SB_CODEX_LEGACY/${SB_SKILLS[idx]##*/}"; then
            printf '  Also exists in %s. Use --codex-dir there if you want to update that copy.\n' "$SB_CODEX_LEGACY"
        fi
    done
    say 'Files are copied unchanged; tool-specific features may need adaptation.'
    confirm "Copy ${#SB_SELECTED[@]} selected skill(s)?" || { say 'Cancelled.'; return 0; }
    acquire_lock
    for idx in "${SB_SELECTED[@]}"; do
        if copy_skill "${SB_SKILLS[idx]}" "$destination_root"; then code=0; else code=$?; fi
        case "$code" in
            0) copied=$((copied + 1)) ;;
            1) skipped=$((skipped + 1)) ;;
            2) failed=$((failed + 1)) ;;
            3) quit=1; break ;;
            *) failed=$((failed + 1)) ;;
        esac
    done
    flock -u 9
    exec 9>&-
    SB_LOCKED=0
    printf '\nDone: %d copied, %d skipped, %d failed.\n' "$copied" "$skipped" "$failed"
    (( ! quit )) || say 'Stopped; remaining selections were not processed.'
    (( ! copied )) || say 'Open a new session in the destination tool if the skills do not appear.'
    (( failed == 0 ))
}

case "$SB_MODE" in
    list) list_skills ;;
    paths) show_paths ;;
    to-codex) transfer claude ;;
    to-claude) transfer codex ;;
    menu)
        show_paths
        while true; do
            cat <<'MENU'

Skill Bridge
  1) Claude Code -> Codex
  2) Codex -> Claude Code
  3) List skills on both sides
  4) Show folders
  q) Exit
MENU
            printf '> '
            IFS= read -r sb_choice || break
            case "$sb_choice" in
                1) transfer claude || true ;;
                2) transfer codex || true ;;
                3) list_skills ;;
                4) show_paths ;;
                q|Q|0|'') break ;;
                *) say 'Choose 1, 2, 3, 4, or q.' ;;
            esac
        done ;;
esac
