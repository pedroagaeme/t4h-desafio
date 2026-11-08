#!/usr/bin/env bash
# Descobre quais comandos SQL concentram o tempo do banco sob a MESMA carga do scripts/medir.sh,
# usando o pg_stat_statements, sem chamar o medir.sh e sem criar nada em resultados/.
#
#   diagnostico/scripts/pgss-sob-carga.sh <rotulo>
#   TOPN=15 VUS=20 DURACAO=60s diagnostico/scripts/pgss-sob-carga.sh pgss-baseline
#
# O que faz, em ordem:
#   1. confere que o pg_stat_statements está carregado e criado (senão explica o que falta e para);
#   2. roda diagnostico/scripts/use-sob-carga.sh (mesma carga, aquecimento incluído). Logo após o aquecimento e
#      antes da leitura, zera os contadores do pg_stat_statements, então só a carga medida entra no ranking;
#   3. grava o ranking na mesma pasta de saída da carga.
#
# Pré-requisitos (feitos uma vez):
#   export COMPOSE_FILE=docker-compose.yml:diagnostico/pgss.yml
#   docker compose up -d banco && docker compose restart api
#   docker compose exec banco psql -U loja -d loja -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
#
# Saída: diagnostico/saidas/<data>-<rotulo>/  (a mesma pasta do use-sob-carga.sh)
#   pgss-top.txt       os TOPN comandos por tempo total, com % do tempo, chamadas, blocos lidos/escritos
#   pgss-todos.csv     todos os comandos registrados
#   pgss-contexto.txt  versão, configuração do Postgres, quando os contadores foram zerados
#   (mais matriz-use.txt, k6-resumo.txt etc., gerados pelo use-sob-carga.sh)
#
# Como ler: total_ms é tempo DECORRIDO (não CPU). Sob throttling ele infla, então use para ordenar
# e comparar proporções, não como parcela exata de CPU. É diagnóstico: nunca use como antes/depois.
# O pg_stat_statements acrescenta custo ao banco; para medições oficiais rode sem ele (unset COMPOSE_FILE).

set -euo pipefail
cd "$(dirname "$0")/../.."

ROTULO="${1:-}"
if [[ -z "$ROTULO" || ! "$ROTULO" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "uso: diagnostico/scripts/pgss-sob-carga.sh <rotulo>   (letras, números, ponto, hífen ou sublinhado)" >&2
  exit 2
fi

TOPN="${TOPN:-10}"
if [[ ! "$TOPN" =~ ^[0-9]+$ || "$TOPN" -lt 1 ]]; then
  echo "TOPN precisa ser um inteiro positivo." >&2
  exit 2
fi

CARGA=diagnostico/scripts/use-sob-carga.sh
if [[ ! -x "$CARGA" ]]; then
  echo "Não encontrei $CARGA (ou não é executável). Rode: chmod +x $CARGA" >&2
  exit 1
fi
if ! grep -q 'PGSS_RESET' "$CARGA"; then
  echo "O $CARGA está numa versão antiga, sem a opção PGSS_RESET. Atualize-o antes de continuar." >&2
  exit 1
fi

psql_banco() {
  docker compose exec -T banco psql -U loja -d loja -X -q -v ON_ERROR_STOP=1 "$@"
}

# 1) Pré-requisitos
if [[ -z "$(docker compose ps -q banco 2>/dev/null)" ]]; then
  echo "O serviço 'banco' não está rodando. Suba com: docker compose up -d" >&2
  exit 1
fi

PRELOAD="$(psql_banco -At -c 'SHOW shared_preload_libraries;' 2>/dev/null || true)"
if [[ "$PRELOAD" != *pg_stat_statements* ]]; then
  cat >&2 <<EOF
O pg_stat_statements não está em shared_preload_libraries (valor atual: '${PRELOAD}').
Falta carregar o override e recriar o banco:
  export COMPOSE_FILE=docker-compose.yml:diagnostico/pgss.yml
  docker compose up -d banco && docker compose restart api
Aguarde o banco ficar saudável e rode este script de novo.
EOF
  exit 1
fi

if ! psql_banco -At -c 'SELECT count(*) FROM pg_stat_statements;' >/dev/null 2>&1; then
  cat >&2 <<EOF
A biblioteca está carregada, mas a extensão não foi criada no banco 'loja'. Crie com:
  docker compose exec banco psql -U loja -d loja -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
EOF
  exit 1
fi

# 2) Carga, zerando os contadores depois do aquecimento (opção PGSS_RESET do use-sob-carga.sh)
export PGSS_RESET=1

STATUS=0
"$CARGA" "$ROTULO" || STATUS=$?

# Pasta que o use-sob-carga.sh acabou de criar (a mais recente com este rótulo).
SAIDA="$(ls -dt diagnostico/saidas/*-"${ROTULO}" 2>/dev/null | head -1 || true)"
if [[ -z "$SAIDA" || ! -d "$SAIDA" ]]; then
  echo "Não encontrei a pasta de saída de '${ROTULO}' em diagnostico/saidas/." >&2
  exit 1
fi

# 3) Ranking
{
  echo "rotulo: ${ROTULO}"
  echo "data: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "COMPOSE_FILE: ${COMPOSE_FILE:-<não definido>}"
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "commit: $(git rev-parse --short HEAD 2>/dev/null || echo sem-commit)"
  fi
  echo "versão: $(psql_banco -At -c 'SELECT version();')"
  echo
  echo "configuração do Postgres:"
  for p in shared_preload_libraries shared_buffers max_parallel_workers_per_gather work_mem effective_cache_size max_connections \
           pg_stat_statements.track pg_stat_statements.max; do
    echo "  ${p} = $(psql_banco -At -c "SELECT current_setting('${p}');")"
  done
  echo
  echo "pg_stat_statements_info (stats_reset deve ser logo após o aquecimento; dealloc > 0 significa comandos perdidos):"
  psql_banco -P pager=off -c 'SELECT dealloc, stats_reset FROM pg_stat_statements_info;'
} > "$SAIDA/pgss-contexto.txt"

{
  echo "Top ${TOPN} comandos por tempo total de execução (tempo decorrido, não CPU). Rótulo: ${ROTULO}"
  echo "pct_tempo = parcela do tempo total de todos os comandos registrados (exceto consultas ao próprio pg_stat_statements)."
  echo
  psql_banco -P pager=off -v topn="$TOPN" <<'SQL'
SELECT queryid,
       calls,
       round(total_exec_time)::bigint AS total_ms,
       round((100 * total_exec_time / NULLIF(sum(total_exec_time) OVER (), 0))::numeric, 1) AS pct_tempo,
       round(mean_exec_time::numeric, 2) AS mean_ms,
       rows,
       shared_blks_hit,
       shared_blks_read,
       shared_blks_dirtied,
       shared_blks_written,
       temp_blks_written,
       left(regexp_replace(query, '\s+', ' ', 'g'), 90) AS query
FROM pg_stat_statements
WHERE query NOT ILIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC
LIMIT :topn;
SQL
} | tee "$SAIDA/pgss-top.txt"

psql_banco <<'SQL' > "$SAIDA/pgss-todos.csv"
COPY (
  SELECT queryid, calls, round(total_exec_time)::bigint AS total_ms, round(mean_exec_time::numeric, 3) AS mean_ms, rows,
         shared_blks_hit, shared_blks_read, shared_blks_dirtied, shared_blks_written, temp_blks_written,
         regexp_replace(query, '\s+', ' ', 'g') AS query
  FROM pg_stat_statements
  WHERE query NOT ILIKE '%pg_stat_statements%'
  ORDER BY total_exec_time DESC
) TO STDOUT WITH CSV HEADER;
SQL

echo
echo "Saída salva em $SAIDA/ (nada foi criado em resultados/)"
exit "$STATUS"