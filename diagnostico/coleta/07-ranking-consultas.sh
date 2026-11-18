# Rodar logo após o 06 (usa os contadores da carga).
source "$(dirname "$0")/lib.sh"
C="calls, round(total_exec_time::numeric) total_ms, round(mean_exec_time::numeric,2) media_ms, round(stddev_exec_time::numeric,2) desvio_ms, round((100*total_exec_time/sum(total_exec_time) OVER ())::numeric,1) pct, rows, shared_blks_hit hit, shared_blks_read lidos, (shared_blks_hit+shared_blks_read)/greatest(calls,1) blocos_chamada, temp_blks_written temp_w, left(regexp_replace(query,'\s+',' ','g'),110) consulta"
{
  echo "=== por tempo total";        sql -c "SELECT $C FROM pg_stat_statements WHERE query NOT ILIKE '%pg_stat%' ORDER BY total_exec_time DESC LIMIT 15"
  echo "=== por tempo médio";        sql -c "SELECT $C FROM pg_stat_statements WHERE calls>=20 AND query NOT ILIKE '%pg_stat%' ORDER BY mean_exec_time DESC LIMIT 10"
  echo "=== por blocos lidos";       sql -c "SELECT $C FROM pg_stat_statements WHERE query NOT ILIKE '%pg_stat%' ORDER BY shared_blks_read DESC LIMIT 10"
  echo "=== por blocos por chamada"; sql -c "SELECT $C FROM pg_stat_statements WHERE calls>=20 AND query NOT ILIKE '%pg_stat%' ORDER BY blocos_chamada DESC NULLS LAST LIMIT 10"
  echo "=== temporários em disco";   sql -c "SELECT $C FROM pg_stat_statements WHERE temp_blks_written>0 ORDER BY temp_blks_written DESC LIMIT 10"
  echo "=== texto completo (top 10)"; sql -c "\x on" -c "SELECT calls, round(total_exec_time::numeric) total_ms, query FROM pg_stat_statements WHERE query NOT ILIKE '%pg_stat%' ORDER BY total_exec_time DESC LIMIT 10"
} 2>&1 | saida
