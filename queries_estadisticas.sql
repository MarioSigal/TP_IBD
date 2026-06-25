-- =====================================================================
-- Ejercicio 2.2 - Funciones estadisticas
-- TP IBD - Etapa 2: SQL Avanzado
-- =====================================================================
-- Dominio: comercio minorista. Tabla analizada: VENTAS.
--
-- IMPORTANTE (nuevo modelo): VENTAS ya NO almacena precio_total ni
-- costo_total (son derivables del detalle) y se elimino estado_entrega.
-- Por eso TODAS las consultas parten de una CTE 'ventas_ext' que reconstruye
-- esos totales por venta a partir de DETALLE_VENTAS. Esto cumple ademas el
-- requisito de usar Common Table Expressions (WITH).
--
-- 'ventas_ext' combina los tres perfiles de columna que pide la consigna:
--   * Numericas:    precio_total, costo_total (calculadas).
--   * Categoricas:  metodo_pago, puntos_de_venta_id (sucursal).
--   * Nullable:     cliente_id (ventas sin cliente identificado), util para
--                   que el porcentaje de no-nulos de C1 no sea siempre 100%.
-- =====================================================================


-- =====================================================================
-- C1: Perfil general de CADA columna
-- =====================================================================
-- Para cada columna informa: cantidad total de filas, filas no nulas,
-- porcentaje de filas no nulas y cantidad de valores diferentes.
-- COUNT(col) ignora NULLs y COUNT(*) cuenta todo: su diferencia son los NULLs.
WITH ventas_ext AS (
    -- Reconstruye los totales por venta desde el detalle (ya no son columnas)
    SELECT
        v.venta_id,
        v.cliente_id,
        v.puntos_de_venta_id,
        v.fecha,
        v.hora,
        v.metodo_pago,
        SUM(dv.cantidad * dv.precio_unidad)                     AS precio_total,
        SUM(dv.cantidad * dv.costo_unidad)                      AS costo_total
    FROM VENTAS v
    JOIN DETALLE_VENTAS dv ON dv.venta_id = v.venta_id
    GROUP BY v.venta_id, v.cliente_id, v.puntos_de_venta_id, v.fecha, v.hora, v.metodo_pago
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


-- =====================================================================
-- C2: Estadisticos descriptivos de las columnas NUMERICAS
-- =====================================================================
-- Para precio_total y costo_total (calculadas por venta): desvio estandar,
-- minimo, P05, Q1, mediana, promedio, Q3, P95, maximo, cantidad y porcentaje
-- de ceros, cantidad y porcentaje de negativos y cantidad de outliers.
--
-- Tecnica:
--   1. ventas_ext reconstruye los totales por venta.
--   2. Se "despivotan" las dos columnas numericas a formato largo
--      (columna, valor) con UNION ALL, para calcular ambas en una sola pasada.
--   3. Percentiles con PERCENTILE_CONT (interpolado).
--   4. Outliers por la regla de Tukey: fuera de [Q1 - 1.5*IQR ; Q3 + 1.5*IQR].
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


-- =====================================================================
-- C3: Distribucion de frecuencias de las columnas CATEGORICAS
-- =====================================================================
-- Para cada columna categorica muestra los hasta 10 valores mas frecuentes
-- (de mayor a menor frecuencia) con su frecuencia y porcentaje, y agrupa
-- todo lo que queda por debajo del top 10 en una unica fila '(resto)'.
--
-- Como VENTAS ya no tiene estado_entrega, las dos columnas categoricas
-- analizadas son metodo_pago y puntos_de_venta_id (la sucursal).
--
-- Tecnica:
--   1. CTE 'conteo': frecuencia por valor (GROUP BY).
--   2. CTE 'ranked': ROW_NUMBER() ordena por frecuencia desc y
--      SUM(frec) OVER () guarda el total de filas para los porcentajes.
--   3. SELECT final: rn <= 10 quedan individuales; el resto -> '(resto)'.
--
-- ---- C3.a: metodo_pago ----
WITH conteo AS (
    SELECT metodo_pago AS valor, COUNT(*) AS frecuencia
    FROM VENTAS
    GROUP BY metodo_pago
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

-- ---- C3.b: puntos_de_venta_id (sucursal) ----
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
