#!/usr/bin/env bash
# Mede o custo de um índice com o banco já populado e deixa o banco como estava.
# Mede: tamanho do índice, tempo de criação (3 repetições) e custo na escrita
# (100.000 linhas inseridas numa cópia da tabela, sem e com o índice, 3 repetições).
# Criação e escrita rodam dentro de transações desfeitas (ROLLBACK): nada muda no banco.
#
#   diagnostico/scripts/custo-indice.sh <rotulo> <indice> <tabela>
#   ex.: diagnostico/scripts/custo-indice.sh itens-pedido idx_itens_pedido_pedido_id itens_pedido
#
# Saída em diagnostico/saidas/<data>-custo-indice-<rotulo>/:
#   contexto.txt, tamanho.txt, criacao.txt, escrita.txt
# Rode sem carga (nada além do banco ocupado). Variável PSQL: comando psql a usar
# (padrão: o banco do docker compose).

set -euo pipefail
cd "$(dirname "$0")/../.."

ROTULO="${1:-}"
INDICE="${2:-}"
TABELA="${3:-}"
for v in "$ROTULO" "$INDICE" "$TABELA"; do
  if [[ ! "$v" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "uso: $0 <rotulo> <indice> <tabela>   (só letras, números, hífen e sublinhado)" >&2
    exit 2
  fi
done

PSQL="${PSQL:-docker compose exec -T banco psql -U loja -d loja -v ON_ERROR_STOP=1}"
SAIDA="diagnostico/saidas/$(date +%Y%m%d-%H%M%S)-custo-indice-${ROTULO}"
mkdir -p "$SAIDA"

DEF="$($PSQL -At -c "SELECT indexdef FROM pg_indexes WHERE indexname = '${INDICE}' AND tablename = '${TABELA}'")"
if [[ -z "$DEF" ]]; then
  echo "índice ${INDICE} não encontrado na tabela ${TABELA}." >&2
  exit 1
fi
# O mesmo índice, na cópia da tabela usada para medir a escrita.
DEF_COPIA="$(echo "$DEF" | sed -e "s/ INDEX ${INDICE} / INDEX idx_teste_escrita /" -e "s/ ON public\.${TABELA} / ON public.teste_escrita /")"

{
  echo "data: $(date -Iseconds)"
  echo "commit: $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD))"
  echo "arquivos sem commit: $(git status --short | wc -l)"
  echo "indice: ${INDICE} em ${TABELA}"
  echo "definicao: ${DEF}"
  $PSQL -At -c "SELECT version()"
} > "$SAIDA/contexto.txt"

$PSQL -c "SELECT pg_relation_size('${INDICE}') AS bytes,
                 pg_size_pretty(pg_relation_size('${INDICE}')) AS indice,
                 pg_size_pretty(pg_relation_size('${TABELA}')) AS tabela" > "$SAIDA/tamanho.txt"

# Criação: apaga e recria o índice na mesma transação e desfaz.
: > "$SAIDA/criacao.txt"
for i in 1 2 3; do
  echo "== repeticao ${i}" >> "$SAIDA/criacao.txt"
  {
    echo "BEGIN;"
    echo "DROP INDEX ${INDICE};"
    echo '\timing on'
    echo "${DEF};"
    echo '\timing off'
    echo "ROLLBACK;"
  } | $PSQL >> "$SAIDA/criacao.txt"
done

# Escrita: insere as mesmas 100.000 linhas numa cópia (só com a chave primária) e depois com o índice.
: > "$SAIDA/escrita.txt"
for i in 1 2 3; do
  echo "== repeticao ${i}" >> "$SAIDA/escrita.txt"
  {
    echo "BEGIN;"
    echo "CREATE TABLE teste_escrita (LIKE ${TABELA} INCLUDING DEFAULTS);"
    echo "ALTER TABLE teste_escrita ADD PRIMARY KEY (id);"
    echo '\echo sem o indice'
    echo '\timing on'
    echo "INSERT INTO teste_escrita SELECT * FROM ${TABELA} LIMIT 100000;"
    echo '\timing off'
    echo "TRUNCATE teste_escrita;"
    echo "${DEF_COPIA};"
    echo '\echo com o indice'
    echo '\timing on'
    echo "INSERT INTO teste_escrita SELECT * FROM ${TABELA} LIMIT 100000;"
    echo '\timing off'
    echo "ROLLBACK;"
  } | $PSQL >> "$SAIDA/escrita.txt"
done

echo "Resultado em ${SAIDA}"
echo "--- tamanho"; cat "$SAIDA/tamanho.txt"
echo "--- criação (ms)"; grep '^Time:' "$SAIDA/criacao.txt"
echo "--- escrita de 100.000 linhas (ms): sem o índice, depois com o índice, por repetição"
grep '^Time:' "$SAIDA/escrita.txt"