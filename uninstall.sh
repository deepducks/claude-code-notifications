#!/usr/bin/env bash
# claude-code-notifications — desinstalador
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
PROTOCOL="claudecodenotify"
ok() { printf '\033[32m✓\033[0m %s\n' "$1"; }

. "$REPO_DIR/scripts/lib/common.sh"

# remove hooks ccn do settings.json (preserva o resto), com backup
if [ -f "$SETTINGS" ]; then
  cp -f "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
  jq '
    def clean(a): (a // []) | map(select(((.hooks // []) | any((.command // "") | test("ccn-notify"))) | not));
    .hooks.Stop = clean(.hooks.Stop) | .hooks.Notification = clean(.hooks.Notification)
    | if (.hooks.Stop | length) == 0 then del(.hooks.Stop) else . end
    | if (.hooks.Notification | length) == 0 then del(.hooks.Notification) else . end
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  ok "Hooks removidos do settings.json"
fi

case "$(detect_platform)" in
  windows)
    # desregistra protocolo e AppID
    reg.exe delete "HKCU\\Software\\Classes\\$PROTOCOL" /f >/dev/null 2>&1 || true
    reg.exe delete "HKCU\\Software\\Classes\\AppUserModelId\\Claude.Code.Notifications" /f >/dev/null 2>&1 || true
    ok "Protocolo $PROTOCOL:// e AppID desregistrados"
    ;;
  macos)
    # remove os assets copiados p/ Application Support
    SUPPORT_DIR="$HOME/Library/Application Support/claude-code-notifications"
    rm -rf "$SUPPORT_DIR"
    ok "Diretório de suporte removido ($SUPPORT_DIR)"
    ;;
esac

# remove script do hook (deixa a logo/handler no Windows; inofensivos)
rm -f "$HOOKS_DIR/ccn-notify.sh" "$HOOKS_DIR/ccn.config" "$HOOKS_DIR/focus-macos.applescript"
rm -rf "$HOOKS_DIR/lib" "$HOOKS_DIR/backends"
ok "Scripts do hook removidos"

echo; ok "Desinstalado. Abra /hooks ou reinicie o Claude Code para recarregar."
