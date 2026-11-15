#!/usr/bin/env bash
# Controle de CPU do banco em repouso: mede quanto CPU o banco gasta sozinho, sem k6 e sem o laço de conexões.
# Serve para descontar o ruído de fundo do Postgres das medições de conexões-sob-carga.sh (fase ociosa).
#
#   diagnostico/scripts/conexoes-controle.sh <rotulo>
#   JANELA_S=30 ESPERA_S=20 diagnostico/scripts/conexoes-controle.sh conexoes-controle-1
#
# JANELA_S: duração da leitura (padrão 30 s, a mesma da fase ociosa de conexoes-sob-carga.sh).
# ESPERA_S: pausa antes de ler, para o banco assentar depois de uma carga (padrão 20 s).
# Os dois `cat` do cpu.stat rodam dentro do contêiner do banco e gastam CPU desprezível.
#
# Diagnóstico: não escreve em resultados/. Commite diagnostico/saidas/ antes de rodar o medir.sh de verdade.
#
# Saída: diagnostico/saidas/<data>-<rotulo>/
#   resumo.txt   parâmetros, commit e deltas de CPU na janela
#   antes/ depois/  cpu.stat bruto do banco

set -euo pipefail
cd "$(dirname "$0")/../.."

ROTULO="${1:-}"
if [[ -z "$ROTULO" || ! "$ROTULO" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "uso: diagnostico/scripts/conexoes-controle.sh <rotulo>   (letras, números, ponto, hífen ou sublinhado)" >&2
  exit 2
fi

JANELA_S="${JANELA_S:-30}"
ESPERA_S="${ESPERA_S:-20}"
CG=/sys/fs/cgroup

for v in JANELA_S ESPERA_S; do
  if [[ ! "${!v}" =~ ^[0-9]+$ ]]; then
    echo "$v precisa ser um número inteiro." >&2
    exit 2
  fi
done

if ! docker compose exec -T banco test -f "$CG/cpu.stat" 2>/dev/null; then
  echo "Não consegui ler $CG/cpu.stat no banco. O contêiner não está rodando ou o cgroup é v1." >&2
  exit 1
fi

if [[ -n "$(docker compose --profile ferramentas ps -q carga 2>/dev/null)" ]]; then
  echo "Há um contêiner do k6 (carga) rodando. Espere terminar: o controle precisa ser feito sem carga." >&2
  exit 1
fi

agora_ns() {
  local t
  t="$(date +%s%N)"
  if [[ "$t" == *N* ]]; then t="$(( $(date +%s) * 1000000000 ))"; fi
  echo "$t"
}

valor() { awk -v k="$2" '$1 == k { print $2; f = 1 } END { if (!f) print 0 }' "$1"; }

SAIDA="diagnostico/saidas/$(date +%Y%m%d-%H%M%S)-${ROTULO}"
mkdir -p "$SAIDA/antes" "$SAIDA/depois"

echo "Esperando ${ESPERA_S}s para o banco assentar..."
sleep "$ESPERA_S"

docker compose exec -T banco cat "$CG/cpu.stat" > "$SAIDA/antes/banco.cpu.stat"
T0="$(agora_ns)"
echo "Lendo o CPU do banco em repouso por ${JANELA_S}s..."
sleep "$JANELA_S"
docker compose exec -T banco cat "$CG/cpu.stat" > "$SAIDA/depois/banco.cpu.stat"
T1="$(agora_ns)"

A="$SAIDA/antes/banco.cpu.stat"
D="$SAIDA/depois/banco.cpu.stat"
USO=$(( $(valor "$D" usage_usec) - $(valor "$A" usage_usec) ))
PER=$(( $(valor "$D" nr_periods) - $(valor "$A" nr_periods) ))
THR=$(( $(valor "$D" nr_throttled) - $(valor "$A" nr_throttled) ))

{
  echo "rotulo: ${ROTULO}"
  echo "data: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "janela_s: ${JANELA_S} espera_s: ${ESPERA_S}"
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "commit: $(git rev-parse --short HEAD 2>/dev/null || echo sem-commit)"
  fi
  echo
  awk -v ns="$((T1 - T0))" -v uso="$USO" -v per="$PER" -v thr="$THR" 'BEGIN {
    printf "janela lida: %.1f s\n", ns / 1e9
    printf "usage_usec (delta): %d µs\n", uso
    printf "CPU médio do banco: %.3f CPUs\n", uso / (ns / 1000)
    printf "períodos: %d, throttled: %d\n", per, thr
  }'
} | tee "$SAIDA/resumo.txt"

echo
echo "Saída salva em $SAIDA/ (nada foi criado em resultados/)"
