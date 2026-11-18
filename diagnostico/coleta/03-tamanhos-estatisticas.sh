source "$(dirname "$0")/lib.sh"
sql \
 -c "SELECT c.relname, c.relkind, pg_size_pretty(pg_total_relation_size(c.oid)) total, pg_size_pretty(pg_relation_size(c.oid)) relacao, c.reltuples::bigint linhas, c.relpages, c.relallvisible FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','i','m') ORDER BY pg_total_relation_size(c.oid) DESC" \
 -c "SELECT pg_size_pretty(pg_database_size('loja')) tamanho_do_banco" \
 -c "SELECT tablename, attname, avg_width, n_distinct, correlation FROM pg_stats WHERE schemaname='public' ORDER BY tablename, attname" \
 -c "SELECT relname, n_live_tup, n_dead_tup, last_vacuum, last_autovacuum, last_analyze, last_autoanalyze FROM pg_stat_user_tables ORDER BY relname" \
 -c "SELECT indexname, indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY tablename, indexname" 2>&1 | saida
