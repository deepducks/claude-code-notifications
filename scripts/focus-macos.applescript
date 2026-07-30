-- claude-code-notifications - focus-macos.applescript
-- Acionado por "terminal-notifier -execute" ao clicar na notificação.
-- Lê o alvo como dados via variável de ambiente (nunca concatenado na origem
-- do script, para não abrir espaço a injeção via título de sessão):
--   CCN_FOCUS_BUNDLE  bundle id do terminal dono da sessão (preferido)
--   CCN_FOCUS_NAME    nome do processo, usado quando o bundle id é desconhecido
--   CCN_FOCUS_TITLE   título da sessão, para selecionar aba/janela
--
-- Ativação genérica funciona para qualquer terminal (Wave, Ghostty, WezTerm,
-- kitty, Alacritty, Warp, Hyper, Tabby, VS Code, ...). Seleção de aba/janela
-- pelo título é best-effort e só entra para Terminal.app e iTerm2 -- os únicos
-- cujos dicionários AppleScript expõem endereçamento por aba. Sem resolução
-- nenhuma, cai no app frontmost. Só usa APIs de ativação seguras -- nunca
-- encerra processos nem faz manipulação privilegiada.

set theBundle to (system attribute "CCN_FOCUS_BUNDLE")
set theName to (system attribute "CCN_FOCUS_NAME")
set theTitle to (system attribute "CCN_FOCUS_TITLE")

set didActivate to false

-- 1) ativação genérica pelo bundle id (funciona para qualquer terminal)
if theBundle is not "" then
	try
		tell application id theBundle to activate
		set didActivate to true
	end try
end if

-- 2) fallback: só o nome do processo é conhecido
if not didActivate and theName is not "" then
	try
		tell application "System Events"
			set frontmost of first process whose name is theName to true
		end tell
		set didActivate to true
	end try
end if

-- 3) último recurso: nada resolvido -- não faz nada (já é o frontmost)
if not didActivate and theBundle is "" and theName is "" then
	try
		tell application "System Events"
			set _p to first process whose frontmost is true
			set frontmost of _p to true
		end tell
	end try
end if

-- 4) best-effort: seleciona a aba/janela pelo título -- Terminal.app e iTerm2
if theTitle is not "" then
	if theBundle is "com.apple.Terminal" then
		try
			tell application "Terminal"
				repeat with w in windows
					try
						if (name of w contains theTitle) then
							set index of w to 1
							exit repeat
						end if
					end try
					repeat with t in tabs of w
						try
							if (custom title of t contains theTitle) then
								set selected of t to true
								set index of w to 1
								exit repeat
							end if
						end try
					end repeat
				end repeat
			end tell
		end try
	else if theBundle is "com.googlecode.iterm2" then
		try
			tell application "iTerm2"
				repeat with w in windows
					repeat with t in tabs of w
						repeat with s in sessions of t
							try
								if (name of s contains theTitle) then
									select t
									select w
									exit repeat
								end if
							end try
						end repeat
					end repeat
				end repeat
			end tell
		end try
	end if
end if
