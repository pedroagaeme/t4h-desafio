-- #14: preenche o mapa de visibilidade de `pedidos`, para a listagem poder usar Index Only Scan.
VACUUM (ANALYZE) pedidos;
