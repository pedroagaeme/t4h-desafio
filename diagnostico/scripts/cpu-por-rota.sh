#!/usr/bin/env bash
# diagnostico/scripts/cpu-por-rota.sh <rotulo>
#
# Pergunta que responde: quanto de CPU do banco (e da API) cada rota consome por requisição,
# sem carga concorrente. O pg_stat_statements mede tempo decorrido (inclui espera por CPU);
# este script lê o contador de CPU usada do cgroup (cpu.stat, usage_usec).
#
# Como funciona:
#   1. Controle: com tudo ocioso, mede a CPU de fundo do banco e da API por CONTROLE_S segundos.
#   2. Para cada rota: 3 requisições de aquecimento, lê cpu.stat, faz N requisições em sequência
#      (uma de cada vez), lê cpu.stat de novo. CPU por requisição = (delta - fundo no mesmo
#      tempo) / N.
#   3. Combina com os pesos do k6 (cliente 25, cliente-por-email 15, pedidos-do-cliente 20,
#      pedidos-por-status 15, busca-produtos 15, vendas-por-dia 8, top-produtos 2) e estima
#      quantas requisições/s 1 CPU do banco sustentaria nesse mix.
#
# Antes de rodar: tudo no ar (docker compose up -d --build), nenhum k6 rodando, e nada
# sem commit fora de diagnostico/saidas (veja o contexto.txt gerado).
# Saída: diagnostico/saidas/<data>-<rotulo>/  (cpu-por-rota.csv, resumo.txt, contexto.txt)
# Rode 2 ou 3 vezes, com rótulos diferentes (cpu-por-rota-1, -2, -3).
# Não grava nada no banco e não altera configuração.

set -euo pipefail

ROTULO="${1:-}"
if [[ -z "$ROTULO" || ! "$ROTULO" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "uso: diagnostico/scripts/cpu-por-rota.sh <rotulo>" >&2
  exit 2
fi

N="${N:-30}"
CONTROLE_S="${CONTROLE_S:-20}"
PORTA_API="${PORTA_API:-3000}"
URL="http://127.0.0.1:${PORTA_API}"
CG=/sys/fs/cgroup

# nome|peso no k6|caminho   (peso 0 = só para comparar, fora do mix)
ROTAS=(
  "cliente|25|/clientes/42"
  "cliente-por-email|15|/clientes?email=cliente42%40exemplo.com"
  "pedidos-do-cliente|20|/clientes/42/pedidos"
  "pedidos-por-status-entregue-p500|15|/pedidos?status=entregue&pagina=500"
  "busca-produtos-cadeira|15|/produtos/busca?q=cadeira"
  "vendas-por-dia|8|/relatorios/vendas-por-dia?inicio=2024-03-01&fim=2024-03-07"
  "top-produtos|2|/relatorios/top-produtos?limite=10"
  "pedidos-por-status-pago-p1|0|/pedidos?status=pago&pagina=1"
  "pedidos-por-status-pago-p1000|0|/pedidos?status=pago&pagina=1000"
)

if [[ ! "$N" =~ ^[0-9]+$ || "$N" -lt 1 || ! "$CONTROLE_S" =~ ^[0-9]+$ ]]; then
  echo "N e CONTROLE_S precisam ser números inteiros (N >= 1)." >&2
  exit 2
fi

if ! curl -fsS "$URL/saude" >/dev/null 2>&1; then
  echo "A API não respondeu em $URL/saude. Suba tudo com: docker compose up -d --build" >&2
  exit 1
fi

if docker compose ps --status running --services 2>/dev/null | grep -qx carga; then
  echo "O container 'carga' (k6) está rodando. Espere terminar: ele mudaria a medida." >&2
  exit 1
fi

# CPU acumulada (µs) de um serviço, lida do cgroup do container.
usage() {
  docker compose exec -T "$1" sh -c "awk '\$1==\"usage_usec\" {print \$2}' $CG/cpu.stat"
}

agora_ms() {
  local t
  t="$(date +%s%N)"
  if [[ "$t" == *N* ]]; then t="$(( $(date +%s) * 1000000000 ))"; fi
  echo "$(( t / 1000000 ))"
}

SAIDA="diagnostico/saidas/$(date +%Y%m%d-%H%M%S)-${ROTULO}"
mkdir -p "$SAIDA"

{
  echo "rotulo: $ROTULO"
  echo "data: $(date -Is)"
  echo "commit: $(git rev-parse --short HEAD 2>/dev/null || echo nd)"
  echo "arquivos alterados sem commit: $(git status --porcelain -- . ':(exclude)resultados' ':(exclude)diagnostico/saidas' | wc -l | tr -d ' ')"
  echo "N por rota: $N   controle: ${CONTROLE_S}s"
} > "$SAIDA/contexto.txt"

# 1. Controle: CPU de fundo (µs por ms de relógio) com tudo ocioso.
echo "Controle ocioso por ${CONTROLE_S}s..."
sleep 5
b0="$(usage banco)"; a0="$(usage api)"; t0="$(agora_ms)"
sleep "$CONTROLE_S"
b1="$(usage banco)"; a1="$(usage api)"; t1="$(agora_ms)"
FUNDO_BANCO="$(awk -v d="$((b1 - b0))" -v t="$((t1 - t0))" 'BEGIN { printf "%.6f", d / t }')"   # µs por ms
FUNDO_API="$(awk -v d="$((a1 - a0))" -v t="$((t1 - t0))" 'BEGIN { printf "%.6f", d / t }')"
echo "fundo banco: $FUNDO_BANCO µs/ms   fundo api: $FUNDO_API µs/ms" | tee -a "$SAIDA/contexto.txt"

echo "rota,peso,n,tempo_ms_por_req,banco_ms_por_req,api_ms_por_req,parcela_banco" > "$SAIDA/cpu-por-rota.csv"

# 2. Por rota.
for item in "${ROTAS[@]}"; do
  IFS='|' read -r nome peso caminho <<< "$item"
  echo "Rota $nome..."
  for _ in 1 2 3; do curl -fsS -o /dev/null "$URL$caminho"; done
  sleep 2
  b0="$(usage banco)"; a0="$(usage api)"; t0="$(agora_ms)"
  for ((i = 0; i < N; i++)); do curl -fsS -o /dev/null "$URL$caminho"; done
  t1="$(agora_ms)"; b1="$(usage banco)"; a1="$(usage api)"
  awk -v nome="$nome" -v peso="$peso" -v n="$N" \
      -v db="$((b1 - b0))" -v da="$((a1 - a0))" -v t="$((t1 - t0))" \
      -v fb="$FUNDO_BANCO" -v fa="$FUNDO_API" 'BEGIN {
        banco = (db - fb * t) / n / 1000; api = (da - fa * t) / n / 1000
        if (banco < 0) banco = 0; if (api < 0) api = 0
        parcela = (banco + api > 0) ? banco / (banco + api) : 0
        printf "%s,%s,%d,%.1f,%.2f,%.2f,%.3f\n", nome, peso, n, t / n, banco, api, parcela }' \
    >> "$SAIDA/cpu-por-rota.csv"
done

# 3. Resumo legível + mix.
awk -F, -v fb="$FUNDO_BANCO" -v fa="$FUNDO_API" 'NR == 1 { next }
  {
    nome[NR] = $1; peso[NR] = $2; t[NR] = $4; b[NR] = $5; a[NR] = $6; p[NR] = $7
    if ($2 > 0) { sp += $2; sb += $2 * $5; sa += $2 * $6 }
    ordem[NR] = NR
  }
  END {
    print "CPU consumida por requisição (ms de CPU), uma requisição por vez, sem carga concorrente"
    printf "%-34s %5s %12s %10s %9s %14s\n", "rota", "peso", "tempo(ms)", "banco(ms)", "api(ms)", "parcela banco"
    for (i = 2; i <= NR; i++)
      printf "%-34s %5s %12.1f %10.2f %9.2f %13.0f%%\n", nome[i], peso[i], t[i], b[i], a[i], p[i] * 100
    print ""
    printf "Mix do k6 (pesos > 0): banco %.2f ms de CPU por requisição, api %.2f ms\n", sb / sp, sa / sp
    if (sb > 0) printf "Requisições/s que 1 CPU do banco sustentaria nesse mix: %.1f\n", 1000 / (sb / sp)
    print ""
    print "Parcela do banco por rota dentro do mix (peso x CPU do banco):"
    for (i = 2; i <= NR; i++) if (peso[i] > 0)
      printf "  %-34s %5.1f%%\n", nome[i], 100 * peso[i] * b[i] / sb
    print ""
    printf "CPU de fundo (controle): banco %.4f CPU, api %.4f CPU\n", fb / 1000, fa / 1000
    print "Limites: 30 requisições por rota, sequenciais; o docker exec de cada leitura soma um"
    print "custo pequeno e fixo ao delta; o k6 mistura rotas em paralelo (o cache e as esperas mudam)."
  }' "$SAIDA/cpu-por-rota.csv" > "$SAIDA/resumo.txt"

echo
cat "$SAIDA/resumo.txt"
echo
echo "Saída em: $SAIDA"