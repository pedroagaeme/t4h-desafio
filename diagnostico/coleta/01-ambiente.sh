source "$(dirname "$0")/lib.sh"
{
  echo "data: $(date -Is)"; echo "commit: $(git rev-parse --short HEAD) ($(git branch --show-current))"
  git status --short | head -20
  docker compose ps
  docker stats --no-stream
  docker compose config | grep -n -i -E "cpus|mem_limit|memory|command|image"
  docker compose exec -T api node -v
  curl -s -o /dev/null -w 'api: %{http_code}\n' "$BASE/clientes/1"
} 2>&1 | saida
