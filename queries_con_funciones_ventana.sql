-- =====================================================================
-- Ejercicio 2.1 - Funciones de Ventana
-- TP IBD - Etapa 2: SQL Avanzado


-- =====================================================================
-- CONSULTA 1: Ranking de productos mas rentables DENTRO de cada categoria
-- =====================================================================
-- (a) PREGUNTA DE NEGOCIO:
--     "Dentro de cada categoria de producto, ¿cuales son los 3 productos
--      que mas profit (ganancia) generaron, y que porcentaje del profit
--      total de su categoria representa cada uno?"
--     Sirve para decidir surtido, negociacion con proveedores y donde
--     concentrar promociones por categoria.
--
-- (b) POR QUE FUNCION DE VENTANA:
--     Necesitamos rankear y comparar cada producto CONTRA su categoria,
--     manteniendo el detalle por producto. Un GROUP BY por categoria
--     colapsaria la informacion y perderiamos el detalle de cada producto;
--     un GROUP BY por (categoria, producto) no permite, en la misma pasada,
--     calcular el ranking ni el porcentaje sobre el total de la categoria.
--     DENSE_RANK() OVER (PARTITION BY categoria ORDER BY profit DESC) y
--     SUM() OVER (PARTITION BY categoria) resuelven ambas cosas a la vez.
--
-- (c) RESULTADO ESPERADO:
--     Una fila por producto con ventas, ordenado por categoria y posicion.
--     Filtramos al top 3 de cada categoria. La columna pct_profit_categoria
--     muestra cuanto pesa ese producto en la ganancia de su categoria
--     (ej: un producto "estrella" puede concentrar >40% del profit).
--
-- >>> POR QUE SE NECESITA FUNCION DE VENTANA Y NO ALCANZA UN GROUP BY <<<
--     El ranking (posicion_en_categoria) y el porcentaje sobre el total de
--     la categoria (pct_profit_categoria) son metricas a NIVEL GRUPO
--     (categoria), pero deben mostrarse en CADA fila de producto. Un GROUP BY
--     por categoria devuelve una sola fila por categoria: para conocer el % de
--     un producto haria falta el total de la categoria Y el detalle del
--     producto en la misma fila, dos granularidades distintas que GROUP BY no
--     puede combinar en una pasada. Hoy se resolveria con una subconsulta
--     correlacionada o un self-join extra por cada metrica; ademas, no existe
--     ninguna funcion de agregacion clasica que produzca un "ranking" (RANK/
--     DENSE_RANK solo existen como funciones de ventana). PARTITION BY agrupa
--     SIN colapsar, devolviendo el agregado de la categoria junto al detalle.
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
    JOIN PRODUCTOS  p ON p.product_id   = dv.product_id   -- solo lineas de producto (no combos)
    JOIN CATEGORIAS c ON c.categoria_id = p.categoria_id
    WHERE dv.product_id IS NOT NULL
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
        ) AS posicion_en_categoria,
        -- Participacion del producto en el profit total de su categoria
        ROUND(
            100.0 * profit_total
            / NULLIF(SUM(profit_total) OVER (PARTITION BY categoria_id), 0),
            2
        ) AS pct_profit_categoria
    FROM profit_por_producto
)
SELECT
    categoria,
    posicion_en_categoria,
    producto,
    unidades_vendidas,
    ingresos,
    profit_total,
    pct_profit_categoria
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
    c.apellido || ', ' || c.nombre                 AS cliente,
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
