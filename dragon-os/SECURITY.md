# Dragon OS 1.5: auditoria de segurança

Escopo: todo o diretório `dragon-os/` (dragonctl, dragond, scripts de shell, Zsh, dotfiles,
serviços systemd, abertura de boot, instalador e gerador de ISO).
Método: `shellcheck`, `bandit`, revisão manual e provas de conceito executadas contra um
Ollama simulado, repetidas depois das correções.

## Modelo de ameaça

- **Conteúdo não confiável que chega ao modelo**: PDFs e textos baixados em `~/Documentos`
  (indexados automaticamente), texto copiado da web (`@`, Hoard), diffs de terceiros (`gcai`),
  imagens da tela (Dragon Eye). Esse conteúdo pode conter *prompt injection*, ou seja, instruções
  que manipulam a resposta do modelo.
- **Outros usuários e processos locais**: tudo o que fica em `/tmp` ou escuta em `127.0.0.1`.
- **Acesso físico**: login automático na abertura de boot.
- **Cadeia de suprimentos**: código baixado e compilado pelo instalador.

## Achados e correções

| # | Severidade | Achado | Correção |
|---|---|---|---|
| 1 | Alta | O Breath executava a 1ª linha da resposta do modelo (`sh -c`) num terminal. Com `#` ou `@`, um documento ou texto copiado podia ditar o comando. | O comando é só **digitado** no prompt do Zsh (`DRAGON_PREFILL` + `print -z`) e roda apenas se o usuário apertar Enter. |
| 2 | Alta | Injeção de escape de terminal: trechos de documentos (`scales search`) e saída do modelo (`ask`, `gen`) iam crus para o terminal. Uma sequência OSC 52 sobrescreve o clipboard. PoC confirmada. | `safe_text()` remove caracteres de controle em toda saída para terminal, Zsh e clipboard. |
| 3 | Alta | O `wtf` usava `echo` do zsh, que transforma o texto `\033` vindo do modelo em ESC real. PoC confirmada. | `print -r`. |
| 4 | Média | Arquivos previsíveis em `/tmp` (estado do dragond, PID e **áudio do ditado**, lock do Santuário): legíveis por outros usuários (o áudio) ou forjáveis por eles (o estado lido pela Waybar, Starship e dragonctl). | Tudo em `$XDG_RUNTIME_DIR` (`/run/user/UID`, 0700), com `umask 077`; gravação atômica do estado. |
| 5 | Média | O PID do ditado era lido do arquivo e recebia `kill` sem verificação. | Só sinaliza se o processo for mesmo o `pw-record`. |
| 6 | Média | `wtype "$TEXTO"`: uma transcrição começando com `-` virava opção (ex.: `-k Return` aperta Enter na janela em foco). | `wtype -- "$TEXTO"`, além da remoção de caracteres de controle. |
| 7 | Média | Symlinks dentro das pastas monitoradas puxavam arquivos de fora (ex.: `~/.ssh/id_ed25519`) para o índice. PoC confirmada. | Symlinks são ignorados; arquivos com nome de segredo (`credentials`, `secret`, `token`, `.pem`…) também. |
| 8 | Média | O índice Scales (trechos de todos os documentos) era criado com 0755/0644. | Pasta 0700, banco 0600. |
| 9 | Média | `export _DRAGON_LAST_CMD`: a linha anterior (com senhas, tokens) ia para o ambiente de todo processo filho. PoC confirmada. | Variável global não exportada. |
| 10 | Média | Login automático: a sessão ficava aberta durante o vídeo, e se o `dragon-intro.sh` falhasse o bloqueio nunca acontecia. | Atalhos desligados (submap `dragon_lockdown`) até o `hyprlock` subir; vídeo limitado a 3 s; `exec-once = dragon-intro.sh \|\| hyprlock` (falha fechada). |
| 11 | Média | `build-dragon-iso.sh` usava `/tmp/dragon-profile` fixo: outro usuário local podia preparar o perfil, e o `mkarchiso` (root) executaria o `profiledef.sh` dele. | `mktemp -d` exclusivo e limpeza em `trap`. |
| 12 | Média | `whisper.cpp` compilado a partir do HEAD do GitHub. | Fixado na tag `v1.9.5` e conferido contra o commit `d1be6fde…`; aborta se não bater. |
| 13 | Baixa | `dragonctl model` / `model.override` eram escritos no `dragon_env.sh` (lido com `source`) sem validação. PoC de injeção não executou. | Nome de modelo validado por regex nos dois lados; valores com `shlex.quote`. |
| 14 | Baixa | Serviços de usuário sem isolamento; o indexador abre PDFs da internet automaticamente. | `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome=read-only` com escrita só no necessário, `PrivateTmp` etc. nos três serviços. |
| 15 | Baixa | Texto do ditado no corpo da notificação era interpretado como markup do Dunst. | Escape de `& < >`. |
| 16 | Baixa | `gcai` colocava a mensagem do modelo entre aspas duplas: `$(...)` seria executado no Enter. | Já corrigido na 1.5 (`${(qq)msg}`). |
| 17 | Info | `Ctrl+G` gera comandos que o usuário revisa. | Alerta (sem bloquear) para `sudo`, `rm -rf`, `dd`, `mkfs`, `curl \| sh`… |
| 18 | Info | Histórico de clipboard sem limite. | `cliphist -max-items 200`. |

## Riscos residuais (aceitos ou fora do alcance do código)

- **Prompt injection continua possível**: o modelo pode ser manipulado por documentos e textos
  copiados. As correções garantem que a saída manipulada **não seja executada nem escape para o
  terminal**, mas as respostas exibidas podem estar erradas ou enganosas.
- **cliphist** guarda em disco tudo o que é copiado (`~/.cache/cliphist`). Gerenciadores de senha
  que marcam a cópia como sensível ficam de fora; os demais, não. Use `cliphist wipe` quando necessário.
- **Ollama (11434) e whisper-server (8178)** escutam em `127.0.0.1` sem autenticação: qualquer
  processo local da máquina pode usá-los. Não exponha com `OLLAMA_HOST=0.0.0.0`.
- **Login automático**: sem criptografia de disco, quem tem acesso físico tem acesso aos dados de
  qualquer forma; o `hyprlock` protege só a sessão. `DRAGON_AUTOLOGIN=0` desliga.
- **hyprlock com `path = screenshot`**: o fundo é um print borrado da tela; textos grandes podem
  continuar legíveis.
- **Modelos do whisper.cpp** são baixados do Hugging Face (HTTPS) sem verificação de hash;
  os modelos do Ollama são verificados por digest pelo próprio Ollama.
- **Isolamento systemd não testado em máquina real**: se um serviço não subir, confira
  `journalctl --user -u <serviço>`; a causa provável é uma das linhas `Protect*`/`ReadWritePaths`.
