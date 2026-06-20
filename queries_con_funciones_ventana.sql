-- =====================================================================
-- Ejercicio 2.1 - Funciones de Ventana
-- TP IBD - Etapa 2: SQL Avanzado


-- =====================================================================
-- CONSULTA 1: Ranking de productos mas rentables DENTRO de cada categoria
-- =====================================================================
-- (a) PREGUNTA DE NEGOCIO:
--     "Dentro de cada categoria de producto, ¿cuales son los 3 productos
--      que mas profit (ganancia) generaron?"
--     Sirve para decidir surtido, negociacion con proveedores y donde
--     concentrar promociones por categoria.
--
-- (b) POR QUE FUNCION DE VENTANA:
--     Necesitamos rankear cada producto DENTRO de su categoria, manteniendo
--     el detalle por producto. Un GROUP BY por categoria colapsaria la
--     informacion y perderiamos el detalle de cada producto; un GROUP BY por
--     (categoria, producto) no permite, en la misma pasada, calcular el
--     ranking dentro de cada categoria.
--     DENSE_RANK() OVER (PARTITION BY categoria ORDER BY profit DESC)
--     resuelve el ranking sin colapsar las filas.
--
-- (c) RESULTADO ESPERADO:
--     Una fila por producto con ventas, ordenado por categoria y posicion.
--     Filtramos al top 3 de cada categoria. Como usamos DENSE_RANK, si hay
--     empates en una posicion pueden aparecer mas de 3 productos por
--     categoria (todos los que comparten las primeras 3 posiciones).
--
-- >>> POR QUE SE NECESITA FUNCION DE VENTANA Y NO ALCANZA UN GROUP BY <<<
--     El ranking (posicion_en_categoria) es una metrica a NIVEL GRUPO
--     (categoria) que ordena los productos entre si, pero debe mostrarse en
--     CADA fila de producto. Un GROUP BY por categoria devuelve una sola fila
--     por categoria y colapsa el detalle de los productos, por lo que no
--     puede asignar una posicion a cada uno. Ademas, no existe ninguna
--     funcion de agregacion clasica que produzca un "ranking" (RANK/
--     DENSE_RANK solo existen como funciones de ventana). PARTITION BY agrupa
--     SIN colapsar, devolviendo el ranking de la categoria junto al detalle.
WITH profit_por_producto AS (
    SELECT
        c.categoria_id,
        c.nombre                         AS categoria,
        p.product_id,
        p.nombre                         AS producto,
        SUM(dv.cantidad)                 AS unidades_vendidas,
        SUM(dv.subtotal)                 AS ingresos,
        SUM(dv.profit)                   AS profit_total
    FROM DETALLE_VENTAS dv
    JOIN PRODUCTOS  p ON p.product_id   = dv.product_id
    JOIN CATEGORIAS c ON c.categoria_id = p.categoria_id
    GROUP BY c.categoria_id, c.nombre, p.product_id, p.nombre
),
ranking AS (
    SELECT
        categoria,
        producto,
        unidades_vendidas,
        ingresos,
        profit_total,
        -- Posicion del producto dentro de su categoria por profit
        DENSE_RANK() OVER (
            PARTITION BY categoria_id
            ORDER BY profit_total DESC
        ) AS posicion_en_categoria
    FROM profit_por_producto
)
SELECT
    categoria,
    posicion_en_categoria,
    producto,
    unidades_vendidas,
    ingresos,
    profit_total
FROM ranking
WHERE posicion_en_categoria <= 3
ORDER BY categoria, posicion_en_categoria;


-- =====================================================================
-- CONSULTA 2: Comportamiento de compra de cada cliente a lo largo del tiempo
--             (gasto acumulado, dias desde la compra anterior y ticket #)
-- =====================================================================
-- (a) PREGUNTA DE NEGOCIO:
--     "Para cada cliente identificado, ¿como es su historial de compras?
--      Para cada venta: ¿que numero de compra es para ese cliente, cuanto
--      lleva gastado acumulado y cuantos dias pasaron desde su compra
--      anterior?"
--     Sirve para analizar recencia/frecuencia, detectar clientes que dejan
--     de comprar y medir el valor acumulado del cliente (CLV simplificado).
--
-- (b) POR QUE FUNCION DE VENTANA:
--     Cada metrica mira la secuencia de compras del cliente:
--       - ROW_NUMBER(): numero de compra ordinal por cliente.
--       - SUM() OVER (... ORDER BY ...): total acumulado (running total),
--         que requiere un marco de ventana ordenado, imposible con GROUP BY.
--       - LAG(fecha): fecha de la compra anterior para medir el intervalo
--         entre compras sucesivas.
--     GROUP BY solo daria totales por cliente, perdiendo la secuencia
--     temporal y la relacion entre compras consecutivas.
--
-- (c) RESULTADO ESPERADO:
--     Una fila por venta de cada cliente identificado, ordenada
--     cronologicamente. nro_compra_cliente crece de 1 en adelante,
--     gasto_acumulado suma el historico hasta esa compra y
--     dias_desde_compra_anterior es NULL en la primera compra y luego mide
--     el espaciamiento (utilidad para alertas de inactividad).
--
-- >>> POR QUE SE NECESITA FUNCION DE VENTANA Y NO ALCANZA UN GROUP BY <<<
--     Las tres metricas dependen del ORDEN y de la POSICION de cada compra
--     dentro del historial del cliente, no de un agregado global. GROUP BY no
--     tiene concepto de "fila anterior" ni de "orden": colapsa todas las
--     compras del cliente en una sola fila, por lo que es imposible numerar la
--     n-esima compra (ROW_NUMBER), acumular el gasto compra a compra
--     manteniendo el detalle de cada una (SUM con marco ROWS ... CURRENT ROW)
--     o leer la fecha de la compra previa para medir el intervalo (LAG). Un
--     GROUP BY por cliente solo daria totales/promedios y se perderia toda la
--     secuencia temporal. La funcion de ventana ordena dentro de la particion
--     del cliente y calcula cada metrica fila por fila sin colapsarlas.
SELECT
    c.cliente_id,
    c.nombre,
    c.apellido,
    v.venta_id,
    v.fecha,
    v.precio_total,
    -- Numero ordinal de compra del cliente (1 = primera compra)
    ROW_NUMBER() OVER (
        PARTITION BY c.cliente_id
        ORDER BY v.fecha, v.hora, v.venta_id
    ) AS nro_compra_cliente,
    -- Gasto acumulado del cliente hasta esta compra inclusive (running total)
    SUM(v.precio_total) OVER (
        PARTITION BY c.cliente_id
        ORDER BY v.fecha, v.hora, v.venta_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS gasto_acumulado,
    -- Dias transcurridos desde la compra inmediatamente anterior del cliente
    v.fecha - LAG(v.fecha) OVER (
        PARTITION BY c.cliente_id
        ORDER BY v.fecha, v.hora, v.venta_id
    ) AS dias_desde_compra_anterior
FROM VENTAS v
JOIN CLIENTES c ON c.cliente_id = v.cliente_id   -- solo ventas con cliente identificado
ORDER BY c.cliente_id, nro_compra_cliente;
