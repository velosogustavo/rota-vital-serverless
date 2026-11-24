#!/usr/bin/env bash
# Roda os Passos 3, 4 e 5 da atividade e grava as saídas em evidencias/.
# Uso (na raiz do repositório, com o Docker aberto):
#   ./scripts/roteiro.sh invoke      # Passo 3: duas invocações com evento
#   ./scripts/roteiro.sh http        # Passo 4: start-api sem warm containers
#   ./scripts/roteiro.sh http-warm   # Passo 4: start-api --warm-containers LAZY
#   ./scripts/roteiro.sh timeout     # Passo 5: Timeout 3 s (erro) e depois 10 s
#   ./scripts/roteiro.sh timeout3    # só a parte do Timeout 3 s
#   ./scripts/roteiro.sh timeout10   # só a parte do Timeout 10 s
#   ./scripts/roteiro.sh tudo        # tudo em sequência
# No Windows, use Git Bash ou WSL.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidencias
export SAM_CLI_TELEMETRY=0
# No Git Bash do Windows o instalador cria só "sam.cmd"; alias não vale dentro
# de script, então uma função faz o papel de "sam".
if ! command -v sam >/dev/null 2>&1 && command -v sam.cmd >/dev/null 2>&1; then
  sam() { sam.cmd "$@"; }
fi
PORTA=3000
URL="http://127.0.0.1:${PORTA}/guias"

titulo() { printf '\n========== %s ==========\n' "$1"; }

invoke() {
  titulo "Passo 3: sam build --use-container + duas invocações com evento"
  sam build --use-container 2>&1 | tee evidencias/01-sam-build.txt
  for i in 1 2; do
    titulo "Invocação $i"
    { time sam local invoke -e events/pedido.json ; } 2>&1 | tee "evidencias/02-invoke-$i.txt"
  done
}

subir_api() {  # $1 = arquivo de log, demais = flags extras
  local log=$1; shift
  if curl -s -o /dev/null "http://127.0.0.1:${PORTA}/"; then
    echo "porta $PORTA já está em uso (start-api antigo?); pare-o antes"; return 1
  fi
  sam local start-api --port "$PORTA" "$@" >"$log" 2>&1 &
  API_PID=$!
  for _ in $(seq 1 60); do
    curl -s -o /dev/null "http://127.0.0.1:${PORTA}/" && return 0
    sleep 1
  done
  echo "start-api não respondeu; veja $log"; return 1
}

parar_api() {
  # No Git Bash, "kill" não alcança o python.exe do SAM; taskkill /T derruba a árvore.
  if [ -r "/proc/$API_PID/winpid" ] && command -v taskkill >/dev/null 2>&1; then
    taskkill //F //T //PID "$(cat "/proc/$API_PID/winpid")" >/dev/null 2>&1
  fi
  kill "$API_PID" 2>/dev/null; wait "$API_PID" 2>/dev/null; sleep 2
}

tres_curls() {  # $1 = arquivo de saída
  for i in 1 2 3; do
    echo "--- chamada $i ---"
    curl -s -w '\nHTTP %{http_code} em %{time_total}s\n' -X POST "$URL" \
      -H "Content-Type: application/json" \
      -d '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'
  done 2>&1 | tee "$1"
}

http() {
  titulo "Passo 4a: start-api sem --warm-containers"
  sam build --use-container >/dev/null 2>&1
  subir_api evidencias/03-start-api.log || return 1
  tres_curls evidencias/03-curl-sem-warm.txt
  parar_api
}

http_warm() {
  titulo "Passo 4b: start-api --warm-containers LAZY"
  sam build --use-container >/dev/null 2>&1
  subir_api evidencias/04-start-api-warm.log --warm-containers LAZY || return 1
  tres_curls evidencias/04-curl-warm.txt
  parar_api
}

demorar() {  # $1 = arquivo de saída
  curl -s -w '\nHTTP %{http_code} em %{time_total}s\n' -X POST "$URL" \
    -H "Content-Type: application/json" \
    -d '{"requisicaoId":"R-003","demorar":true}' 2>&1 | tee "$1"
}

trocar_timeout() {  # $1 = de, $2 = para
  sed "s/Timeout: $1 /Timeout: $2 /" template.yaml > template.tmp && mv template.tmp template.yaml
  grep -n "Timeout:" template.yaml
}

timeout3() {
  titulo "Passo 5a: demorar=true com Timeout 3 s"
  trocar_timeout 10 3 >/dev/null
  sam build --use-container >/dev/null 2>&1
  subir_api evidencias/05-start-api-timeout3.log || return 1
  demorar evidencias/05-curl-timeout3.txt
  parar_api
  echo "--- trecho do log do start-api ---"
  grep -iE "timed out|timeout|error" evidencias/05-start-api-timeout3.log | tail -5
}

timeout10() {
  titulo "Passo 5b: Timeout 10 s + sam build --use-container e repetir"
  trocar_timeout 3 10 | tee evidencias/06-template-timeout10.txt
  sam build --use-container >/dev/null 2>&1
  subir_api evidencias/06-start-api-timeout10.log || return 1
  demorar evidencias/06-curl-timeout10.txt
  parar_api

  echo "Voltando o template para Timeout 3 (valor original)."
  trocar_timeout 10 3 >/dev/null
}

case "${1:-tudo}" in
  invoke) invoke ;;
  http) http ;;
  http-warm) http_warm ;;
  timeout) timeout3; timeout10 ;;
  timeout3) timeout3 ;;
  timeout10) timeout10 ;;
  tudo) invoke; http; http_warm; timeout3; timeout10 ;;
  *) echo "uso: $0 {invoke|http|http-warm|timeout|timeout3|timeout10|tudo}"; exit 1 ;;
esac
