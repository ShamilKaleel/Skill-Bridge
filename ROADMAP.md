# Roadmap

Known gaps in `skill-bridge.sh` 1.0, grouped by priority. Tick items off as they ship.

## Done

- [x] `./skill-bridge.sh` works right after cloning, because the executable bit is now set in git.
- [x] `sh skill-bridge.sh` prints "Run it with bash" instead of the confusing `set: Illegal option -o pipefail`.

## High priority: correctness

- [ ] **Bash version check is too loose.** The script says it needs Bash 4.4+, but the check only rejects versions below 4. Bash 4.0–4.3 treat empty arrays as unset under `set -u`, so code that expands an empty array may abort there. Check the minor version as well, and test on Bash 4.3 if you plan to support it.
- [ ] **Skills with the same name can collide.** Skills found in nested subfolders are copied to `<destination>/<folder-name>`, so `team-a/deploy` and `team-b/deploy` both target `deploy`. Either keep the subfolder path or warn before copying.
- [ ] **Check for GNU tools at startup.** On BusyBox (Alpine) or macOS, `realpath -m` and `mv -T` fail with unclear errors. Detect this early and print one clear "GNU coreutils required" message.

## Install and update

- [ ] Add a `--version` flag. The version currently only appears in a comment.
- [ ] Add an `--uninstall` flag that removes the binary and the two alias lines, with a backup of the rc file.
- [ ] Add `--update` or a symlink install mode (`--install --link`). Right now the installed copy goes stale after `git pull` until `--install` is run again.
- [ ] Install a real `~/.local/bin/skillsync` command instead of relying only on the shell alias. `~/.local/bin` is usually on `PATH`, and a real command also works in scripts and in fish or other shells. Keep the alias for compatibility.

## Everyday use

- [ ] **Non-interactive mode** for scripts and automation: skill names as arguments (`skillsync --to-codex pdf-tools`), plus `--all`, `--yes`, `--replace` and `--skip-existing`.
- [ ] **`--dry-run`** to show what would be copied or replaced without doing it.
- [ ] **"Replace all / skip all"** answers at the conflict prompt, so you don't have to answer once per skill.
- [ ] **Skill check (`--check`)**: validate the `name` and `description` frontmatter in `SKILL.md`, and warn about Claude-only fields, hooks or variables before copying to Codex.
- [ ] **Backup management**: list backups, restore one by number, and prune old ones. Backups currently build up forever.
- [ ] **Sync status in `--list`**: show whether each destination copy is identical to its source, older, or changed.
- [ ] **Same-tool copies** between scopes, for example personal Claude skills ↔ a project's `.claude/skills`.

## Repository

- [ ] Add a `LICENSE`. The repository is public but has no license, so others can't legally reuse the code.
- [ ] Add ShellCheck and a GitHub Actions workflow that lints the script and runs a smoke test.
- [ ] Add automated tests (for example with bats) that run real transfers in temporary folders.
- [ ] Add a `CHANGELOG.md` and tag releases (`v1.0.0`).
- [ ] Add a `.gitattributes` with `*.sh text eol=lf`, so a Windows checkout can't add CRLF line endings that break the script.

## Cosmetic

- [ ] Fix the one-column misalignment of `--claude-dir`/`--codex-dir` in `--help` and of the `Backups:` row in `--paths`.
- [ ] Skill names longer than 26 characters push the columns out of line in the skill lists.
