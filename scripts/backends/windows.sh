#!/usr/bin/env bash
# claude-code-notifications — backends/windows.sh
# Renderização do toast nativo do Windows (a partir do WSL). Consome o
# contrato EVENT/TITLE/BODY/FOOTER/TURN_SECS (lib/common.sh) e as variáveis
# de configuração carregadas por ccn_load_config. Auto-configura o lado
# Windows na 1ª execução (copia assets + registra AppID + protocolo).

AUMID="Claude.Code.Notifications"

xml_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"; }
url_encode() { jq -rn --arg s "$1" '$s|@uri'; }

# --- auto-setup do lado Windows (re-roda quando a versão do plugin muda) ------
# atualiza só as chaves gerenciadas, preservando as configs do usuário.
ccn_set() {  # ccn_set CHAVE VALOR  (no arquivo $CONFIG)
  touch "$CONFIG"
  grep -v "^$1=" "$CONFIG" > "$CONFIG.tmp" 2>/dev/null || true
  printf "%s='%s'\n" "$1" "$2" >> "$CONFIG.tmp"
  mv "$CONFIG.tmp" "$CONFIG"
}
ensure_setup() {
  local here assets ver curver la win_win win_wsl
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  assets="${CLAUDE_PLUGIN_ROOT:-$here/..}/assets"
  [ -d "$assets" ] || assets="$here/../assets"
  ver="$(jq -r '.version // "0"' "${CLAUDE_PLUGIN_ROOT:-$here/..}/.claude-plugin/plugin.json" 2>/dev/null || echo 0)"
  curver="$([ -f "$CONFIG" ] && sed -n "s/^CCN_VER='\(.*\)'$/\1/p" "$CONFIG" | tail -1)"
  [ -n "$curver" ] && [ "$curver" = "$ver" ] && return 0   # já configurado nesta versão
  la="$(powershell.exe -NoProfile -Command '$env:LOCALAPPDATA' 2>/dev/null | tr -d '\r')"
  [ -z "$la" ] && return 0
  win_win="${la}\\claude-code-notifications"
  win_wsl="$(wslpath "$la" 2>/dev/null)/claude-code-notifications"
  mkdir -p "$win_wsl" "$(dirname "$CONFIG")" 2>/dev/null
  cp -f "$assets/claude-logo.png"  "$win_wsl/claude-logo.png" 2>/dev/null
  cp -f "$assets/anthropic.png"    "$win_wsl/anthropic.png"   2>/dev/null
  cp -f "$assets/sounds/Cloud.wav" "$win_wsl/Cloud.wav"       2>/dev/null
  cp -f "$assets/sounds/Alert.wav" "$win_wsl/Alert.wav"       2>/dev/null
  cp -f "$here/focus.ps1"          "$win_wsl/focus.ps1"       2>/dev/null
  cp -f "$here/focus.vbs"          "$win_wsl/focus.vbs"       2>/dev/null
  reg.exe add "HKCU\\Software\\Classes\\AppUserModelId\\$AUMID" /v DisplayName /d "Claude Code" /f >/dev/null 2>&1
  reg.exe add "HKCU\\Software\\Classes\\AppUserModelId\\$AUMID" /v IconUri /d "${win_win}\\anthropic.png" /f >/dev/null 2>&1
  reg.exe add "HKCU\\Software\\Classes\\claudecodenotify" /ve /d "URL:Claude Code Notify" /f >/dev/null 2>&1
  reg.exe add "HKCU\\Software\\Classes\\claudecodenotify" /v "URL Protocol" /d "" /f >/dev/null 2>&1
  reg.exe add "HKCU\\Software\\Classes\\claudecodenotify\\shell\\open\\command" /ve /d "wscript.exe \"${win_win}\\focus.vbs\" \"%1\"" /f >/dev/null 2>&1
  ccn_set CCN_APP_ID "$AUMID"
  ccn_set LOGO_WIN "${win_win}\\claude-logo.png"
  ccn_set CCN_DEFAULT_WAV "${win_win}\\Cloud.wav"
  ccn_set CCN_ALERT_WAV "${win_win}\\Alert.wav"
  ccn_set CCN_VER "$ver"
}

ccn_render_windows() {
  command -v jq >/dev/null 2>&1 || exit 0
  command -v powershell.exe >/dev/null 2>&1 || exit 0

  ensure_setup
  LOGO_WIN=""; CCN_APP_ID=""; CCN_DEFAULT_WAV=""; CCN_ALERT_WAV=""
  [ -f "$CONFIG" ] && . "$CONFIG"
  APP_ID="${CCN_APP_ID:-$AUMID}"

  # --- imagem (mascote no corpo) ----------------------------------------------
  image=""
  if [ -n "$LOGO_WIN" ]; then
    logo_uri="file:///$(printf '%s' "$LOGO_WIN" | sed 's#\\#/#g')"
    image="<image placement=\"appLogoOverride\" src=\"$(xml_escape "$logo_uri")\"/>"
  fi

  # --- som (padrão depende do evento; overrides globais preservados) -----------
  # Prioridade: CCN_SOUND_FILE > CCN_SOUND > som padrão do evento
  # (Stop = Cloud, Notification = Alert). CCN_SOUND=silent deixa mudo.
  # Padrão único: Cloud para todos os eventos. O som distinto de alerta no
  # Notification é opt-in (CCN_ALERT=1) — sem isso, é SEMPRE o Cloud.
  ccn_sound_intent
  custom_wav=""
  if [ -n "$CCN_SOUND_FILE_RAW" ]; then
    case "$CCN_SOUND_FILE_RAW" in
      /*) custom_wav="$(wslpath -w "$CCN_SOUND_FILE_RAW" 2>/dev/null)";;
      *)  custom_wav="$CCN_SOUND_FILE_RAW";;
    esac
  fi
  if [ -n "$custom_wav" ] || [ "$CCN_SOUND_IS_SILENT_REQUEST" = "1" ]; then
    audio='<audio silent="true"/>'
  else
    audio="<audio src=\"$(xml_escape "$CCN_SOUND_NAMED")\"/>"
  fi

  # --- monta e dispara o toast -------------------------------------------------
  tenc="$(url_encode "$TITLE")"

  # clicar foca a aba/janela da sessão (a menos que CCN_CLICK=0)
  launch=""
  if [ "${CCN_CLICK:-1}" != "0" ]; then
    launch=" launch=\"$(xml_escape "claudecodenotify://focus?title=${tenc}")\" activationType=\"protocol\""
  fi

  # botões de resposta no Notification (Sim / Sim sempre / Não). O "Sim sempre"
  # decide no clique: usa a opção "não perguntar" se existir, senão vira um Sim.
  # Desative com CCN_BUTTONS=0.
  actions=""
  if [ "$EVENT" = "Notification" ] && [ "${CCN_BUTTONS:-1}" != "0" ]; then
    a() { printf '<action content="%s" activationType="protocol" arguments="%s"/>' \
          "$(xml_escape "$1")" "$(xml_escape "claudecodenotify://answer?key=$2&title=${tenc}")"; }
    actions="<actions>$(a 'Sim' 1)$(a 'Sim, sempre' always)$(a 'Não' esc)</actions>"
  fi

  xml="<toast${launch}>
  <visual><binding template=\"ToastGeneric\">
    ${image}
    <text>$(xml_escape "$TITLE")</text>
    <text>$(xml_escape "$BODY")</text>
    <text placement=\"attribution\">$(xml_escape "$FOOTER")</text>
  </binding></visual>
  ${audio}
  ${actions}
</toast>"

  b64="$(printf '%s' "$xml" | base64 -w0 2>/dev/null || printf '%s' "$xml" | base64 | tr -d '\n')"

  powershell.exe -NoProfile -Command "
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType=WindowsRuntime]   | Out-Null
\$xml = [Windows.Data.Xml.Dom.XmlDocument]::new()
\$xml.LoadXml([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('$b64')))
\$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('$APP_ID').Show(\$toast)
" >/dev/null 2>&1

  # som custom (.wav): toca destacado, sem bloquear o hook
  if [ -n "$custom_wav" ]; then
    wav_esc="$(printf '%s' "$custom_wav" | sed "s/'/''/g")"
    setsid powershell.exe -NoProfile -Command "(New-Object Media.SoundPlayer '$wav_esc').PlaySync()" >/dev/null 2>&1 < /dev/null &
  fi
}
