# Experimentos

Uma linha por mudança.

## Procedimento

1. `unset COMPOSE_FILE` (nada do diagnóstico ligado).
2. Fazer uma única mudança.
3. `git commit` da mudança, para o `contexto.txt` mostrar 0 arquivos alterados sem commit.
4. `./scripts/verificar-contrato.sh comparar` passando (código de saída 0).
5. `./scripts/medir.sh <rotulo>` 3 vezes com o mesmo rótulo; comparar as medianas.
6. Commit separado de `resultados/` e nova linha na tabela abaixo.

Cada linha compara com o estado anterior, indicado na coluna "Pasta antes".

## Baseline

Rótulo `00-linha-de-base`, 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42), commit `fb41551`, 0 arquivos sem commit.

- `resultados/20261107-102646-00-linha-de-base`
- `resultados/20261107-102913-00-linha-de-base`
- `resultados/20261107-103052-00-linha-de-base`

Mediana de cada métrica entre as 3 execuções (valores de cada `resumo.txt`). Erros: 0,0% em todas as rotas, nas 3 execuções.

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 224 | 1048,1 | 20065,9 | 23204,7 |
| cliente | 54 | 396,8 | 699,4 | 795,7 |
| cliente-por-email | 38 | 998,8 | 1557,4 | 1958,0 |
| pedidos-do-cliente | 51 | 17494,2 | 22594,2 | 23449,4 |
| pedidos-por-status | 24 | 6447,1 | 9959,6 | 12041,3 |
| busca-produtos | 37 | 606,5 | 997,8 | 1128,9 |
| vendas-por-dia | 17 | 6066,3 | 7948,6 | 8135,5 |
| top-produtos | 3 | 14303,9 | 24825,4 | 25760,7 |

Requisições por segundo (total): 3,32.

Recursos (`recursos.txt`, mediana das 3 execuções; 100% = 1 CPU):

| contêiner | cpu média | cpu máx | mem média (MiB) | mem máx (MiB) |
|---|---|---|---|---|
| banco | 99,9% | 100,0% | 398,6 | 445,9 |
| api | 6,9% | 9,9% | 31,6 | 37,2 |

## Experimentos

Rodada = rodada de diagnóstico (`diagnostico/README.md`) que motivou a ideia. Pastas = rótulo das 3 execuções em `resultados/` (`*-<rótulo>`); a pasta "antes" é o estado de comparação (baseline ou o "depois" da linha anterior).

| # | Rodada | Ideia | Fonte | Status | Antes | Depois | Pasta antes | Pasta depois | Conclusão |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 1 | Índice em `itens_pedido(pedido_id)` | [Docs 11.1](https://www.postgresql.org/docs/16/indexes-intro.html), [Docs 5.4.5](https://www.postgresql.org/docs/16/ddl-constraints.html) | Aplicada e medida | p95 `pedidos-do-cliente`: 22594,2 ms<br>p95 total: 20065,9 ms<br>3,32 req/s | p95 `pedidos-do-cliente`: 11518,9 ms<br>p95 total: 10717,4 ms<br>5,45 req/s | `*-00-linha-de-base` | `*-01-indice-itens-pedido` | H1 confirmada: p95 da rota caiu 49%, p95 total 47%, req/s +64%. `vendas-por-dia` piorou (p95 7948,6 → 14053,4 ms), causa não investigada |
| 2 | 1 | Índice em `pedidos(cliente_id)` | mesmas do #1 | Pesquisada, teste futuro | p95 `pedidos-do-cliente`: 11518,9 ms<br>p95 total: 10717,4 ms<br>5,45 req/s | preencher | `*-01-indice-itens-pedido` | preencher | preencher |

Status: `Aplicada e medida`, `Aplicada, sem ganho` ou `Pesquisada, teste futuro`. Ao medir, troque o status e preencha Depois (medianas das 3 execuções), a pasta e a conclusão.

### Detalhe do #1 (mediana das 3 execuções, antes → depois)

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 224 → 340 | 1048,1 → 898,4 | 20065,9 → 10717,4 | 23204,7 → 17400,8 |
| cliente | 54 → 83 | 396,8 → 297,8 | 699,4 → 598,5 | 795,7 → 819,9 |
| cliente-por-email | 38 → 56 | 998,8 → 896,9 | 1557,4 → 1340,1 | 1958,0 → 1782,4 |
| pedidos-do-cliente | 51 → 68 | 17494,2 → 8003,5 | 22594,2 → 11518,9 | 23449,4 → 12206,4 |
| pedidos-por-status | 24 → 48 | 6447,1 → 5723,1 | 9959,6 → 11004,6 | 12041,3 → 22125,4 |
| busca-produtos | 37 → 60 | 606,5 → 499,0 | 997,8 → 793,4 | 1128,9 → 977,3 |
| vendas-por-dia | 17 → 25 | 6066,3 → 6417,8 | 7948,6 → 14053,4 | 8135,5 → 18860,6 |
| top-produtos | 3 → 5 | 14303,9 → 16802,2 | 24825,4 → 30522,3 | 25760,7 → 32745,8 |

Requisições por segundo: 3,32 → 5,45. Erros: 0,0% nas 3 execuções.
O p95 de `pedidos-do-cliente` nas 3 execuções foi 11518,9, 10708,3 e 12513,5 ms, todos abaixo do menor valor da baseline (22017,4 ms).

## Hipóteses (escritas antes de aplicar)

**H1 (#1).** Criar um índice em `itens_pedido(pedido_id)` deve reduzir o p95 da rota `pedidos-do-cliente`, porque, segundo a Rodada 1, cada uma das 5 consultas por requisição hoje lê a tabela inteira (varredura sequencial) e descarta 499999 linhas para devolver 2.

**H2 (#2).** Criar um índice em `pedidos(cliente_id)` deve reduzir o p95 da rota `pedidos-do-cliente` sobre o estado após o #1, porque, segundo a Rodada 1, a consulta hoje lê a tabela inteira (varredura sequencial) e descarta 166665 linhas por processo para devolver 5.