#!/usr/bin/env bash
# claude-code-notifications — backends/macos.sh
# Renderização de notificação nativa do macOS (Notification Center). Consome o
# contrato EVENT/TITLE/BODY/FOOTER/TURN_SECS (lib/common.sh) e as variáveis de
# configuração carregadas por ccn_load_config. Auto-configura o lado macOS na
# 1ª execução (copia assets; nada de reg.exe/AUMID/protocolo — isso é só
# Windows). A notificação em si independe do terminal que hospeda a sessão;
# só o clique (foco) precisa saber quem é o terminal — ver ccn_owning_terminal.

# escapa um valor para uso seguro dentro de uma string de shell (aspas simples),
# usado só para montar o argumento -execute do terminal-notifier (nunca para
# concatenar texto do transcript direto na origem de um script).
_ccn_shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# --- auto-setup do lado macOS (re-roda quando a versão do plugin muda) -------
# atualiza só as chaves gerenciadas, preservando as configs do usuário.
ccn_set() {  # ccn_set CHAVE VALOR  (no arquivo $CONFIG)
  touch "$CONFIG"
  grep -v "^$1=" "$CONFIG" > "$CONFIG.tmp" 2>/dev/null || true
  printf "%s='%s'\n" "$1" "$2" >> "$CONFIG.tmp"
  mv "$CONFIG.tmp" "$CONFIG"
}
ensure_setup_macos() {
  local here assets ver curver support
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  assets="${CLAUDE_PLUGIN_ROOT:-$here/..}/assets"
  [ -d "$assets" ] || assets="$here/../assets"
  ver="$(jq -r '.version // "0"' "${CLAUDE_PLUGIN_ROOT:-$here/..}/.claude-plugin/plugin.json" 2>/dev/null || echo 0)"
  curver="$([ -f "$CONFIG" ] && sed -n "s/^CCN_VER='\(.*\)'$/\1/p" "$CONFIG" | tail -1)"
  [ -n "$curver" ] && [ "$curver" = "$ver" ] && return 0   # já configurado nesta versão
  support="$HOME/Library/Application Support/claude-code-notifications"
  mkdir -p "$support" "$(dirname "$CONFIG")" 2>/dev/null
  cp -f "$assets/claude-logo.png" "$support/claude-logo.png" 2>/dev/null
  cp -f "$assets/anthropic.png"   "$support/anthropic.png"   2>/dev/null
  cp -f "$assets"/sounds/*        "$support/"                2>/dev/null
  ccn_set CCN_ICON          "$support/anthropic.png"
  ccn_set CCN_MASCOT        "$support/claude-logo.png"
  ccn_set CCN_DEFAULT_SOUND Glass
  ccn_set CCN_ALERT_SOUND   Basso
  ccn_set CCN_VER "$ver"
}

# --- som: vocabulário /ccn -> nome de som do macOS ---------------------------
# default -> Glass, silent -> omite, im -> Blow, mail -> Ping, reminder -> Hero,
# alarm -> Sosumi, call -> Funk. CCN_SOUND_FILE (custom) toca à parte via
# afplay, com a notificação silenciosa. CCN_ALERT=1 troca o som padrão do
# Notification por um som de alerta distinto (mesma semântica do Windows).
ccn_map_sound_macos() {
  ccn_sound_intent
  MAC_SOUND_NAME=""
  MAC_CUSTOM_FILE=""

  if [ -n "$CCN_SOUND_FILE_RAW" ]; then
    MAC_CUSTOM_FILE="$CCN_SOUND_FILE_RAW"
    return 0
  fi

  if [ "$CCN_SOUND_IS_SILENT_REQUEST" = "1" ]; then
    return 0   # silent: omite -sound / sound name
  fi

  case "${CCN_SOUND:-}" in
    im)       MAC_SOUND_NAME="Blow" ;;
    mail)     MAC_SOUND_NAME="Ping" ;;
    reminder) MAC_SOUND_NAME="Hero" ;;
    alarm)    MAC_SOUND_NAME="Sosumi" ;;
    call)     MAC_SOUND_NAME="Funk" ;;
    ""|default)
      if [ "$EVENT" = "Notification" ] && [ "${CCN_ALERT:-0}" = "1" ]; then
        MAC_SOUND_NAME="${CCN_ALERT_SOUND:-Basso}"
      else
        MAC_SOUND_NAME="${CCN_DEFAULT_SOUND:-Glass}"
      fi
      ;;
    *) MAC_SOUND_NAME="$CCN_SOUND" ;;   # passthrough de um nome de som do macOS
  esac
}

# --- resolve o terminal dono da sessão (para o clique) -----------------------
# 1) $TERM_PROGRAM (herdado do terminal, mapeado para bundle id)
# 2) ancestralidade de processo (sobe via ps, resolve o .app do executável)
# 3) app frontmost, como último recurso
# Preenche CCN_TERM_BUNDLE (preferido) e/ou CCN_TERM_NAME. Nunca falha: se nada
# resolver, ambos ficam vazios e o focus-macos.applescript cai no frontmost.
_ccn_bundle_id_from_exe() {
  local exe="$1" app
  app="$(printf '%s' "$exe" | sed -n 's#\(.*\.app\)/Contents/MacOS/.*#\1#p')"
  [ -z "$app" ] && return 1
  defaults read "$app/Contents/Info" CFBundleIdentifier 2>/dev/null
}

ccn_owning_terminal() {
  CCN_TERM_BUNDLE=""
  CCN_TERM_NAME=""

  case "${TERM_PROGRAM:-}" in
    Apple_Terminal) CCN_TERM_BUNDLE="com.apple.Terminal" ;;
    iTerm.app)      CCN_TERM_BUNDLE="com.googlecode.iterm2" ;;
    vscode)         CCN_TERM_BUNDLE="com.microsoft.VSCode" ;;
    WarpTerminal)   CCN_TERM_BUNDLE="dev.warp.Warp-Stable" ;;
    ghostty)        CCN_TERM_BUNDLE="com.mitchellh.ghostty" ;;
    WezTerm)        CCN_TERM_BUNDLE="com.github.wez.wezterm" ;;
    Hyper)          CCN_TERM_BUNDLE="co.zeit.hyper" ;;
    Tabby)          CCN_TERM_BUNDLE="org.tabby" ;;
  esac
  [ -n "$CCN_TERM_BUNDLE" ] && return 0

  local pid exe bundle
  pid=$$
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ -z "$pid" ] && break
    [ "$pid" = "1" ] && break
    exe="$(ps -o comm= -p "$pid" 2>/dev/null)"
    bundle="$(_ccn_bundle_id_from_exe "$exe")"
    if [ -n "$bundle" ]; then CCN_TERM_BUNDLE="$bundle"; return 0; fi
    if command -v lsappinfo >/dev/null 2>&1; then
      bundle="$(lsappinfo info -only bundleID -pid "$pid" 2>/dev/null | sed -n 's/.*"\(.*\)".*/\1/p')"
      if [ -n "$bundle" ]; then CCN_TERM_BUNDLE="$bundle"; return 0; fi
    fi
  done

  CCN_TERM_NAME="$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)"
}

# --- renderiza a notificação --------------------------------------------------
ccn_render_macos() {
  ensure_setup_macos
  CCN_ICON=""; CCN_MASCOT=""; CCN_DEFAULT_SOUND=""; CCN_ALERT_SOUND=""
  [ -f "$CONFIG" ] && . "$CONFIG"

  ccn_map_sound_macos

  local here focus_script project group

  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  focus_script="$here/focus-macos.applescript"
  project="$(basename "$CWD")"
  group="ccn-$project"

  # som customizado: toca à parte, sem bloquear o hook; notificação fica muda
  if [ -n "$MAC_CUSTOM_FILE" ] && command -v afplay >/dev/null 2>&1; then
    afplay "$MAC_CUSTOM_FILE" >/dev/null 2>&1 < /dev/null &
    disown $! 2>/dev/null || true
  fi

  if command -v terminal-notifier >/dev/null 2>&1; then
    local -a args
    args=(-title "$TITLE" -subtitle "$FOOTER" -message "$BODY" -group "$group")
    [ -n "$CCN_ICON" ]      && args+=(-appIcon "$CCN_ICON")
    [ -n "$CCN_MASCOT" ]    && args+=(-contentImage "$CCN_MASCOT")
    [ -n "$MAC_SOUND_NAME" ] && args+=(-sound "$MAC_SOUND_NAME")

    if [ "${CCN_CLICK:-1}" != "0" ]; then
      ccn_owning_terminal
      local focus_cmd
      focus_cmd="CCN_FOCUS_BUNDLE=$(_ccn_shq "$CCN_TERM_BUNDLE") CCN_FOCUS_NAME=$(_ccn_shq "$CCN_TERM_NAME") CCN_FOCUS_TITLE=$(_ccn_shq "$TITLE") osascript $(_ccn_shq "$focus_script")"
      args+=(-execute "$focus_cmd")
    fi

    terminal-notifier "${args[@]}" >/dev/null 2>&1 < /dev/null &
    disown $! 2>/dev/null || true
  else
    # fallback: osascript. Sem terminal-notifier não há ícone próprio, imagem de
    # conteúdo, clique-para-focar nem som customizado — fidelidade reduzida,
    # mas a notificação ainda aparece. Texto vai por variável de ambiente lida
    # com "system attribute", nunca concatenado na origem do AppleScript.
    (
      export CCN_TITLE="$TITLE" CCN_BODY="$BODY" CCN_FOOTER="$FOOTER" CCN_SOUND_NAME="$MAC_SOUND_NAME"
      osascript -e '
set theTitle to (system attribute "CCN_TITLE")
set theBody to (system attribute "CCN_BODY")
set theFooter to (system attribute "CCN_FOOTER")
set theSound to (system attribute "CCN_SOUND_NAME")
if theSound is "" then
	display notification theBody with title theTitle subtitle theFooter
else
	display notification theBody with title theTitle subtitle theFooter sound name theSound
end if
' >/dev/null 2>&1 < /dev/null
    ) &
    disown $! 2>/dev/null || true
  fi
}
