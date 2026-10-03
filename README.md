# Skill Bridge

Copy skills between **Claude Code** and **Codex** from your Linux terminal. Pick skills from a menu and copy whole skill folders in either direction. If a skill already exists, Skill Bridge backs it up before replacing it.

**Linux only** · **Bash 4.4+** · **No sudo** · **Works offline** · **fzf optional**

- [Quick start](#quick-start)
- [Requirements](#requirements)
- [Usage](#usage)
- [Command reference](#command-reference)
- [Common tasks](#common-tasks)
- [Where skills live](#where-skills-live)
- [How copying works](#how-copying-works)
- [Updating](#updating) · [Uninstalling](#uninstalling)
- [Troubleshooting](#troubleshooting)
- [Roadmap](#roadmap)

## What it does

- Copies skills **Claude Code → Codex** or **Codex → Claude Code**.
- Copies the **whole skill folder**: `SKILL.md` plus any scripts, references and templates in it.
- **Never changes the source.** If the destination already has the skill, it backs that copy up first and prints where the backup went.
- Works with your personal skills, with a project's skills, or with any folders you choose.

> [!NOTE]
> **Linux only.** Skill Bridge needs GNU coreutils (`realpath -m`, `mv -T`) and util-linux (`flock`). Ubuntu, Debian, Fedora, Arch, openSUSE and most other distros ship both. It does not run on macOS, BSD, or BusyBox systems such as Alpine.

## Quick start

```bash
git clone https://github.com/ShamilKaleel/Skill-Bridge.git ~/Skill-Bridge
cd ~/Skill-Bridge
bash skill-bridge.sh --install
```

Load the new command, then run it:

```bash
source ~/.bashrc      # Zsh: source ~/.zshrc
skillsync
```

The installer prints the exact `source` command for your shell. You can also just open a new terminal.

Don't delete the `~/Skill-Bridge` folder. You need it to [update](#updating) later.

### Try it without installing

From inside the cloned folder:

```bash
./skill-bridge.sh --list    # show the skills it can find
./skill-bridge.sh           # open the menu
```

### What `--install` does

1. Copies the script to `~/.local/bin/skill-bridge`.
2. Adds these two lines to `~/.bashrc` (or to `${ZDOTDIR:-$HOME}/.zshrc` for Zsh):
   ```bash
   # Skill Bridge: copy selected Claude Code / Codex skills
   alias skillsync='"$HOME/.local/bin/skill-bridge"'
   ```
3. Saves a backup of each file it changes in `~/.local/state/skill-bridge/setup-backups/`.

It works out which shell you use from `$SHELL`. To choose the shell yourself, run `bash skill-bridge.sh --install bash` or `--install zsh`. Running the installer again is safe because it never adds the alias twice. No sudo is needed.

## Requirements

| Requirement | Notes |
| --- | --- |
| Linux | Any mainstream distribution. |
| Bash 4.4 or later | Check with `bash --version`. |
| GNU coreutils and util-linux | Already installed on standard distributions. |
| `git` | Used to clone and update the tool. |
| Bash or Zsh | Needed for the `skillsync` shortcut. In other shells (such as fish), run `~/.local/bin/skill-bridge` directly. |
| `fzf` *(optional)* | Adds a searchable picker. Install with `sudo apt install fzf`, `sudo dnf install fzf` or `sudo pacman -S fzf`. |

You also need skill folders that each contain a `SKILL.md` file. Skill Bridge doesn't need an API key or an internet connection.

## Usage

### The menu

Run `skillsync`:

```text
Claude skills:       ~/.claude/skills
Codex copy target:   ~/.agents/skills
Also read for Codex: ~/.codex/skills
Backups:            ~/.local/state/skill-bridge/backups

Skill Bridge
  1) Claude Code -> Codex
  2) Codex -> Claude Code
  3) List skills on both sides
  4) Show folders
  q) Exit
>
```

The real output shows full paths. They are shortened to `~` here.

| Option | Action |
| --- | --- |
| `1` | Copy Claude Code skills to Codex. |
| `2` | Copy Codex skills to Claude Code. |
| `3` | List the skills on both sides. |
| `4` | Show the folders in use. |
| `q` or Enter | Exit. |

### Example: copy two Claude skills to Codex

```text
$ skillsync --to-codex --plain

Copy from Claude to: ~/.agents/skills

  1  commit-helper              [Claude] ~/.claude/skills/commit-helper
  2  pdf-tools                  [Claude] ~/.claude/skills/pdf-tools
  3  release-notes              [Claude] ~/.claude/skills/release-notes
Select: 1 3 5-7, or all. Enter/q cancels.
> 1 3

  ~/.claude/skills/commit-helper -> ~/.agents/skills/commit-helper
  ~/.claude/skills/release-notes -> ~/.agents/skills/release-notes
Files are copied unchanged; tool-specific features may need adaptation.
Copy 2 selected skill(s)? [y/N] y
Copied: ~/.agents/skills/commit-helper
Copied: ~/.agents/skills/release-notes

Done: 2 copied, 0 skipped, 0 failed.
Open a new session in the destination tool if the skills do not appear.
```

### Selecting skills by number

| Input | Selects |
| --- | --- |
| `2` | Skill 2 |
| `1 3 5` | Skills 1, 3 and 5 |
| `2-5` | Skills 2 through 5 |
| `1,3,5-7` | Skills 1, 3, 5, 6 and 7 |
| `all` | Every listed skill |
| Enter or `q` | Cancel |

Nothing is copied until you answer **`y`** to the `Copy N selected skill(s)?` prompt.

### Selecting skills with fzf

If `fzf` is installed, Skill Bridge opens a searchable picker in place of the numbered list:

| Key | Action |
| --- | --- |
| Type | Filter the list |
| Tab | Select or deselect a skill |
| Ctrl+A / Ctrl+D | Select all / deselect all |
| Enter | Accept the selection |
| Esc | Cancel |

To use the numbered list instead, add `--plain`.

### When a skill already exists

```text
Already exists: ~/.agents/skills/commit-helper
[s] Skip (default), [r] Replace with backup, [q] Quit: r
Backup: ~/.local/state/skill-bridge/backups/20261003T094220.kOeZ1o/commit-helper
Copied: ~/.agents/skills/commit-helper
```

| Answer | Result |
| --- | --- |
| `s` or Enter | Keep the existing skill and move on to the next one. |
| `r` | Back up the existing skill, then replace it. |
| `q` | Stop. The remaining selected skills are not copied. |

## Command reference

| Command | What it does |
| --- | --- |
| `skillsync` | Open the menu. |
| `skillsync --to-codex` | Select Claude Code skills to copy to Codex. |
| `skillsync --to-claude` | Select Codex skills to copy to Claude Code. |
| `skillsync --list` | List the skills on both sides. |
| `skillsync --paths` | Show the folders in use. |
| `skillsync --plain` | Use the numbered list even if `fzf` is installed. |
| `skillsync --project <dir>` | Use the skill folders of the project in `<dir>`. |
| `skillsync --claude-dir <dir>` | Use `<dir>` as the Claude skills folder. |
| `skillsync --codex-dir <dir>` | Use `<dir>` as the Codex skills folder, for both reading and writing. |
| `skillsync --help` | Show the built-in help. |
| `bash skill-bridge.sh --install [bash\|zsh]` | Install or update the `skillsync` command. |

You can combine flags, for example `skillsync --to-claude --plain`. Folder flags are applied left to right, so a later flag overrides an earlier one.

## Common tasks

**Copy every Claude skill to Codex.** Run `skillsync --to-codex` and type `all` (in fzf, press Ctrl+A).

**See what each tool has.** Run `skillsync --list`.

**Share a project's skills.** This uses `.claude/skills` and `.agents/skills` inside the project and also reads its `.codex/skills`:

```bash
skillsync --project ~/code/my-app
```

**Copy your personal Claude skills into a project's Codex folder:**

```bash
skillsync --to-codex --codex-dir ~/code/my-app/.agents/skills
```

**Copy to an older Codex install that only reads `~/.codex/skills`:**

```bash
skillsync --codex-dir ~/.codex/skills
```

**Use custom folders.** Give each flag the parent folder that holds the skill folders:

```bash
skillsync --claude-dir /path/to/claude/skills --codex-dir /path/to/codex/skills
```

## Where skills live

| Folder | How Skill Bridge uses it |
| --- | --- |
| `~/.claude/skills` | Reads and writes Claude Code skills. |
| `~/.agents/skills` | Reads and writes Codex skills. |
| `~/.codex/skills` | Also reads Codex skills here, but never writes to it unless you pass `--codex-dir`. |
| `~/.local/state/skill-bridge/backups` | Holds backups of replaced skills. |

Each skill is a folder that contains a `SKILL.md`:

```text
~/.claude/skills/
└── pdf-tools/
    ├── SKILL.md
    └── scripts/
        └── extract.sh
```

Skill Bridge also finds skills inside nested subfolders. It skips hidden folders such as `.system` and `.git`, plugin caches, and old `.claude/commands` files.

These environment variables change the default folders:

| Variable | Effect |
| --- | --- |
| `CLAUDE_CONFIG_DIR` | The Claude folder becomes `$CLAUDE_CONFIG_DIR/skills`. |
| `CODEX_HOME` | The extra Codex folder becomes `$CODEX_HOME/skills`. |
| `XDG_STATE_HOME` | State and backups go in `$XDG_STATE_HOME/skill-bridge`. |
| `SKILL_BRIDGE_STATE_DIR` | Sets the state folder directly. |

To see which folders are actually in use, run `skillsync --paths`.

## How copying works

- **It's a one-time copy, not a sync.** The source never changes. Later edits are not copied over automatically, so run Skill Bridge again when you want them.
- **Interrupted copies are safe.** Each skill is first copied to a temporary folder and then moved into place in one step. If a copy fails or you press Ctrl+C, the existing skill stays as it was.
- **Replacing gives an exact copy.** The old destination is backed up and then fully replaced, so files you deleted from the source don't remain at the destination.
- **Backups are kept outside the skill folders**, so they never appear as duplicate skills. Every backup path is printed.
- **Only one transfer runs at a time.** A lock file stops two windows from copying at once.
- **Symlinks are kept as they are.** Links that point outside the skill folder may need fixing after the copy. If the skill folder itself is a symlink, it is copied as a real folder.
- **Only files are copied.** Skill Bridge does not translate Claude-specific frontmatter, tool names, variables or hooks, and it does not install MCP servers. Skills that depend on these need manual changes to work in the other tool.

## Updating

```bash
cd ~/Skill-Bridge
git pull
bash skill-bridge.sh --install
```

The installer copies the script into `~/.local/bin`, so `git pull` on its own doesn't change the `skillsync` command you run. Run `--install` again after every pull. The previous version is saved in `~/.local/state/skill-bridge/setup-backups/`.

## Uninstalling

```bash
rm -- ~/.local/bin/skill-bridge
unalias skillsync 2>/dev/null
```

Then open `~/.bashrc` (or `~/.zshrc`) and delete these two lines:

```bash
# Skill Bridge: copy selected Claude Code / Codex skills
alias skillsync='"$HOME/.local/bin/skill-bridge"'
```

Optionally, also delete the clone (`rm -rf ~/Skill-Bridge`) and the state folder (`rm -rf ~/.local/state/skill-bridge`). Deleting the state folder **deletes every backup**. Uninstalling never touches your skills.

## Troubleshooting

### `skillsync: command not found`

The alias only loads in a new terminal. Run `source ~/.bashrc` (or `source ~/.zshrc`), or open a new terminal. To check that the install worked, run `ls -l ~/.local/bin/skill-bridge`. You can always run `~/.local/bin/skill-bridge` directly, and that also works in shells other than Bash and Zsh.

### `Permission denied` when running `./skill-bridge.sh`

Run `bash skill-bridge.sh` instead, or make the file executable with `chmod +x skill-bridge.sh`.

### `This script needs Bash 4 or later. Run it with bash, not sh.`

You ran the script with `sh`. Use `bash skill-bridge.sh`. If you already used `bash`, check your version with `bash --version`.

### `Error: Use --install bash or --install zsh to choose your shell.`

Your login shell isn't Bash or Zsh, so name the shell explicitly, for example `bash skill-bridge.sh --install bash`.

### `Error: An existing skillsync alias/function is in ~/.bashrc. Rename it first.`

Your shell config already defines a different `skillsync`. Remove or rename that definition, then run the installer again.

### No skills are listed

Run `skillsync --paths` and check those folders. Each skill needs its own folder with a `SKILL.md` inside, for example `~/.claude/skills/my-skill/SKILL.md`. If your skills are somewhere else, use `--claude-dir` or `--codex-dir`. Hidden folders are skipped.

### A copied skill doesn't show up in the other tool

- Start a new session in that tool.
- Check that `SKILL.md` has `name` and `description` in its frontmatter.
- If your Codex only reads `~/.codex/skills`, copy there with `--codex-dir ~/.codex/skills`.
- If the same skill name exists in more than one folder, run `skillsync --list` to find the duplicates.

### `Error: Another Skill Bridge transfer is running.`

Another `skillsync` window is in the middle of a copy. Finish or close it. The lock is released automatically when that process exits.

### Restoring a backup

When a skill is replaced, Skill Bridge prints a line starting with `Backup:`. To restore that backup, use the paths it printed:

```bash
backup=~/.local/state/skill-bridge/backups/20261003T094220.kOeZ1o/commit-helper
target=~/.agents/skills/commit-helper
rm -rf -- "$target" && cp -a -- "$backup" "$target"
```

To see all backups, run `ls ~/.local/state/skill-bridge/backups/`.

## Roadmap

Planned improvements and known limitations are listed in [ROADMAP.md](ROADMAP.md).

## References

- [Claude Code skills documentation](https://code.claude.com/docs/en/skills)
- [Codex skills documentation](https://learn.chatgpt.com/docs/build-skills)
