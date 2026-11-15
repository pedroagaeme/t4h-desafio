#!/usr/bin/env bash
# Mede quanto leva conectar, consultar e fechar uma conexão do pg, de dentro do container da API,
# em duas fases: sistema ocioso e sob a MESMA carga do scripts/medir.sh.
#
#   diagnostico/scripts/conexoes-sob-carga.sh <rotulo>
#   JANELA_S=30 ESPERA_S=10 PAUSA_MS=100 diagnostico/scripts/conexoes-sob-carga.sh conexoes-baseline
#
# DURACAO da carga (padrão 60s) precisa ser maior que ESPERA_S + JANELA_S.
# Diagnóstico: não escreve em resultados/. Commite diagnostico/saidas/ antes de rodar o medir.sh de verdade.
#
# Saída: diagnostico/saidas/<data>-<rotulo>/
#   conexoes.csv  fase,connect_ms,query_ms,end_ms (uma linha por conexão)
#   resumo.txt    contagem, mínimo e máximo por fase, e CPU do banco por conexão na fase ociosa
# A mediana de cada fase fica para você calcular a mão a partir do conexoes.csv.

set -euo pipefail
cd "$(dirname "$0")/../.."

ROTULO="${1:-}"
if [[ -z "$ROTULO" || ! "$ROTULO" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "uso: diagnostico/scripts/conexoes-sob-carga.sh <rotulo>" >&2
  exit 2
fi

VUS="${VUS:-20}"
DURACAO="${DURACAO:-60s}"
AQUECIMENTO="${AQUECIMENTO:-15s}"
SEMENTE="${SEMENTE:-42}"
JANELA_S="${JANELA_S:-30}"
ESPERA_S="${ESPERA_S:-10}"
PAUSA_MS="${PAUSA_MS:-100}"
PORTA_API="${PORTA_API:-3000}"
USUARIO="$(id -u):$(id -g)"
CG=/sys/fs/cgroup

if ! curl -fsS "http://127.0.0.1:${PORTA_API}/saude" >/dev/null 2>&1; then
  echo "A API não respondeu em http://127.0.0.1:${PORTA_API}/saude. Suba tudo com: docker compose up -d --build" >&2
  exit 1
fi

SAIDA="diagnostico/saidas/$(date +%Y%m%d-%H%M%S)-${ROTULO}"
mkdir -p "$SAIDA"
echo "fase,connect_ms,query_ms,end_ms" > "$SAIDA/conexoes.csv"

JS=$(cat <<'JS_FIM'
const { Client } = require('pg');
const fase = process.env.FASE;
const fim = Date.now() + Number(process.env.SEGUNDOS) * 1000;
const pausa = Number(process.env.PAUSA_MS);
const ms = (a, b) => (Number(b - a) / 1e6).toFixed(1);
(async () => {
  while (Date.now() < fim) {
    const c = new Client({ host: process.env.DB_HOST, port: Number(process.env.DB_PORT), user: process.env.DB_USER, database: process.env.DB_NAME });
    const t0 = process.hrtime.bigint();
    await c.connect();
    const t1 = process.hrtime.bigint();
    await c.query('select 1');
    const t2 = process.hrtime.bigint();
    await c.end();
    const t3 = process.hrtime.bigint();
    console.log(`${fase},${ms(t0, t1)},${ms(t1, t2)},${ms(t2, t3)}`);
    await new Promise((r) => setTimeout(r, pausa));
  }
})();
JS_FIM
)

medir_fase() {
  docker compose exec -T -e FASE="$1" -e SEGUNDOS="$JANELA_S" -e PAUSA_MS="$PAUSA_MS" api node -e "$JS" >> "$SAIDA/conexoes.csv"
}

cpu_banco() {  # imprime usage_usec do banco
  docker compose exec -T banco cat "$CG/cpu.stat" | awk '$1 == "usage_usec" { print $2 }'
}

{
  echo "rotulo: ${ROTULO}"
  echo "data: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "vus: ${VUS} duracao: ${DURACAO} aquecimento: ${AQUECIMENTO} semente: ${SEMENTE}"
  echo "janela_s: ${JANELA_S} espera_s: ${ESPERA_S} pausa_ms: ${PAUSA_MS}"
  echo "commit: $(git rev-parse --short HEAD 2>/dev/null || echo sem-commit)"
} > "$SAIDA/resumo.txt"

echo "Aquecendo por ${AQUECIMENTO} (igual ao medir.sh)..."
docker compose run --rm --user "$USUARIO" -e VUS=5 -e DURACAO="$AQUECIMENTO" -e SEMENTE="$((SEMENTE + 1))" \
  carga run --quiet --no-summary /carga/teste-carga.js >/dev/null
sleep 5

echo "Fase ociosa: ${JANELA_S}s..."
CPU_ANTES="$(cpu_banco)"
medir_fase ocioso
CPU_DEPOIS="$(cpu_banco)"

echo "Fase sob carga: iniciando k6 (${VUS} VUs, ${DURACAO}), medindo depois de ${ESPERA_S}s..."
docker compose run --rm --user "$USUARIO" -e VUS="$VUS" -e DURACAO="$DURACAO" -e SEMENTE="$SEMENTE" \
  carga run --quiet --no-summary /carga/teste-carga.js >/dev/null &
K6=$!
sleep "$ESPERA_S"
medir_fase carga
wait "$K6" || true

{
  echo
  awk -F, 'NR > 1 {
    n[$1]++
    if (!($1 in cmin) || $2 < cmin[$1]) cmin[$1] = $2
    if ($2 > cmax[$1]) cmax[$1] = $2
    if (!($1 in qmin) || $3 < qmin[$1]) qmin[$1] = $3
    if ($3 > qmax[$1]) qmax[$1] = $3
  } END {
    for (f in n) printf "%-7s conexões=%d connect min=%s max=%s ms | query min=%s max=%s ms\n", f, n[f], cmin[f], cmax[f], qmin[f], qmax[f]
  }' "$SAIDA/conexoes.csv"
  N_OCIOSO="$(awk -F, '$1 == "ocioso"' "$SAIDA/conexoes.csv" | wc -l | tr -d ' ')"
  echo
  echo "CPU do banco na fase ociosa: delta usage_usec = $((CPU_DEPOIS - CPU_ANTES)) µs em ${N_OCIOSO} conexões (inclui ruído de fundo do Postgres)"
  echo "Para a mediana: sort -t, -k2 -n diagnostico/saidas/<pasta>/conexoes.csv (filtre a fase com grep)"
} | tee -a "$SAIDA/resumo.txt"

echo
echo "Saída salva em $SAIDA/ (nada foi criado em resultados/)"
