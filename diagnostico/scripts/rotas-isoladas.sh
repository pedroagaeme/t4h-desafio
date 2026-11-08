#!/usr/bin/env bash
# Diagnóstico por rota, SEM carga:
#   Parte 1: mede cada rota sozinha com curl (várias repetições) e resume os tempos.
#   Parte 2: captura o plano de execução (EXPLAIN ANALYZE, BUFFERS) de cada consulta que a rota REALMENTE
#            executa, e conta quantas consultas cada requisição dispara.
#
#   diagnostico/scripts/rotas-isoladas.sh [rotulo]
#   REPS=10 diagnostico/scripts/rotas-isoladas.sh        # mais repetições por rota (padrão 5)
#   PLANOS=0 diagnostico/scripts/rotas-isoladas.sh       # só os tempos (parte 1)
#   diagnostico/scripts/rotas-isoladas.sh --limpar       # desfaz a configuração de diagnóstico, se um run foi interrompido
#
# Como a parte 2 descobre as consultas sem você precisar copiá-las: liga o módulo auto_explain do Postgres
# (e o log de duração de cada comando) só para o banco "loja", reinicia a API para que suas conexões peguem a
# configuração, chama cada rota duas vezes e guarda o trecho do log do banco de cada chamada.
# No fim o script SEMPRE desfaz isso e reinicia a API de novo (inclusive com Ctrl+C).
#
# Cuidados:
#  - Rode com o sistema ocioso, sem medir.sh nem recursos-sob-carga.sh em andamento. O script recusa rodar se o
#    banco estiver ocupado (FORCAR=1 ignora).
#  - Os tempos da parte 1 são medidos ANTES de ligar o auto_explain, para não serem afetados por ele. Já as durações
#    dentro dos planos (parte 2) incluem o custo do ANALYZE: use-as para ver o FORMATO (varreduras, linhas lidas,
#    buffers), não para comparar com o curl.
#  - A configuração temporária fica no banco (ALTER DATABASE) e a API é reiniciada duas vezes. Isso só diagnostica;
#    nada aqui é resultado de antes/depois. Se quiser garantir um estado limpo antes de uma medição oficial:
#    docker compose down -v && docker compose up -d --build
#  - O contexto.txt do medir.sh conta arquivos novos fora de resultados/ como "alterados sem commit". Commite (ou apague)
#    diagnostico/saidas/ antes de rodar o medir.sh de verdade.
#
# Saída: diagnostico/saidas/<data>-<rotulo>/
#   tempos.csv, tempos-resumo.txt       parte 1
#   planos/<rota>-chamada<1|2>.log      trecho do log do banco de cada chamada (consultas, parâmetros, planos)
#   consultas-por-requisicao.txt        quantas consultas cada chamada executou e quanto tempo gastou no banco
#   contexto.txt                        parâmetros, commit e rotas usadas

set -euo pipefail
cd "$(dirname "$0")/../.."

PORTA_API="${PORTA_API:-3000}"
REPS="${REPS:-5}"
MAX_TEMPO="${MAX_TEMPO:-120}"
PLANOS="${PLANOS:-1}"
FORCAR="${FORCAR:-0}"
URL_BASE="http://127.0.0.1:${PORTA_API}"

# nome|caminho. Edite à vontade (nomes únicos, sem espaços). As variações de pedidos-por-status testam se o custo
# depende da página e do status, já que a carga sorteia páginas de 1 a 1000.
ROTAS=(
  "cliente|/clientes/42"
  "cliente-por-email|/clientes?email=cliente42%40exemplo.com"
  "pedidos-do-cliente|/clientes/42/pedidos"
  "pedidos-por-status-pago-p1|/pedidos?status=pago&pagina=1"
  "pedidos-por-status-pago-p1000|/pedidos?status=pago&pagina=1000"
  "pedidos-por-status-cancelado-p500|/pedidos?status=cancelado&pagina=500"
  "busca-produtos-cadeira|/produtos/busca?q=cadeira"
  "busca-produtos-lumin|/produtos/busca?q=lumin"
  "vendas-por-dia|/relatorios/vendas-por-dia?inicio=2024-03-01&fim=2024-03-07"
  "top-produtos|/relatorios/top-produtos?limite=10"
)

esperar_api() {
  local i
  for i in $(seq 1 60); do
    if curl -fsS "$URL_BASE/saude" >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  return 1
}

desfazer_diagnostico() {
  docker compose exec -T banco psql -U loja -d loja -q >/dev/null 2>&1 <<'SQL' || true
ALTER DATABASE loja RESET session_preload_libraries;
ALTER DATABASE loja RESET auto_explain.log_min_duration;
ALTER DATABASE loja RESET auto_explain.log_analyze;
ALTER DATABASE loja RESET auto_explain.log_buffers;
ALTER DATABASE loja RESET auto_explain.log_timing;
ALTER DATABASE loja RESET auto_explain.log_nested_statements;
ALTER DATABASE loja RESET log_min_duration_statement;
SQL
}

if [[ "${1:-}" == "--limpar" ]]; then
  desfazer_diagnostico
  docker compose restart api >/dev/null 2>&1 || true
  esperar_api || echo "AVISO: a API não voltou a responder. Confira com: docker compose ps" >&2
  echo "Configuração de diagnóstico removida do banco e API reiniciada."
  exit 0
fi

ROTULO="${1:-rotas-isoladas}"
if [[ ! "$ROTULO" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "uso: diagnostico/scripts/rotas-isoladas.sh [rotulo]   (letras, números, ponto, hífen ou sublinhado)" >&2
  exit 2
fi
for v in REPS MAX_TEMPO; do
  if [[ ! "${!v}" =~ ^[0-9]+$ || "${!v}" -lt 1 ]]; then
    echo "$v precisa ser um número inteiro maior que zero." >&2
    exit 2
  fi
done

if ! curl -fsS "$URL_BASE/saude" >/dev/null 2>&1; then
  echo "A API não respondeu em $URL_BASE/saude. Suba tudo com: docker compose up -d --build" >&2
  exit 1
fi

# O sistema precisa estar ocioso: um teste de carga em andamento invalidaria os tempos.
CPU_BANCO="$(docker stats --no-stream --format '{{.CPUPerc}}' "$(docker compose ps -q banco)" 2>/dev/null | tr -d '%' | head -1 || true)"
if [[ "$FORCAR" != "1" ]] && awk -v c="${CPU_BANCO:-0}" 'BEGIN { exit !(c > 20) }'; then
  echo "O banco está usando ${CPU_BANCO}% de CPU: há algo rodando (um teste de carga?). Espere ficar ocioso ou use FORCAR=1." >&2
  exit 1
fi

SAIDA="diagnostico/saidas/$(date +%Y%m%d-%H%M%S)-${ROTULO}"
mkdir -p "$SAIDA/planos"

{
  echo "rotulo: ${ROTULO}"
  echo "data: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "repeticoes por rota: ${REPS}"
  echo "planos (parte 2): ${PLANOS}"
  echo "cpu do banco ao começar: ${CPU_BANCO:-?}%"
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "commit: $(git rev-parse --short HEAD 2>/dev/null || echo sem-commit)"
    echo "arquivos alterados sem commit: $(git status --porcelain -- . ':(exclude)resultados' ':(exclude)diagnostico/saidas' | wc -l | tr -d ' ')"
  fi
  echo
  echo "rotas:"
  for entrada in "${ROTAS[@]}"; do echo "  ${entrada%%|*}  ${entrada#*|}"; done
} > "$SAIDA/contexto.txt"

# ---------------------------------------------------------------- Parte 1: tempos de cada rota, sozinha
echo "Parte 1: tempo de cada rota sozinha (${REPS} repetições)..."
echo "rota,url,repeticao,http,tempo_total_s,bytes" > "$SAIDA/tempos.csv"
for entrada in "${ROTAS[@]}"; do
  nome="${entrada%%|*}"; caminho="${entrada#*|}"
  for rep in $(seq 1 "$REPS"); do
    medida="$(curl -s -o /dev/null --max-time "$MAX_TEMPO" -w '%{http_code},%{time_total},%{size_download}' "$URL_BASE$caminho" || echo '000,0,0')"
    echo "${nome},${caminho//,/;},${rep},${medida}" >> "$SAIDA/tempos.csv"
  done
  echo "  ${nome}: ok"
done

awk -F, '
  function mediana(r, cnt,   i, j, t, x) {
    for (i = 1; i <= cnt; i++) x[i] = v[r, i]
    for (i = 2; i <= cnt; i++) { t = x[i]; for (j = i - 1; j >= 1 && x[j] > t; j--) x[j + 1] = x[j]; x[j + 1] = t }
    return (cnt % 2) ? x[(cnt + 1) / 2] : (x[cnt / 2] + x[cnt / 2 + 1]) / 2
  }
  NR > 1 {
    r = $1; n[r]++; t = $5 * 1000
    if (!(r in ordem)) { ordem[r] = ++k; nome[k] = r }
    if (n[r] == 1) prim[r] = t
    else { m[r]++; v[r, m[r]] = t; if (m[r] == 1 || t < mn[r]) mn[r] = t; if (t > mx[r]) mx[r] = t }
    if ($4 != 200) ruim[r]++
  }
  END {
    printf "%-34s %12s %16s %10s %10s %8s\n", "rota", "1a_chamada", "mediana_demais", "min", "max", "nao_200"
    for (i = 1; i <= k; i++) {
      r = nome[i]
      if (m[r] > 0) printf "%-34s %9.1f ms %13.1f ms %7.1f ms %7.1f ms %8d\n", r, prim[r], mediana(r, m[r]), mn[r], mx[r], ruim[r]
      else          printf "%-34s %9.1f ms %16s %10s %10s %8d\n", r, prim[r], "-", "-", "-", ruim[r]
    }
    print ""
    print "1a_chamada pode incluir cache frio; mediana_demais/min/max usam as repetições seguintes."
  }
' "$SAIDA/tempos.csv" > "$SAIDA/tempos-resumo.txt"

echo
cat "$SAIDA/tempos-resumo.txt"

if [[ "$PLANOS" != "1" ]]; then
  echo
  echo "Saída salva em $SAIDA/ (parte 2 pulada: PLANOS=0)"
  exit 0
fi

# ---------------------------------------------------------------- Parte 2: consultas e planos reais
echo
echo "Parte 2: consultas e planos de execução de cada rota..."

if ! docker compose exec -T banco sh -c 'ls /usr/lib/postgresql/*/lib/auto_explain.so' >/dev/null 2>&1; then
  echo "AVISO: não achei o módulo auto_explain na imagem do banco. Pulando a parte 2." >&2
  echo "Saída salva em $SAIDA/"
  exit 0
fi

DIAGNOSTICO_LIGADO=0
encerrar() {
  if [[ "$DIAGNOSTICO_LIGADO" == 1 ]]; then
    echo
    echo "Desfazendo a configuração de diagnóstico do banco e reiniciando a API..."
    desfazer_diagnostico
    docker compose restart api >/dev/null 2>&1 || true
    esperar_api || echo "AVISO: a API não voltou a responder. Confira com: docker compose ps" >&2
    DIAGNOSTICO_LIGADO=0
  fi
}
trap encerrar EXIT
trap 'exit 130' INT TERM

DIAGNOSTICO_LIGADO=1
docker compose exec -T banco psql -U loja -d loja -q -v ON_ERROR_STOP=1 <<'SQL'
ALTER DATABASE loja SET session_preload_libraries = 'auto_explain';
ALTER DATABASE loja SET auto_explain.log_min_duration = 0;
ALTER DATABASE loja SET auto_explain.log_analyze = on;
ALTER DATABASE loja SET auto_explain.log_buffers = on;
ALTER DATABASE loja SET auto_explain.log_timing = on;
ALTER DATABASE loja SET auto_explain.log_nested_statements = on;
ALTER DATABASE loja SET log_min_duration_statement = 0;
SQL

# A API reinicia para abrir conexões novas, que já nascem com a configuração.
docker compose restart api >/dev/null
esperar_api || { echo "A API não voltou a responder depois do reinício." >&2; exit 1; }

contar_linhas_log() { docker compose logs --no-color --no-log-prefix banco 2>&1 | wc -l | tr -d ' '; }

resumir_trecho() {
  awk '
    /duration: [0-9.]+ ms +(execute [^:]*|statement):/ { split($0, a, "duration: "); split(a[2], b, " ms"); soma += b[1]; n++ }
    /duration: [0-9.]+ ms +plan:/ { p++ }
    END { printf "%d %.1f %d\n", n, soma, p }
  ' "$1"
}

printf '%-34s %8s %14s %16s %10s\n' rota chamada sql_executados soma_ms_no_banco planos > "$SAIDA/consultas-por-requisicao.txt"
TOTAL_PLANOS=0
for entrada in "${ROTAS[@]}"; do
  nome="${entrada%%|*}"; caminho="${entrada#*|}"
  for k in 1 2; do
    n0="$(contar_linhas_log)"
    curl -s -o /dev/null --max-time "$MAX_TEMPO" "$URL_BASE$caminho" || true
    sleep 1
    docker compose logs --no-color --no-log-prefix banco 2>&1 | tail -n +"$((n0 + 1))" > "$SAIDA/planos/${nome}-chamada${k}.log"
    read -r nsql soma nplanos < <(resumir_trecho "$SAIDA/planos/${nome}-chamada${k}.log")
    printf '%-34s %8s %14s %16s %10s\n' "$nome" "$k" "$nsql" "$soma" "$nplanos" >> "$SAIDA/consultas-por-requisicao.txt"
    TOTAL_PLANOS=$((TOTAL_PLANOS + nplanos))
  done
  echo "  ${nome}: ok"
done

{
  echo
  echo "sql_executados = consultas que a requisição disparou no banco; soma_ms_no_banco = soma das durações delas"
  echo "(com o custo do ANALYZE). chamada 1 = cache possivelmente frio; chamada 2 = mais quente."
  echo "No log: procure Seq Scan, 'Rows Removed by Filter', 'Buffers: shared read', 'Sort Method: external merge'."
} >> "$SAIDA/consultas-por-requisicao.txt"

echo
cat "$SAIDA/consultas-por-requisicao.txt"

if [[ "$TOTAL_PLANOS" -eq 0 ]]; then
  echo
  echo "AVISO: nenhum plano foi registrado. Veja em $SAIDA/planos/ se há linhas 'duration:' (consultas) sem 'plan:'." >&2
  echo "Causas prováveis: o auto_explain não carregou nas conexões da API, ou o Postgres da imagem não aceitou a configuração." >&2
fi

echo
echo "Saída salva em $SAIDA/"