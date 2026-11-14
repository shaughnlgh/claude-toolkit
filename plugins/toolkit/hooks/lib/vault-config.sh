# Sourced by the hooks and vault-fs.sh: the one shell definition of the vault config path.
# Prints the first file that exists under $1/.claude (default $HOME): toolkit-vault.json, then the legacy obsidian-sync.json. Returns 1 when neither exists.
vault_config_file() {
  local h="${1:-$HOME}" f
  for f in toolkit-vault.json obsidian-sync.json; do
    [ -f "$h/.claude/$f" ] && { printf '%s\n' "$h/.claude/$f"; return 0; }
  done
  return 1
}
