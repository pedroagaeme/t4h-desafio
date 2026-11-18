# Funções comuns da coleta de diagnóstico. Somente leitura, exceto 04 (ativa pg_stat_statements) e 06 (zera contadores e roda a carga).
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1
BASE=${BASE:-http://localhost:3000}
OUT=${OUT:-diagnostico/saidas/$(date +%Y%m%d-%H%M%S)-coleta}
mkdir -p "$OUT"
sql() { docker compose exec -T banco psql -U loja -d loja -X -P pager=off "$@"; }
cpu() { docker compose exec -T "$1" cat /sys/fs/cgroup/cpu.stat | awk '$1=="usage_usec"{print $2}'; }
saida() { tee "$OUT/$(basename "$0" .sh).txt"; }
esperar_api() { for _ in $(seq 40); do [ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/clientes/1")" = 200 ] && return 0; sleep 2; done; return 1; }
docker compose ps --status running --services 2>/dev/null | grep -qx banco || { echo "ERRO: o serviço banco não está rodando (docker compose up -d --build)"; exit 1; }
