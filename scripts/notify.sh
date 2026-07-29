#!/usr/bin/env bash
# claude-code-notifications — notify.sh
# Toast nativo do Windows (a partir do WSL) para eventos do Claude Code.
#
# Stop         -> "terminou de responder", corpo = trecho da última resposta.
# Notification -> "aguardando você", corpo = mensagem do Claude.
#
# Este script é só o despachante: carrega a config, faz o parsing do payload
# do hook (via lib/common.sh) e repassa para o backend da plataforma
# detectada (scripts/backends/*.sh). Toda lógica específica de plataforma —
# renderização do toast, wslpath/reg.exe/powershell.exe etc. — mora no
# respectivo backend.
#
# Variáveis (em ~/.claude/hooks/ccn.config ou no ambiente):
#   CCN_ENABLED=0        desliga as notificações
#   CCN_MIN_SECONDS=N    no Stop, só notifica se a resposta demorou >= N seg
#   CCN_SHOW_DURATION=0  não mostra a duração no rodapé
#   CCN_SOUND=...        evento ms-winsoundevent, ou 'silent'
#   CCN_SOUND_FILE=...   .wav próprio (tem prioridade sobre CCN_SOUND)
#   CCN_MAX_LEN=N        tamanho do trecho (padrão 220)
#
# Requisitos (checados pelo backend Windows): WSL, powershell.exe no PATH, jq.

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/common.sh"

ccn_load_config

# desligado?
[ "${CCN_ENABLED:-1}" = "0" ] && exit 0

ccn_parse_payload
ccn_apply_threshold || exit 0

case "$(detect_platform)" in
  windows)
    . "$here/backends/windows.sh"
    ccn_render_windows
    ;;
  macos)
    . "$here/backends/macos.sh"
    ccn_render_macos
    ;;
  *)
    exit 0
    ;;
esac

exit 0
