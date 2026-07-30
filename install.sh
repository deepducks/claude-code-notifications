#!/usr/bin/env bash
# claude-code-notifications — instalador
# Instala o hook de notificações nativas para o Claude Code. Suporta WSL
# (toast do Windows) e macOS (Notification Center). A plataforma é detectada
# via scripts/lib/common.sh (mesma lógica usada em runtime pelo notify.sh).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
CONFIG="$HOOKS_DIR/ccn.config"

info() { printf '\033[36m›\033[0m %s\n' "$1"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
err()  { printf '\033[31m✗\033[0m %s\n' "$1" >&2; }
warn() { printf '\033[33m!\033[0m %s\n' "$1"; }

. "$REPO_DIR/scripts/lib/common.sh"

# --- pré-requisito compartilhado ---------------------------------------------
command -v jq >/dev/null 2>&1 || { err "jq não encontrado. Instale: sudo apt install jq (WSL) ou brew install jq (macOS)"; exit 1; }

CCN_VER="$(jq -r '.version // "0"' "$REPO_DIR/.claude-plugin/plugin.json" 2>/dev/null || echo 0)"
PLATFORM="$(detect_platform)"

case "$PLATFORM" in
  windows)
    # --- pré-requisitos WSL ---------------------------------------------------
    command -v powershell.exe >/dev/null 2>&1  || { err "powershell.exe não está no PATH do WSL."; exit 1; }
    ok "Ambiente WSL + jq + powershell.exe"

    # --- caminho Windows (LOCALAPPDATA) ------------------------------------------
    LOCALAPPDATA_WIN="$(powershell.exe -NoProfile -Command '$env:LOCALAPPDATA' 2>/dev/null | tr -d '\r')"
    WIN_DIR_WIN="${LOCALAPPDATA_WIN}\\claude-code-notifications"
    WIN_DIR_WSL="$(wslpath "$LOCALAPPDATA_WIN")/claude-code-notifications"
    LOGO_WIN="${WIN_DIR_WIN}\\claude-logo.png"      # mascote (corpo do toast)
    HEADER_WIN="${WIN_DIR_WIN}\\anthropic.png"      # logo Anthropic (ícone do AppID)

    # --- copia arquivos ----------------------------------------------------------
    mkdir -p "$HOOKS_DIR" "$WIN_DIR_WSL" "$HOOKS_DIR/lib" "$HOOKS_DIR/backends"
    install -m 0755 "$REPO_DIR/scripts/notify.sh" "$HOOKS_DIR/ccn-notify.sh"
    install -m 0644 "$REPO_DIR/scripts/lib/common.sh" "$HOOKS_DIR/lib/common.sh"
    install -m 0644 "$REPO_DIR/scripts/backends/windows.sh" "$HOOKS_DIR/backends/windows.sh"
    cp -f "$REPO_DIR/assets/claude-logo.png"  "$WIN_DIR_WSL/claude-logo.png"
    cp -f "$REPO_DIR/assets/anthropic.png"    "$WIN_DIR_WSL/anthropic.png"
    cp -f "$REPO_DIR/assets/sounds/Cloud.wav" "$WIN_DIR_WSL/Cloud.wav"
    cp -f "$REPO_DIR/assets/sounds/Alert.wav" "$WIN_DIR_WSL/Alert.wav"
    cp -f "$REPO_DIR/scripts/focus.ps1"       "$WIN_DIR_WSL/focus.ps1"
    cp -f "$REPO_DIR/scripts/focus.vbs"       "$WIN_DIR_WSL/focus.vbs"
    ok "Hook instalado em $HOOKS_DIR (logos em $WIN_DIR_WSL)"

    # --- registra o AppID (AUMID) — sem isso o Windows descarta o toast ----------
    AUMID="Claude.Code.Notifications"
    AUMID_KEY="HKCU\\Software\\Classes\\AppUserModelId\\$AUMID"
    reg.exe add "$AUMID_KEY" /v DisplayName /d "Claude Code" /f >/dev/null
    reg.exe add "$AUMID_KEY" /v IconUri /d "$HEADER_WIN" /f >/dev/null
    ok "AppID '$AUMID' registrado (nome + ícone Anthropic no cabeçalho)"

    # --- protocolo do clique (foca a aba/janela da sessão) -----------------------
    PROTO_CMD="wscript.exe \"${WIN_DIR_WIN}\\focus.vbs\" \"%1\""
    reg.exe add "HKCU\\Software\\Classes\\claudecodenotify" /ve /d "URL:Claude Code Notify" /f >/dev/null
    reg.exe add "HKCU\\Software\\Classes\\claudecodenotify" /v "URL Protocol" /d "" /f >/dev/null
    reg.exe add "HKCU\\Software\\Classes\\claudecodenotify\\shell\\open\\command" /ve /d "$PROTO_CMD" /f >/dev/null
    ok "Clique na notificação foca a aba/janela da sessão"

    # --- config (AppID + caminho da logo p/ o notify.sh) -------------------------
    { printf "CCN_APP_ID='%s'\n" "$AUMID"
      printf "LOGO_WIN='%s'\n" "$LOGO_WIN"
      printf "CCN_DEFAULT_WAV='%s'\n" "${WIN_DIR_WIN}\\Cloud.wav"
      printf "CCN_ALERT_WAV='%s'\n" "${WIN_DIR_WIN}\\Alert.wav"
      printf "CCN_VER='%s'\n" "$CCN_VER"; } > "$CONFIG"
    ok "Config gravado em $CONFIG"
    ;;

  macos)
    ok "Ambiente macOS + jq"

    # --- copia arquivos ----------------------------------------------------------
    mkdir -p "$HOOKS_DIR" "$HOOKS_DIR/lib" "$HOOKS_DIR/backends"
    install -m 0755 "$REPO_DIR/scripts/notify.sh" "$HOOKS_DIR/ccn-notify.sh"
    install -m 0644 "$REPO_DIR/scripts/lib/common.sh" "$HOOKS_DIR/lib/common.sh"
    install -m 0644 "$REPO_DIR/scripts/backends/macos.sh" "$HOOKS_DIR/backends/macos.sh"
    install -m 0644 "$REPO_DIR/scripts/focus-macos.applescript" "$HOOKS_DIR/focus-macos.applescript"
    ok "Hook instalado em $HOOKS_DIR"

    # --- terminal-notifier (opcional, mas melhora ícone/imagem/clique) -----------
    if command -v terminal-notifier >/dev/null 2>&1; then
      ok "terminal-notifier encontrado"
    elif command -v brew >/dev/null 2>&1; then
      install_tn="y"
      if [ -t 0 ]; then
        read -r -p "› terminal-notifier não encontrado. Instalar agora via Homebrew? [Y/n] " reply || reply=""
        case "$reply" in [nN]*) install_tn="n" ;; *) install_tn="y" ;; esac
      fi
      if [ "$install_tn" = "y" ] && brew install terminal-notifier; then
        ok "terminal-notifier instalado"
      else
        warn "Seguindo sem terminal-notifier — notificações via osascript (sem ícone próprio, imagem de conteúdo ou clique-para-focar)."
      fi
    else
      warn "terminal-notifier não encontrado (Homebrew indisponível) — notificações via osascript (sem ícone próprio, imagem de conteúdo ou clique-para-focar)."
    fi

    # --- copia assets p/ Application Support --------------------------------------
    SUPPORT_DIR="$HOME/Library/Application Support/claude-code-notifications"
    mkdir -p "$SUPPORT_DIR"
    cp -f "$REPO_DIR/assets/claude-logo.png" "$SUPPORT_DIR/claude-logo.png"
    cp -f "$REPO_DIR/assets/anthropic.png"   "$SUPPORT_DIR/anthropic.png"
    cp -f "$REPO_DIR"/assets/sounds/*        "$SUPPORT_DIR/"
    ok "Assets copiados para \"$SUPPORT_DIR\""

    # --- config (ícone/mascote + sons nomeados p/ o notify.sh) -------------------
    { printf "CCN_ICON='%s'\n" "$SUPPORT_DIR/anthropic.png"
      printf "CCN_MASCOT='%s'\n" "$SUPPORT_DIR/claude-logo.png"
      printf "CCN_DEFAULT_SOUND='%s'\n" "Glass"
      printf "CCN_ALERT_SOUND='%s'\n" "Basso"
      printf "CCN_VER='%s'\n" "$CCN_VER"; } > "$CONFIG"
    ok "Config gravado em $CONFIG"
    ;;

  *)
    err "Plataforma não suportada ($PLATFORM). Este instalador funciona em WSL (Windows) ou macOS."
    exit 1
    ;;
esac

# --- merge dos hooks no settings.json (idempotente + backup) -----------------
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp -f "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
HOOK_CMD="$HOOKS_DIR/ccn-notify.sh"
jq --arg cmd "$HOOK_CMD" '
  def clean(a): (a // []) | map(select(((.hooks // []) | any((.command // "") | test("ccn-notify"))) | not));
  .hooks.Stop         = clean(.hooks.Stop)         + [{"hooks":[{"type":"command","command":$cmd}]}]
  | .hooks.Notification = clean(.hooks.Notification) + [{"hooks":[{"type":"command","command":$cmd}]}]
' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
jq empty "$SETTINGS" && ok "Hooks Stop + Notification adicionados em $SETTINGS"

echo
ok "Instalado! Abra o menu /hooks no Claude Code (ou reinicie) para recarregar."
info "Teste: no Claude Code, envie uma mensagem — ao terminar, o toast aparece."
info "Desinstalar: bash \"$REPO_DIR/uninstall.sh\""
