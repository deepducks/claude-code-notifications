#!/usr/bin/env bash
# claude-code-notifications — lib/common.sh
# Núcleo compartilhado entre plataformas: carrega a config, faz o parsing do
# payload do hook (contrato EVENT/TITLE/BODY/FOOTER/TURN_SECS), aplica o
# filtro de duração e resolve a intenção de som. Nada de ferramentas
# específicas de plataforma aqui (wslpath/reg.exe/powershell.exe ficam nos
# backends, em scripts/backends/*.sh).

detect_platform() {
  case "$(uname -s 2>/dev/null)" in
    Darwin) echo macos ;;
    Linux)
      if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
        echo windows
      else
        echo linux
      fi
      ;;
    *) echo unknown ;;
  esac
}

ccn_load_config() {
  CONFIG="${CCN_CONFIG:-$HOME/.claude/hooks/ccn.config}"
  LOGO_WIN=""; CCN_APP_ID=""; CCN_DEFAULT_WAV=""; CCN_ALERT_WAV=""
  [ -f "$CONFIG" ] && . "$CONFIG"
}

# Lê o payload do hook (stdin) + transcript e preenche o contrato consumido
# pelos backends de render: EVENT, TITLE, BODY, FOOTER, TURN_SECS (e CWD).
ccn_parse_payload() {
  local start_ts se project branch max_len
  payload="$(cat)"
  get() { printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }
  EVENT="$(get '.hook_event_name')"
  transcript="$(get '.transcript_path')"
  CWD="$(get '.cwd')"; [ -z "$CWD" ] && CWD="$PWD"

  tjq() { [ -n "$transcript" ] && [ -f "$transcript" ] && jq -rs "$1" "$transcript" 2>/dev/null; }

  # --- duração do turno (do último prompt humano até agora; só no Stop) -----
  TURN_SECS=""
  if [ "$EVENT" != "Notification" ]; then
    start_ts="$(tjq '[.[] | select(.type=="user") | select((.message.content|tostring)|test("tool_result")|not) | .timestamp] | last // empty')"
    if [ -n "$start_ts" ]; then
      se="$(date -d "$start_ts" +%s 2>/dev/null || true)"
      [ -n "$se" ] && TURN_SECS=$(( $(date +%s) - se ))
      [ -n "$TURN_SECS" ] && [ "$TURN_SECS" -lt 0 ] && TURN_SECS=""
    fi
  fi

  # --- título -----------------------------------------------------------------
  TITLE="$(tjq '([.[] | select(.type=="custom-title") | .customTitle] | last) // ([.[] | select(.type=="ai-title") | .aiTitle] | last) // empty')"
  [ -z "$TITLE" ] && TITLE="$(basename "$CWD")"

  # --- corpo -------------------------------------------------------------------
  if [ "$EVENT" = "Notification" ]; then
    BODY="$(get '.message')"; [ -z "$BODY" ] && BODY="Aguardando sua ação"
  else
    BODY="$(tjq '[.[] | select(.type=="assistant" and (.message.content|type=="array") and (.message.content|any(.type=="text")))] | last | .message.content | map(select(.type=="text")|.text) | join(" ")')"
    [ -z "$BODY" ] && BODY="Terminou de responder"
  fi
  BODY="$(printf '%s' "$BODY" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')"
  max_len="${CCN_MAX_LEN:-220}"
  [ "${#BODY}" -gt "$max_len" ] && BODY="$(printf '%s' "$BODY" | cut -c1-"$max_len")…"

  # --- rodapé: projeto · branch · hora [· duração] -----------------------------
  fmt_dur() { if [ "$1" -ge 60 ]; then printf '%dm%02ds' "$(($1/60))" "$(($1%60))"; else printf '%ds' "$1"; fi; }
  project="$(basename "$CWD")"
  branch="$(tjq '[.[] | .gitBranch // empty] | last // empty')"
  [ -z "$branch" ] && branch="$(git -C "$CWD" branch --show-current 2>/dev/null)"
  FOOTER="$project"
  [ -n "$branch" ] && [ "$branch" != "HEAD" ] && FOOTER="$FOOTER · ⎇ $branch"
  FOOTER="$FOOTER · $(date +%H:%M)"
  if [ "${CCN_SHOW_DURATION:-1}" != "0" ] && [ -n "$TURN_SECS" ]; then
    FOOTER="$FOOTER · $(fmt_dur "$TURN_SECS")"
  fi
}

# Filtro de duração (só Stop): retorna 1 quando a resposta foi mais rápida
# que CCN_MIN_SECONDS, para o chamador dar exit 0 sem notificar.
ccn_apply_threshold() {
  local min_s="${CCN_MIN_SECONDS:-0}"
  if [ "$EVENT" != "Notification" ] && [ -n "$TURN_SECS" ] \
     && [ "$min_s" -gt 0 ] && [ "$TURN_SECS" -lt "$min_s" ]; then
    return 1
  fi
  return 0
}

# Resolve a intenção de som (silencioso / evento nomeado / arquivo custom) a
# partir de CCN_SOUND/CCN_SOUND_FILE/CCN_ALERT — sem tocar em ferramentas de
# plataforma. Preenche CCN_SOUND_FILE_RAW, CCN_SOUND_NAMED e
# CCN_SOUND_IS_SILENT_REQUEST; cada backend decide como converter o caminho
# do arquivo (ex.: wslpath) e como efetivamente tocar o som.
ccn_sound_intent() {
  local ev_default
  ev_default="$CCN_DEFAULT_WAV"
  if [ "$EVENT" = "Notification" ] && [ "${CCN_ALERT:-0}" = "1" ] && [ -n "$CCN_ALERT_WAV" ]; then
    ev_default="$CCN_ALERT_WAV"
  fi
  CCN_SOUND_FILE_RAW=""
  if [ -n "${CCN_SOUND_FILE:-}" ]; then
    CCN_SOUND_FILE_RAW="$CCN_SOUND_FILE"
  elif [ -z "${CCN_SOUND:-}" ] && [ -n "$ev_default" ]; then
    CCN_SOUND_FILE_RAW="$ev_default"
  fi
  CCN_SOUND_NAMED="${CCN_SOUND:-ms-winsoundevent:Notification.Default}"
  CCN_SOUND_IS_SILENT_REQUEST=0
  [ "${CCN_SOUND:-}" = "silent" ] && CCN_SOUND_IS_SILENT_REQUEST=1
}
