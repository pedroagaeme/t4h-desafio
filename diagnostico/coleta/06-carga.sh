# Zera contadores, roda scripts/medir.sh (rótulo diagnostico-carga) e amostra conexões ativas e cgroups. Não é medição de experimento.
source "$(dirname "$0")/lib.sh"
{
  sql -c "SELECT pg_stat_statements_reset()" -c "SELECT pg_stat_reset()" >/dev/null
  for s in api banco; do docker compose exec -T $s cat /sys/fs/cgroup/cpu.stat > "$OUT/.antes-$s"; done
  docker compose exec -T banco cat /sys/fs/cgroup/memory.events > "$OUT/.antes-mem"
  ( for _ in $(seq 30); do sql -At -c "SELECT now()::time(0), count(*) FILTER (WHERE state='active'), count(*) FROM pg_stat_activity WHERE datname='loja' AND pid<>pg_backend_pid()"; sleep 2; done > "$OUT/.conexoes" ) &
  bash scripts/medir.sh diagnostico-carga
  wait
  echo "--- conexões (hora, ativas, total)"; cat "$OUT/.conexoes"
  for s in api banco; do
    docker compose exec -T $s cat /sys/fs/cgroup/cpu.stat > "$OUT/.depois-$s"
    echo "--- $s cpu.stat (delta, us)"; paste "$OUT/.antes-$s" "$OUT/.depois-$s" | awk '{print $1, $4-$2}'
    docker compose exec -T $s sh -c 'echo mem atual=$(cat /sys/fs/cgroup/memory.current) limite=$(cat /sys/fs/cgroup/memory.max)'
  done
  echo "--- banco memory.events (delta)"
  docker compose exec -T banco cat /sys/fs/cgroup/memory.events > "$OUT/.depois-mem"
  paste "$OUT/.antes-mem" "$OUT/.depois-mem" | awk '{print $1, $4-$2}'
} 2>&1 | saida
rm -f "$OUT"/.antes-* "$OUT"/.depois-* "$OUT"/.conexoes
