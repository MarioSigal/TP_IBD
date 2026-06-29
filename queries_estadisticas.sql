-- C1: Para cada columna: cantidad total de filas, cantidad y porcentaje de filas con valor no
--nulo, cantidad de valores diferentes
WITH ventas_ext AS (
    -- Reconstruye los totales por venta desde el detalle (ya no son columnas)
    SELECT
        v.venta_id,
        v.cliente_id,
        v.puntos_de_venta_id,
        v.fecha,
        v.hora,
        mp.nombre                                              AS metodo_pago,
        SUM(dv.cantidad * dv.precio_unidad)                     AS precio_total,
        SUM(dv.cantidad * dv.costo_unidad)                      AS costo_total
    FROM VENTAS v
    JOIN DETALLE_VENTAS dv ON dv.venta_id = v.venta_id
    JOIN METODOS_PAGO  mp ON mp.metodo_pago_id = v.metodo_pago_id   -- metodo_pago ahora es una entidad
    GROUP BY v.venta_id, v.cliente_id, v.puntos_de_venta_id, v.fecha, v.hora, mp.nombre
),
perfil_columnas AS (
    SELECT 'venta_id'           AS columna, 1 AS orden,
           COUNT(*)             AS total_filas,
           COUNT(venta_id)      AS no_nulos,
           COUNT(DISTINCT venta_id) AS valores_distintos
    FROM ventas_ext
    UNION ALL
    SELECT 'cliente_id', 2,
           COUNT(*), COUNT(cliente_id), COUNT(DISTINCT cliente_id) FROM ventas_ext
    UNION ALL
    SELECT 'puntos_de_venta_id', 3,
           COUNT(*), COUNT(puntos_de_venta_id), COUNT(DISTINCT puntos_de_venta_id) FROM ventas_ext
    UNION ALL
    SELECT 'fecha', 4,
           COUNT(*), COUNT(fecha), COUNT(DISTINCT fecha) FROM ventas_ext
    UNION ALL
    SELECT 'hora', 5,
           COUNT(*), COUNT(hora), COUNT(DISTINCT hora) FROM ventas_ext
    UNION ALL
    SELECT 'metodo_pago', 6,
           COUNT(*), COUNT(metodo_pago), COUNT(DISTINCT metodo_pago) FROM ventas_ext
    UNION ALL
    SELECT 'precio_total', 7,
           COUNT(*), COUNT(precio_total), COUNT(DISTINCT precio_total) FROM ventas_ext
    UNION ALL
    SELECT 'costo_total', 8,
           COUNT(*), COUNT(costo_total), COUNT(DISTINCT costo_total) FROM ventas_ext
)
SELECT
    columna,
    total_filas,
    no_nulos,
    ROUND(100.0 * no_nulos / NULLIF(total_filas, 0), 2) AS pct_no_nulos,
    valores_distintos
FROM perfil_columnas
ORDER BY orden;


-- C2: Para cada columna considerada numérica: desvío estandard, mínimo, P05, primer cuartil,
--mediana, promedio, tercer cuartil, P95, máximo, cantidad y porcentaje de ceros, cantidad y
--porcentaje de valores negativos, cantidad de outliers
WITH ventas_ext AS (
    SELECT
        v.venta_id,
        SUM(dv.cantidad * dv.precio_unidad) AS precio_total,
        SUM(dv.cantidad * dv.costo_unidad)  AS costo_total
    FROM VENTAS v
    JOIN DETALLE_VENTAS dv ON dv.venta_id = v.venta_id
    GROUP BY v.venta_id
),
valores_numericos AS (
    SELECT 'precio_total' AS columna, precio_total AS valor FROM ventas_ext
    UNION ALL
    SELECT 'costo_total',            costo_total          FROM ventas_ext
),
limites AS (
    -- Cuartiles e IQR por columna, base para detectar outliers
    SELECT
        columna,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valor) AS q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valor) AS q3
    FROM valores_numericos
    WHERE valor IS NOT NULL
    GROUP BY columna
)
SELECT
    v.columna,
    COUNT(v.valor)                                              AS n_no_nulos,
    ROUND(STDDEV_SAMP(v.valor), 2)                              AS desvio_std,
    MIN(v.valor)                                               AS minimo,
    ROUND((PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY v.valor))::numeric, 2) AS p05,
    ROUND(l.q1::numeric, 2)                                    AS q1,
    ROUND((PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY v.valor))::numeric, 2) AS mediana,
    ROUND(AVG(v.valor), 2)                                     AS promedio,
    ROUND(l.q3::numeric, 2)                                    AS q3,
    ROUND((PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY v.valor))::numeric, 2) AS p95,
    MAX(v.valor)                                               AS maximo,
    COUNT(*) FILTER (WHERE v.valor = 0)                        AS cant_ceros,
    ROUND(100.0 * COUNT(*) FILTER (WHERE v.valor = 0)
          / NULLIF(COUNT(v.valor), 0), 2)                      AS pct_ceros,
    COUNT(*) FILTER (WHERE v.valor < 0)                        AS cant_negativos,
    ROUND(100.0 * COUNT(*) FILTER (WHERE v.valor < 0)
          / NULLIF(COUNT(v.valor), 0), 2)                      AS pct_negativos,
    COUNT(*) FILTER (
        WHERE v.valor < l.q1 - 1.5 * (l.q3 - l.q1)
           OR v.valor > l.q3 + 1.5 * (l.q3 - l.q1)
    )                                                          AS cant_outliers
FROM valores_numericos v
JOIN limites l USING (columna)
WHERE v.valor IS NOT NULL
GROUP BY v.columna, l.q1, l.q3
ORDER BY v.columna;


-- C3: Para cada columna considerada categórica: la frecuencia y el porcentaje de los hasta 10
--valores más frecuentes (de mayor a menor frecuencia), y del resto.
WITH conteo AS (
    SELECT mp.nombre AS valor, COUNT(*) AS frecuencia
    FROM VENTAS v
    JOIN METODOS_PAGO mp ON mp.metodo_pago_id = v.metodo_pago_id
    GROUP BY mp.nombre
),
ranked AS (
    SELECT
        valor,
        frecuencia,
        ROW_NUMBER() OVER (ORDER BY frecuencia DESC) AS rn,
        SUM(frecuencia) OVER ()                      AS total
    FROM conteo
)
SELECT
    'metodo_pago' AS columna,
    CASE WHEN rn <= 10 THEN valor ELSE '(resto)' END AS valor,
    SUM(frecuencia)                                  AS frecuencia,
    ROUND(100.0 * SUM(frecuencia) / MAX(total), 2)   AS porcentaje
FROM ranked
GROUP BY CASE WHEN rn <= 10 THEN valor ELSE '(resto)' END
ORDER BY frecuencia DESC;

WITH conteo AS (
    SELECT puntos_de_venta_id::text AS valor, COUNT(*) AS frecuencia
    FROM VENTAS
    GROUP BY puntos_de_venta_id
),
ranked AS (
    SELECT
        valor,
        frecuencia,
        ROW_NUMBER() OVER (ORDER BY frecuencia DESC) AS rn,
        SUM(frecuencia) OVER ()                      AS total
    FROM conteo
)
SELECT
    'puntos_de_venta_id' AS columna,
    CASE WHEN rn <= 10 THEN valor ELSE '(resto)' END AS valor,
    SUM(frecuencia)                                  AS frecuencia,
    ROUND(100.0 * SUM(frecuencia) / MAX(total), 2)   AS porcentaje
FROM ranked
GROUP BY CASE WHEN rn <= 10 THEN valor ELSE '(resto)' END
ORDER BY frecuencia DESC;
