# diagnostico/

Saídas de diagnóstico (não são medições). Antes e depois de cada mudança vêm só de `medir.sh`, em `resultados/`.
Os valores de k6 destas pastas usam duração curta e **não são baseline**.

## Rodada 1

### Saídas

**`saidas/20261108-095016-use-baseline`**
- *Por que rodei:* a baseline (`recursos.txt`) já mostrava a utilização: banco em ~100% da CPU e API em ~7%. Faltava saber se há saturação (trabalho esperando por recurso) e erros, que o `recursos.txt` não mede.
- *O que descobri:*
  - Saturação: a CPU do banco está saturada. O sistema o segurou por causa do limite em 96,3% dos períodos de controle, e em 86,9% do tempo havia alguma tarefa esperando CPU. A memória do banco também encostou no limite de 512 MiB (atingiu o limite 2414 vezes, com pressão de memória em 5,9% do tempo), bem menos que a CPU. A API quase não tem saturação (0,7% dos períodos). Disco sem saturação relevante (0,6% do tempo).
  - Erros: nenhum, no banco nem na API (`oom=0`, `oom_kill=0`).

**`saidas/20261108-160654-pgss-baseline`**
- *Por que rodei:* como o banco é o gargalo, para saber quais consultas SQL gastam mais tempo nele.
- *O que descobri:* da soma do tempo gasto em consultas durante o teste, 44,0% foi na consulta que busca os itens de um pedido (`itens_pedido` por `pedido_id`) e 12,8% na que lista os pedidos de um cliente (`pedidos` por `cliente_id`). Em seguida vêm a listagem de pedidos por `status` (11,5%), `vendas-por-dia` (10,4%) e `top-produtos` (9,3%).

**`saidas/20261108-101356-rotas-isoladas`**
- *Por que rodei:* para ver o que cada rota faz no banco quando está sozinha, sem outras requisições competindo, e ler o plano de execução de cada consulta (o roteiro que o PostgreSQL escolhe para buscar os dados).
- *O que descobri:* uma única requisição a `pedidos-do-cliente` dispara 17 consultas: 1 de cliente, 1 da lista de pedidos, 5 de itens e 10 de produtos. As 6 consultas de pedidos e itens fazem varredura sequencial: leem a tabela inteira, linha por linha, para devolver de 2 a 5 linhas. Cada uma leva de 70 a 92 ms, e juntas são ~99,9% do tempo que a rota gasta no banco (~470 ms). As outras 11 buscam pela chave primária, que já tem índice, e levam 0,2 ms ou menos. O plano é o mesmo na chamada 1 (cache frio) e na 2 (cache quente).

**`saidas/indices-antes.txt`**
- *Por que rodei:* para conferir se `pedidos` e `itens_pedido` têm índice nas colunas que as consultas usam para filtrar.
- *O que descobri:* só existem as chaves primárias. Não há índice em `pedidos.cliente_id` nem em `itens_pedido.pedido_id`, o que é coerente com o banco ter de ler a tabela inteira nessas consultas.

### Hipóteses de causa

Três problemas encadeados. Cada hipótese é suposição até a medição de `experimentos.md` confirmar ou refutar.

**1. p95 alto → a CPU do banco está saturada.**
- Evidência: a baseline mostra o banco em ~100% da CPU e a API em ~7% (`recursos.txt`); `use-baseline` mostra que o banco está saturado, com trabalho esperando CPU.

**2. CPU do banco saturada → consultas mal otimizadas.**
- Evidência: as consultas de pedidos do cliente gastam ~57% do tempo do banco com ~22,5% das requisições (`pgss-baseline`). Em `rotas-isoladas`, 6 das 17 consultas da rota somam ~99,9% do tempo dela no banco.

**3. Consultas mal otimizadas → falta de índice em `itens_pedido.pedido_id` e `pedidos.cliente_id`.**
- Evidência: só existem chaves primárias (`indices-antes.txt`), e os planos mostram o banco lendo a tabela inteira (descartando 499999 linhas em `itens_pedido` e 166665 por processo em `pedidos`) para devolver de 2 a 5. `itens_pedido` roda 5 vezes por requisição (≈82–83% do tempo da rota no banco); `pedidos`, 1 vez (≈17–18%).
- Falta: medir antes e depois de cada índice (`experimentos.md`).

## Scripts

| Script | Função |
|---|---|
| `scripts/use-sob-carga.sh <rotulo>` | Matriz USE via cgroup v2, sob a carga do `medir.sh` |
| `scripts/pgss-sob-carga.sh <rotulo>` | Igual, com `pg_stat_statements` zerado após o aquecimento; grava o ranking |
| `scripts/rotas-isoladas.sh` | Mede cada rota sozinha, sem concorrência (conferir descrição) |
| `pgss.yml` | Liga `pg_stat_statements` só no diagnóstico: `export COMPOSE_FILE=docker-compose.yml:diagnostico/pgss.yml`. Para medir: `unset COMPOSE_FILE` |

## IA

Usei IA para escrever estes scripts e buscar fontes; rodei tudo e as conclusões são minhas (ver seção 9 do artigo).