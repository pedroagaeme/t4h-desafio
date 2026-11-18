source "$(dirname "$0")/lib.sh"
sql \
 -c "SELECT relname, seq_scan, seq_tup_read, idx_scan, idx_tup_fetch FROM pg_stat_user_tables ORDER BY seq_tup_read DESC" \
 -c "SELECT relname, indexrelname, idx_scan, idx_tup_read, pg_size_pretty(pg_relation_size(indexrelid)) tamanho FROM pg_stat_user_indexes ORDER BY idx_scan" \
 -c "SELECT blks_read, blks_hit, round(100.0*blks_hit/nullif(blks_hit+blks_read,0),2) pct_cache, temp_files, temp_bytes, xact_commit, xact_rollback, deadlocks FROM pg_stat_database WHERE datname='loja'" 2>&1 | saida
