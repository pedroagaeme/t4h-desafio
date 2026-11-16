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
| 2 | 1 | Índice em `pedidos(cliente_id)` | mesmas do #1 | Aplicada e medida | p95 `pedidos-do-cliente`: 11518,9 ms<br>p95 total: 10717,4 ms<br>5,45 req/s | p95 `pedidos-do-cliente`: 9388,6 ms<br>p95 total: 8796,8 ms<br>6,50 req/s | `*-01-indice-itens-pedido` | `*-02-indice-pedidos-cliente` | H2 confirmada: p95 da rota caiu 18,5%, p95 total 17,9%, req/s +19,3%. Ganho bem menor que o do #1; o banco segue em ~100% de CPU. `pedidos-por-status` melhorou sem ter sido alterada (p95 11004,6 → 8707,0 ms), causa não investigada |
| 3 | 2 | Trocar a conexão por consulta (`db.js`) por um `pg.Pool` na API | [node-postgres: Pooling](https://node-postgres.com/features/pooling), [node-postgres: Pool API](https://node-postgres.com/apis/pool), [Docs: client/server model](https://www.postgresql.org/docs/16/connect-estab.html) | Pesquisada, teste futuro | mediana total: 897,5 ms<br>p95 total: 8796,8 ms<br>p99 total: 16570,7 ms<br>6,50 req/s | preencher | `*-02-indice-pedidos-cliente` | preencher | preencher |
| 4 | 2 | PgBouncer como serviço novo entre a API e o banco (API sem pool) | [PgBouncer: Features](https://www.pgbouncer.org/features.html), [PgBouncer: configuração](https://www.pgbouncer.org/config.html), [Yugabyte](https://www.yugabyte.com/blog/database-connection-management/) | Aplicada e medida | mediana total: 897,5 ms<br>p95 total: 8796,8 ms<br>p99 total: 16570,7 ms<br>6,50 req/s | mediana total: 704,6 ms<br>p95 total: 7335,1 ms<br>p99 total: 13101,0 ms<br>8,61 req/s | `*-02-indice-pedidos-cliente` | `*-04-pgbouncer` | H4 confirmada: mediana total −21,5%, p95 −16,6%, p99 −20,9%, req/s +32,5%. Custo: contêiner novo com 3,9% de CPU média e 7,9 MiB de memória média. O banco segue em ~101% de CPU |
| 5 | 2 | Pgpool-II como serviço novo entre a API e o banco (API sem pool) | [Pgpool-II](https://www.pgpool.net/mediawiki/index.php/Main_Page) | Pesquisada, teste futuro | mediana total: 897,5 ms<br>p95 total: 8796,8 ms<br>p99 total: 16570,7 ms<br>6,50 req/s | preencher | `*-02-indice-pedidos-cliente` | preencher | preencher |

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

### Detalhe do #2 (mediana das 3 execuções, antes → depois)

Rótulo `02-indice-pedidos-cliente`, 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42), commit `182842e`, 0 arquivos sem commit. Contrato mantido (42 respostas iguais) nas 3 execuções.

- `resultados/20261114-142312-02-indice-pedidos-cliente`
- `resultados/20261114-142444-02-indice-pedidos-cliente`
- `resultados/20261114-142617-02-indice-pedidos-cliente`

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 340 → 417 | 898,4 → 897,5 | 10717,4 → 8796,8 | 17400,8 → 16570,7 |
| cliente | 83 → 111 | 297,8 → 303,3 | 598,5 → 586,4 | 819,9 → 700,5 |
| cliente-por-email | 56 → 64 | 896,9 → 894,2 | 1340,1 → 1178,8 | 1782,4 → 1475,3 |
| pedidos-do-cliente | 68 → 83 | 8003,5 → 5687,9 | 11518,9 → 9388,6 | 12206,4 → 10396,2 |
| pedidos-por-status | 48 → 57 | 5723,1 → 5598,3 | 11004,6 → 8707,0 | 22125,4 → 12159,9 |
| busca-produtos | 60 → 70 | 499,0 → 495,2 | 793,4 → 714,7 | 977,3 → 918,1 |
| vendas-por-dia | 25 → 29 | 6417,8 → 5622,4 | 14053,4 → 14231,2 | 18860,6 → 20786,4 |
| top-produtos | 5 → 5 | 16802,2 → 22700,8 | 30522,3 → 24875,9 | 32745,8 → 26467,6 |

Requisições por segundo: 5,45 → 6,50. Erros: 0,0% nas 3 execuções.
O p95 de `pedidos-do-cliente` nas 3 execuções foi 10390,8, 9100,6 e 9388,6 ms, todos abaixo do menor valor de antes (10708,3 ms).

Recursos (`recursos.txt`, mediana das 3 execuções; 100% = 1 CPU):

| contêiner | cpu média | cpu máx | mem média (MiB) | mem máx (MiB) |
|---|---|---|---|---|
| banco | 100,3% | 99,9% | 398,9 | 466,5 |
| api | 11,7% | 9,7% | 39,5 | 54,0 |

### Detalhe do #4 (mediana das 3 execuções, antes → depois)

Rótulo `04-pgbouncer`, 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42), 0 arquivos sem commit. Contrato mantido (42 respostas iguais) nas 3 execuções. Configuração: imagem `edoburu/pgbouncer:v1.26.1-p0`, `pool_mode = transaction`, `default_pool_size = 10`, limites do contêiner de 0,25 CPU e 64 MB; a API sem pool, apontando para o PgBouncer.

- `resultados/20261116-113231-04-pgbouncer`
- `resultados/20261116-113402-04-pgbouncer`
- `resultados/20261116-113534-04-pgbouncer`

| rota | req | mediana (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|
| total | 417 → 558 | 897,5 → 704,6 | 8796,8 → 7335,1 | 16570,7 → 13101,0 |
| cliente | 111 → 153 | 303,3 → 199,3 | 586,4 → 710,8 | 700,5 → 899,3 |
| cliente-por-email | 64 → 80 | 894,2 → 601,0 | 1178,8 → 1283,6 | 1475,3 → 1517,5 |
| pedidos-do-cliente | 83 → 116 | 5687,9 → 4590,3 | 9388,6 → 8042,7 | 10396,2 → 9688,9 |
| pedidos-por-status | 57 → 78 | 5598,3 → 3400,4 | 8707,0 → 7861,8 | 12159,9 → 13757,6 |
| busca-produtos | 70 → 86 | 495,2 → 303,3 | 714,7 → 763,2 | 918,1 → 995,8 |
| vendas-por-dia | 29 → 38 | 5622,4 → 3787,1 | 14231,2 → 8411,6 | 20786,4 → 9993,8 |
| top-produtos | 5 → 8 | 22700,8 → 14461,4 | 24875,9 → 20464,0 | 26467,6 → 21238,4 |

Requisições por segundo: 6,50 → 8,61 (8,48, 8,61 e 8,82 nas 3 execuções). Erros: 0,0% nas 3 execuções.
Nas 3 execuções, a mediana total (700,1, 704,6 e 708,8 ms), o p95 total (7272,5, 7335,1 e 7364,1 ms) e o p99 total (13554,4, 11243,3 e 13101,0 ms) ficaram abaixo dos valores de antes (897,5, 8796,8 e 16570,7 ms).

Recursos (`recursos.txt`, mediana das 3 execuções; 100% = 1 CPU):

| contêiner | cpu média | cpu máx | mem média (MiB) | mem máx (MiB) |
|---|---|---|---|---|
| banco | 100,3% → 100,9% | 99,9% → 100,0% | 398,9 → 404,9 | 466,5 → 460,0 |
| pgbouncer | — → 3,9% | — → 7,8% | — → 7,9 | — → 8,2 |
| api | 11,7% → 14,5% | 9,7% → 9,6% | 39,5 → 37,5 | 54,0 → 45,5 |

## Hipóteses (escritas antes de aplicar)

**H1 (#1).** Criar um índice em `itens_pedido(pedido_id)` deve reduzir o p95 da rota `pedidos-do-cliente`, porque, segundo a Rodada 1, cada uma das 5 consultas por requisição hoje lê a tabela inteira (varredura sequencial) e descarta 499999 linhas para devolver 2.

**H2 (#2).** Criar um índice em `pedidos(cliente_id)` deve reduzir o p95 da rota `pedidos-do-cliente` sobre o estado após o #1, porque, segundo a Rodada 1, a consulta hoje lê a tabela inteira (varredura sequencial) e descarta 166665 linhas por processo para devolver 5.

**H3 (#3).** Trocar a conexão por consulta (`db.js`) por um `pg.Pool` deve reduzir a mediana, o p95 e o p99 gerais sobre o estado após o #2, porque criar uma conexão leva tempo e hoje cada consulta cria a sua.

**H4 (#4).** Colocar o PgBouncer entre a API e o banco, mantendo a API sem pool, deve reduzir a mediana, o p95 e o p99 gerais sobre o estado após o #2, pelo mesmo motivo do H3: o custo vem de abrir conexões ao banco, que está saturado, e o PgBouncer é um pooler de conexões que reaproveita as conexões ao servidor. O custo do contêiner novo (CPU e memória em `recursos.txt`) entra na comparação.

**H5 (#5).** Colocar o Pgpool-II entre a API e o banco, mantendo a API sem pool, deve reduzir a mediana, o p95 e o p99 gerais sobre o estado após o #2, pelo mesmo motivo do H3, porque o Pgpool-II lista pool de conexões entre as suas funções. O custo do contêiner novo (CPU e memória em `recursos.txt`) entra na comparação.

Os #3, #4 e #5 são testados separadamente, cada um sobre o estado após o #2 e sem os outros dois aplicados.