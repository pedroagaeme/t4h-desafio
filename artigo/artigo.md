# API de loja de 3,32 para 686,5 req/s: índices, pool e views materializadas dentro dos mesmos limites de CPU e memória

## 1. Resumo

Uma API de loja fictícia (Node.js 20/Express e PostgreSQL 16; API com 0,5 CPU e 256 MB, banco com 1 CPU e 512 MB) atendia 3,32 req/s no teste de carga, com p95 de 20065,9 ms e o banco a 99,9% de CPU. Diagnostiquei consultas que liam tabelas inteiras e trabalho repetido a cada requisição, testei 18 mudanças e adotei 15, cada uma medida três vezes sem alterar o que as rotas devolvem. O resultado foi 686,5 req/s e p95 de 71,7 ms, com os mesmos limites. O gargalo passou para a CPU da API, e os relatórios passaram a refletir o último `REFRESH` das views.

## 2. Contexto e diagnóstico

No teste de carga (20 usuários virtuais, 60 s, semente 42), a linha de base ([`resultados/20261107-102646-00-linha-de-base`](resultados/20261107-102646-00-linha-de-base/resumo.txt) e duas execuções irmãs) mostrou o banco em 99,9% de CPU e a API em 6,9%: o banco era o gargalo (`diagnostico/saidas/20261108-095016-use-baseline`). Os problemas que o diagnóstico (`diagnostico/README.md`) encontrou, cada um com a hipótese de causa:

- **Consultas que leem a tabela inteira.** As consultas de itens e de pedidos por cliente descartavam 499.999 linhas para devolver 2 (`diagnostico/saidas/20261108-101356-rotas-isoladas/planos/pedidos-do-cliente-chamada1.log`). Hipótese: faltam índices, e só existiam as chaves primárias (`diagnostico/saidas/indices-antes.txt`).
- **Consultas demais por requisição.** `pedidos-do-cliente` dispara 17 consultas (`.../rotas-isoladas/consultas-por-requisicao.txt`), cada uma numa conexão nova, que sob carga levava 196 ms para abrir (`diagnostico/saidas/20261114-194425-conexoes-1`). Hipótese: o padrão N+1 e a ausência de um pool.
- **Listagem de pedidos por status.** Responde por 45,6% da CPU do banco (`diagnostico/saidas/20261115-114814-cpu-por-rota-1/resumo.txt`) e fica mais cara nas páginas altas: 10.052 blocos lidos na página 500 e 120.594 na 6000 (`diagnostico/saidas/20261118-094652-coleta/10-explain-consultas.txt`). Hipótese: o `OFFSET` calcula as linhas puladas.
- **Filtros que não usam índice.** A busca por e-mail e a busca de produtos faziam varredura sequencial (`diagnostico/saidas/20261116-161317-rotas-isoladas-pos-8/planos/cliente-por-email-chamada1.log` e `diagnostico/saidas/20261118-094652-coleta/10-explain-consultas.txt`), e `vendas-por-dia` filtrava por `criado_em::date`. Hipótese: o filtro precisa de índice sobre a expressão ou o trecho de texto, e o `::date` impede o uso de um índice simples.
- **Agregações refeitas a cada requisição.** `top-produtos` lê e junta cerca de 1,35 milhão de linhas por requisição (`diagnostico/saidas/20261115-112714-rotas-isoladas-pos-indices/planos/top-produtos-chamada1.log`), e o `count(*)` por status gasta 15,2% do tempo do banco (`diagnostico/saidas/20261116-162256-pgss-pos-8/pgss-top.txt`). Hipótese: os resultados são recalculados, embora os dados não mudem durante o teste.
- **API limitada pela cota de CPU.** Depois dos índices e das views, a API ficou pausada em 715 de 782 períodos (`diagnostico/saidas/20261118-094652-coleta/06-carga.txt`), e `vendas-por-dia` gasta 78,1 a 84,1 ms de CPU da API por requisição ao agrupar ~12,9 mil linhas em JavaScript (`diagnostico/saidas/20261116-161636-cpu-por-rota-pos-8-1`). Hipótese: o trabalho de agregação deveria estar no banco.
- **Paralelismo num banco de 1 CPU.** O plano de `vendas-por-dia` usa `Gather` com 2 workers (`10-explain-consultas.txt`). Hipótese: com um só núcleo, os workers só adicionam coordenação.

## 3. Estado da arte

Para cada problema do diagnóstico, o que as fontes dizem sobre como ele costuma ser resolvido. O que medi aqui está nas seções 4 a 6.

### Consultas que leem a tabela inteira

A solução usual é o índice. Sem ele, o PostgreSQL faz uma varredura sequencial e confere cada linha, o que custa caro numa tabela grande para uma consulta que devolve poucas linhas; o índice leva à linha por uma árvore de poucos níveis, mas o planejador só o usa se achar que compensa, e cada índice custa em toda escrita [1]. Um índice B-tree também devolve as linhas já ordenadas e dispensa a ordenação, o que ajuda sobretudo em `ORDER BY ... LIMIT n`, e em índices de várias colunas a direção de cada coluna importa [2]. Para filtros sobre uma expressão, como `lower(col)`, o índice pode ser criado sobre a própria expressão, ao custo de calculá-la em cada inserção e atualização [3]. Para buscas por trecho de texto, os índices trigram (GIN ou GiST) aceitam `LIKE` e `ILIKE` mesmo com curinga no início, onde um B-tree comum não ajuda [4]. Quando a consulta pede só colunas do índice, o Index Only Scan evita a tabela, mas só nas páginas marcadas como visíveis [5].

### Muitas consultas por requisição e filtros que impedem o índice

O padrão N+1 é uma consulta para as linhas principais e mais uma para os dados relacionados de cada linha. A fonte argumenta que as idas e voltas ao banco pesam mais no tempo de resposta do que o volume de dados, e recomenda a junção no banco, com atenção a efeitos como registros-pai duplicados [8]. Outro problema é aplicar uma função à coluna do filtro: segundo o mesmo autor, isso costuma impedir o índice simples, e a correção é comparar a coluna com um início inclusivo e um fim exclusivo [9]. A página não cita o `::date` do PostgreSQL; que o raciocínio vale para o cast é inferência minha.

### Conexões

Abrir uma conexão é caro: o node-postgres cita cerca de 20 a 30 ms para estabelecê-la, lembra que o PostgreSQL limita quantos clientes atende e que um cliente executa uma consulta por vez, e por isso recomenda um pool [11]. No `pg`, o pool é o `pg.Pool`: `pool.query()` roda a consulta num cliente já aberto e disponível, e o uso manual com `pool.connect()` exige `client.release()` depois de cada uso, sob pena de vazar clientes até as requisições travarem [11]. Outra opção é um pooler separado. O PgBouncer é leve e tem três modos (sessão, transação e comando); no modo de transação, recursos baseados em sessão deixam de funcionar [12]. O Pgpool-II é um middleware mais amplo, que além do pool lista balanceamento de leitura, alta disponibilidade e cache de consultas [13].

### Listagem paginada

A paginação comum usa `LIMIT` e `OFFSET`, mas as linhas puladas ainda são calculadas no servidor, e é preciso um `ORDER BY` de ordem única [6]. O seek method evita esse custo ao filtrar pela chave da última linha vista, mas exige ordem determinística e não permite saltar para a página N [7]. O Index Only Scan [5], descrito acima, reduz a leitura da tabela quando a consulta se limita às colunas do índice.

### Agregações refeitas a cada requisição

Uma view materializada guarda o resultado da consulta como uma tabela e fica desatualizada até o próximo `REFRESH` [15]. Para contagens, o wiki do PostgreSQL explica que o `count(*)` é lento por causa do controle de versões (MVCC), que obriga a checar a visibilidade de cada linha, e sugere estimativas quando a precisão exata não é necessária; a página não trata de views materializadas [10]. Em escala maior, o C-Store descreve os data warehouses como sistemas otimizados para leitura, em que o armazenamento por coluna lê só o que a consulta precisa [16].

### Reaproveitar planos de consulta

Uma instrução preparada é analisada uma vez e planejada a cada execução com os parâmetros recebidos. O ganho é maior quando planejar é caro (junções de várias tabelas) e menor quando a consulta é barata de planejar e cara de executar. No modo automático, o servidor usa planos personalizados nas primeiras cinco execuções e só adota o genérico se o custo estimado não for muito maior [14].

### Paralelismo e escalabilidade

No PostgreSQL, o processo líder também lê todas as tuplas dos workers e, com muitas tuplas, passa a maior parte do tempo coletando-as [17]. O número de workers por consulta é limitado por `max_parallel_workers_per_gather` (padrão 2), os workers pedidos podem não estar disponíveis na hora, e o valor 0 desliga o paralelismo [18]. Para o panorama geral, Gunther modela a escalabilidade como uma função racional do número de processadores, da qual a lei de Amdahl é um caso particular [19].

## 4. Alternativas consideradas

Para cada decisão comparei o que a literatura oferece com o que consegui medir, sempre sobre o estado anterior indicado em `experimentos.md` (mediana de 3 execuções). Onde não houve medição, a célula diz "não medido" ou "pesquisada". O enunciado exige mostrar o ganho junto com o custo, então a coluna de custo traz CPU, memória ou tamanho quando os medi; o resto fica como "não medido". O tamanho, o tempo de criação e o custo de escrita dos índices vêm de `diagnostico/scripts/custo-indice.sh` (pastas `diagnostico/saidas/20261120-*-custo-indice-*`): a escrita é a inserção de 100.000 linhas numa cópia da tabela com só a chave primária, em ordem de `id`, e por isso subestima inserções fora de ordem.

**Leituras sem índice (#1, #2, #6, #7, #12, #16)**

| Alternativa | Custo | Desempenho | Risco | Esforço |
|---|---|---|---|---|
| Sem índice (original) | varredura sequencial a cada consulta [1] | ponto de partida: 3,32 req/s | nenhum novo | — |
| Índices em `itens_pedido(pedido_id)` e `pedidos(cliente_id)` (#1, #2) | índices de 21 MB e 5720 kB; criação em 695,4 e 281,5 ms; inserir 100.000 linhas custa +70,2 ms (+48,2%) e +82,9 ms (+28,1%) [1] | req/s 3,32 → 5,45 → 6,50; p95 total 20065,9 → 8796,8 ms | a escrita fica mais cara, e a API do teste só lê | dois `CREATE INDEX` |
| Índice `(status, criado_em DESC, id DESC)` (#6) | 21 MB; criação em 769,6 ms; inserir 100.000 linhas 285,4 → 497,9 ms (+74,4%) | req/s 8,82 → 14,83 (+68,1%); p95 total −24,9% | o índice só ajuda com a ordem igual à da consulta [2] | um `CREATE INDEX` |
| Índice em `criado_em` e filtro por intervalo (#7) | 11 MB; criação em 290,8 ms; inserir 100.000 linhas 392,3 → 531,3 ms (+35,5%) | req/s 14,83 → 17,34 (+16,9%); p95 total −19,7% | p95 e p99 de `pedidos-por-status` pioraram, causa não investigada; a função na coluna impedia o índice [9] | índice e reescrita da consulta, juntos |
| Índice sobre `lower(email)` (#12) | 4792 kB; 422,1 ms para criar; escrita mais cara [3], não medida | req/s 55,57 → 65,71 (+18,2%); mediana da rota −59,9% | consulta precisa usar `lower(email)` igual ao índice [3] | um `CREATE INDEX` |
| Índice GIN trigram em `produtos.nome` (#16) | 1144 kB; criação em 99,2 ms; inserir as 20.000 linhas da tabela 28,9 → 225,9 ms (7,8 vezes) | req/s 131,0 → 169,6 (+29,5%); mediana da busca 202,0 → 96,8 ms | suporta `ILIKE` com curinga, onde um B-tree não ajuda [4] | extensão `pg_trgm` e um `CREATE INDEX` |

**Consultas por rota (#9, #13)**

| Alternativa | Custo | Desempenho | Risco | Esforço |
|---|---|---|---|---|
| Uma consulta por pedido e por item em `pedidos-do-cliente` (original, 17 consultas) | uma ida ao banco por consulta [8] | ponto de partida | nenhum novo | — |
| Junção única (#9) | nenhum serviço novo | req/s 42,86 → 45,21 (+5,5%); mediana da rota −67,2% | mediana total subiu de 291,9 para 398,1 ms e as outras 6 rotas pioraram, causa não investigada; linhas duplicadas na junção [8] | reescrever a consulta e agrupar em JavaScript |
| Tirar `observacoes` do SELECT de `vendas-por-dia` (#13) | nenhum | req/s 65,71 → 87,66 (+33,4%) | p95 e p99 de `pedidos-por-status` pioraram, causa não investigada | uma linha |

**Paginação da listagem (#6, #14)**

| Alternativa | Custo | Desempenho | Risco | Esforço |
|---|---|---|---|---|
| `OFFSET` com índice `(status, criado_em DESC, id DESC)` (#6) | linhas puladas ainda são calculadas [6]; 10.052 blocos lidos na página 500 e 120.594 na 6000 | req/s 8,82 → 14,83 (+68,1%) | custo cresce com a página | — |
| Junção adiada com Index Only Scan e `VACUUM` (#14) | blocos lidos: 139 na página 500 e 681 na 6000 | req/s 87,66 → 107,34 (+22,5%) | só evita a tabela nas páginas visíveis [5] | consulta reescrita e `VACUUM` na criação do banco |
| Seek method (pesquisado, não aplicado) | não medido | não medido | não salta para a página N [7], e a rota recebe `pagina=N` | reescrever a rota e o contrato |

**Conexões**

| Alternativa | Custo | Desempenho | Risco | Esforço |
|---|---|---|---|---|
| `pg.Pool` na API (#3) | memória média da API de 39,5 para 87,3 MiB | req/s 6,50 → 8,82 (+35,7%); p95 total −13,7% | baixo | uma mudança em `db.js` |
| PgBouncer (#4) | contêiner novo: 3,9% de CPU e 7,9 MiB | req/s 6,50 → 8,61 (+32,5%); p95 total −16,6% | modo de transação limita recursos de sessão [12] | serviço novo e configuração |
| Pgpool-II (#5) | contêiner novo: 11,8% de CPU e 226,0 MiB | req/s 6,50 → 7,74 (+19,1%); mediana −39,1%, mas p95 +21,5% e p99 +26,0% | processos-filho falharam com `enable_shared_relcache` ligado (causa não investigada) | serviço novo e configuração mais longa |
| Instruções preparadas nomeadas (pesquisada, teste futuro) | cache de planos por conexão | não medido | pode trocar planos personalizados por genéricos [14] | mudar `db.js` |

**Agregações e relatórios**

| Alternativa | Custo | Desempenho | Risco | Esforço |
|---|---|---|---|---|
| Calcular a cada requisição (original) | 78 a 84 ms de CPU da API por requisição em `vendas-por-dia` (Rodada 3) | ponto de partida | nenhum novo | — |
| Agrupar no SQL (#15) | CPU do banco por requisição 6,1 → 7,5 ms; CPU da API 49,5% → 11,2% | req/s 107,3 → 131,0 (+22,0%) | só ajuda se a API for o limite | uma consulta |
| View `mv_top_produtos` (#8) | 2664 kB; `REFRESH` de 1012,4 ms | req/s 17,34 → 42,86 (+147,2%); mediana da rota −99,0% | dados defasados até o `REFRESH` [15]; memória do banco subiu para 495,8 MiB | um `.sql` e uma consulta |
| View `mv_pedidos_por_status` (#10) | 16 kB; `REFRESH` de 70,6 ms; `count(*)` exige checar a visibilidade de cada linha [10] | req/s 45,21 → 55,57 (+22,9%); mediana da rota −40,5% | idem | um `.sql` e uma consulta |
| View `mv_vendas_por_dia` (#18) | 731 linhas; 104 kB; `REFRESH` de 1116,1 ms | req/s 270,9 → 686,5 (+153,4%); mediana da rota 290,7 → 11,7 ms | idem; dispersão de 673,5 a 753,1 req/s nas 3 execuções | um `.sql` e uma consulta |
| Data warehouse (pesquisado, não testado) | serviço novo, mais CPU e memória | não medido | carga e atualização dos dados [16] | alto |

**Paralelismo no banco**

| Alternativa | Custo | Desempenho | Risco | Esforço |
|---|---|---|---|---|
| Padrão do PostgreSQL (até 2 workers por consulta) [18] | 5,9 ms de CPU do banco por requisição | 169,6 req/s | o líder gasta tempo coletando as tuplas dos workers [17] | — |
| `max_parallel_workers_per_gather = 0` (#17) | 3,7 ms de CPU do banco por requisição; memória máxima do banco de 510,3 MiB, causa não investigada | req/s 169,6 → 270,9 (+59,8%) | consultas pesadas futuras rodam sem paralelismo | uma configuração |

## 5. Solução escolhida e por quê

Adotei 15 das 18 mudanças. A regra foi atacar, a cada passo, o recurso que a medição mostrava saturado: índices e junção única enquanto o banco estava perto de 100% de CPU; pré-cálculo, com views materializadas, nas rotas de leitura sobre dados que não mudam durante a carga; e desligar o paralelismo quando o `EXPLAIN` mostrou que o plano com workers era mais lento que o serial num banco de 1 CPU. Fiquei com o `pg.Pool` porque o ganho foi parecido com o do PgBouncer sem serviço novo (+35,7% contra +32,5% de req/s), e descartei o Pgpool-II: a mediana caiu, mas o p95 e o p99 subiram e o contêiner usou 226,0 MiB. A agregação no SQL (#15) foi adotada e depois substituída pela view (#18). O data warehouse, o seek method e as instruções preparadas nomeadas ficaram fora: os dois relatórios somam 10% das requisições e já respondem rápido com a view, o seek não se encaixa em `pagina=N`, e o ganho esperado das instruções preparadas é pequeno para consultas curtas [14].

## 6. Experimento e resultado

Cada linha compara com o estado indicado em `experimentos.md`. Valores: mediana de 3 execuções (20 VUs, 60 s, aquecimento 15 s, semente 42). CPU: média do banco / da API, em % de 1 CPU; memória: máxima do banco, em MiB.

| Mudança | Hipótese | p95 total antes → depois (ms) | req/s antes → depois | CPU banco / API (%); mem. máx. banco | Pasta | Conclusão |
|---|---|---|---|---|---|---|
| Linha de base | — | 20065,9 | 3,32 | 99,9 / 6,9; 445,9 | `00-linha-de-base` | ponto de partida |
| #1 índice `itens_pedido(pedido_id)` | H1: reduz o p95 de `pedidos-do-cliente` | 20065,9 → 10717,4 | 3,32 → 5,45 | 96,7 / 10,8; 446,2 | `01-indice-itens-pedido` | confirmada |
| #2 índice `pedidos(cliente_id)` | H2: idem, sobre o #1 | 10717,4 → 8796,8 | 5,45 → 6,50 | 100,3 / 11,7; 466,5 | `02-indice-pedidos-cliente` | confirmada |
| #3 `pg.Pool` | H3: reduz mediana, p95 e p99 | 8796,8 → 7593,9 | 6,50 → 8,82 | 91,7 / 11,0; 458,7 | `03-pool-api` | confirmada, adotada |
| #4 PgBouncer | H4: idem H3 | 8796,8 → 7335,1 | 6,50 → 8,61 | 100,9 / 14,5; 460,0 | `04-pgbouncer` | confirmada, não adotada |
| #5 Pgpool-II | H5: idem H3 | 8796,8 → 10688,1 | 6,50 → 7,74 | 98,1 / 15,8; 472,1 | `05-pgpool` | não confirmada |
| #6 índice `(status, criado_em, id)` | H6: reduz mediana, p95 e p99 | 7593,9 → 5704,1 | 8,82 → 14,83 | 99,8 / 16,1; 483,4 | `06-indice-pedidos-status` | confirmada |
| #7 índice `criado_em` e filtro por intervalo | H7: reduz `vendas-por-dia` | 5704,1 → 4579,8 | 14,83 → 17,34 | 98,5 / 16,3; 449,0 | `07-indice-pedidos-criado-em` | confirmada |
| #8 view `mv_top_produtos` | H8: reduz `top-produtos` | 4579,8 → 1721,2 | 17,34 → 42,86 | 91,4 / 38,9; 495,8 | `08-view-top-produtos` | confirmada |
| #9 junção única em `pedidos-do-cliente` | H9: reduz a rota | 1721,2 → 910,6 | 42,86 → 45,21 | 92,1 / 38,3; 492,5 | `09-juncao-pedidos-do-cliente` | confirmada; mediana total piorou |
| #10 view `mv_pedidos_por_status` | H10: reduz `pedidos-por-status` | 910,6 → 796,5 | 45,21 → 55,57 | 85,9 / 43,9; 500,5 | `10-view-contagem-status` | confirmada |
| #11 agrupar vendas no SQL (1ª versão) | H11: reduz `vendas-por-dia` | 796,5 → 792,1 | 55,57 → 54,26 | 100,4 / 5,9; 496,8 | `11-agregacao-vendas-por-dia` | sem ganho, não adotada |
| #12 índice `lower(email)` | H12: reduz `cliente-por-email` | 796,5 → 698,6 | 55,57 → 65,71 | 64,1 / 48,6; 501,5 | `12-indice-email-clientes` | confirmada |
| #13 tirar `observacoes` do SELECT | H13: mais req/s | 698,6 → 521,1 | 65,71 → 87,66 | 93,0 / 43,1; 492,7 | `13-vendas-sem-observacoes` | confirmada |
| #14 listagem com junção adiada e `VACUUM` | H14: menos blocos lidos | 521,1 → 406,9 | 87,66 → 107,34 | 65,2 / 49,5; 486,5 | `14-listagem-juncao-adiada` | confirmada |
| #15 agregar vendas no SQL | H15: menos CPU da API | 406,9 → 399,9 | 107,3 → 131,0 | 98,8 / 11,2; 497,1 | `15-vendas-agregacao-sql` | confirmada |
| #16 índice GIN trigram | H16: menos CPU na busca | 399,9 → 392,6 | 131,0 → 169,6 | 100,6 / 14,7; 498,2 | `16-indice-trigram-produtos` | confirmada |
| #17 desligar o paralelismo | H17: plano serial é mais barato | 392,6 → 215,1 | 169,6 → 270,9 | 99,5 / 21,2; 510,3 | `17-sem-paralelismo-banco` | confirmada |
| #18 view `mv_vendas_por_dia` | H18: menos CPU do banco | 215,1 → 71,7 | 270,9 → 686,5 | 51,6 / 49,8; 468,0 | `18-view-vendas-por-dia` | confirmada; a API vira o limite |

O que não funcionou: o #5 piorou o p95 e o p99; o #11 não ganhou, e a leitura (inferência) é que o banco ainda era o limite, já que o #15, depois que a API virou o limite, deu +22,0%; o #4 funcionou, mas ficou de fora pelo serviço extra. Há efeitos que não expliquei: no #9 a mediana total subiu (291,9 → 398,1 ms) com a rota-alvo 67% mais rápida, e o p95 e o p99 de `pedidos-por-status` pioraram nos #7 e #13, com causa não investigada. O ruído sem mudança de código, medido na primeira tentativa do #10 (uma view sem uso), foi de +2,6% em req/s no total, com 7 das 18 comparações por rota piorando até +8,3%.

## 7. Limites e testes futuros

O teste é sintético, de laço fechado (20 usuários sem pausa) e com um só tamanho de dados: ele mede a capacidade máxima, não uma carga típica, e o p95 inclui espera em fila que num uso normal não existiria. As views materializadas refletem o último `REFRESH`, que aqui é a criação do banco, porque a API só tem rotas GET; com escrita, seria preciso decidir quando atualizar. A memória do banco chegou a 510,3 MiB dos 512 MiB no #17, com causa não investigada, e as três execuções do #18 variaram de 673,5 a 753,1 req/s. Não verifiquei o comportamento com um volume de dados maior, nem com chegadas em taxa fixa. Eu mudaria de conclusão se uma repetição com outro conjunto de dados invertesse a ordem dos ganhos, ou se o uso real fosse dominado por consultas que as views não cobrem. Ficaram para o [`proximos-testes.md`](../proximos-testes.md) a paginação por chave (seek method), um data warehouse para as rotas de relatório e as instruções preparadas nomeadas.

## 8. Referências

1. PostgreSQL 16. *Introduction (Indexes).* https://www.postgresql.org/docs/16/indexes-intro.html. Acesso em 08/11/2026.
2. PostgreSQL 16. *Indexes and ORDER BY.* https://www.postgresql.org/docs/16/indexes-ordering.html. Acesso em 16/11/2026.
3. PostgreSQL 16. *Indexes on Expressions.* https://www.postgresql.org/docs/16/indexes-expressional.html. Acesso em 17/11/2026.
4. PostgreSQL 16. *pg_trgm: trigram matching.* https://www.postgresql.org/docs/16/pgtrgm.html. Acesso em 18/11/2026.
5. PostgreSQL 16. *Index-Only Scans and Covering Indexes.* https://www.postgresql.org/docs/16/indexes-index-only-scans.html. Acesso em 18/11/2026.
6. PostgreSQL 16. *LIMIT and OFFSET.* https://www.postgresql.org/docs/16/queries-limit.html. Acesso em 20/11/2026.
7. Winand, M. *Use The Index, Luke: Paginação sem OFFSET.* https://use-the-index-luke.com/no-offset. Acesso em 20/11/2026.
8. Winand, M. *Use The Index, Luke: Nested Loops, ORMs and the N+1 Problem.* https://use-the-index-luke.com/sql/join/nested-loops-join-n1-problem. Acesso em 17/11/2026.
9. Winand, M. *Use The Index, Luke* (seção sobre condições com funções na coluna, datas). https://use-the-index-luke.com/sql/where-clause/obfuscation/dates. Acesso em 16/11/2026.
10. PostgreSQL Wiki. *Slow Counting.* https://wiki.postgresql.org/wiki/Slow_Counting. Acesso em 17/11/2026.
11. node-postgres. *Pooling.* https://node-postgres.com/features/pooling. Acesso em 15/11/2026.
12. PgBouncer. *Features.* https://www.pgbouncer.org/features.html. Acesso em 15/11/2026.
13. Pgpool-II. *What is Pgpool-II?* https://www.pgpool.net/docs/latest/en/html/intro-whatis.html. Acesso em 15/11/2026.
14. PostgreSQL 16. *PREPARE.* https://www.postgresql.org/docs/16/sql-prepare.html. Acesso em 20/11/2026.
15. PostgreSQL 16. *Materialized Views.* https://www.postgresql.org/docs/16/rules-materializedviews.html. Acesso em 16/11/2026.
16. Stonebraker, M. et al. *C-Store: A Column-oriented DBMS.* VLDB 2005. https://dsl.cds.iisc.ac.in/~course/DBMS/papers/cstore.pdf. Acesso em 20/11/2026.
17. PostgreSQL 16. *How Parallel Query Works.* https://www.postgresql.org/docs/16/how-parallel-query-works.html. Acesso em 18/11/2026.
18. PostgreSQL 16. *Resource Consumption (max_parallel_workers_per_gather).* https://www.postgresql.org/docs/16/runtime-config-resource.html. Acesso em 18/11/2026.
19. Gunther, N. J. *A General Theory of Computational Scalability Based on Rational Functions.* arXiv:0808.1431, 2008. https://arxiv.org/abs/0808.1431. Acesso em 18/11/2026.

## 9. Uso de IA

Usei o Claude (Anthropic) para planejar o ciclo de experimentos, gerar comandos e scripts, revisar hipóteses e rascunhar este texto.