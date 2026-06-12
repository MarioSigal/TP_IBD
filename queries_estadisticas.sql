-- =====================================================================
-- Ejercicio 2.2 - Funciones estadisticas
-- TP IBD - Etapa 2: SQL Avanzado
-- =====================================================================
-- Dominio: comercio minorista. Tabla analizada: VENTAS.
--
-- Se eligio VENTAS porque combina los tres perfiles de columna que pide la
-- consigna:
--   * Numericas:    precio_total, costo_total.
--   * Categoricas:  metodo_pago, estado_entrega.
--   * Nullable:     cliente_id (ventas sin cliente identificado), util para
--                   que el porcentaje de no-nulos de C1 no sea siempre 100%.
-- =====================================================================


-- =====================================================================
-- C1: Perfil general de CADA columna
-- =====================================================================
-- Para cada columna informa:
--   * cantidad total de filas de la tabla,
--   * cantidad de filas con valor no nulo,
--   * porcentaje de filas con valor no nulo,
--   * cantidad de valores diferentes (distintos).
--
-- Tecnica: como cada columna tiene un tipo distinto, se calcula el perfil
-- por columna y se apilan los resultados con UNION ALL en formato "largo"
-- (una fila por columna). COUNT(col) ignora NULLs, mientras que COUNT(*)
-- cuenta todas las filas: la diferencia entre ambos es la cantidad de NULLs.
WITH perfil_columnas AS (
    SELECT 'venta_id'           AS columna, 1 AS orden,
           COUNT(*)             AS total_filas,
           COUNT(venta_id)      AS no_nulos,
           COUNT(DISTINCT venta_id) AS valores_distintos
    FROM VENTAS
    UNION ALL
    SELECT 'cliente_id', 2,
           COUNT(*), COUNT(cliente_id), COUNT(DISTINCT cliente_id) FROM VENTAS
    UNION ALL
    SELECT 'puntos_de_venta_id', 3,
           COUNT(*), COUNT(puntos_de_venta_id), COUNT(DISTINCT puntos_de_venta_id) FROM VENTAS
    UNION ALL
    SELECT 'fecha', 4,
           COUNT(*), COUNT(fecha), COUNT(DISTINCT fecha) FROM VENTAS
    UNION ALL
    SELECT 'hora', 5,
           COUNT(*), COUNT(hora), COUNT(DISTINCT hora) FROM VENTAS
    UNION ALL
    SELECT 'precio_total', 6,
           COUNT(*), COUNT(precio_total), COUNT(DISTINCT precio_total) FROM VENTAS
    UNION ALL
    SELECT 'costo_total', 7,
           COUNT(*), COUNT(costo_total), COUNT(DISTINCT costo_total) FROM VENTAS
    UNION ALL
    SELECT 'metodo_pago', 8,
           COUNT(*), COUNT(metodo_pago), COUNT(DISTINCT metodo_pago) FROM VENTAS
    UNION ALL
    SELECT 'estado_entrega', 9,
           COUNT(*), COUNT(estado_entrega), COUNT(DISTINCT estado_entrega) FROM VENTAS
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
-- Para precio_total y costo_total informa: desvio estandar, minimo, P05,
-- primer cuartil (Q1), mediana, promedio, tercer cuartil (Q3), P95, maximo,
-- cantidad y porcentaje de ceros, cantidad y porcentaje de negativos y
-- cantidad de outliers.
--
-- Tecnica:
--   1. Se "despivotan" las columnas numericas a formato largo (columna, valor)
--      con UNION ALL, de modo de calcular los estadisticos de ambas en una
--      sola pasada agrupando por 'columna'.
--   2. Los percentiles se calculan con PERCENTILE_CONT (interpolado) como
--      funciones de conjunto ordenado: PERCENTILE_CONT(p) WITHIN GROUP (...).
--   3. Outliers por la regla de Tukey (rango intercuartilico): se consideran
--      atipicos los valores fuera de [Q1 - 1.5*IQR ; Q3 + 1.5*IQR], con
--      IQR = Q3 - Q1. Los limites se precalculan en la CTE 'limites' y se
--      reutilizan con COUNT(*) FILTER para contar cuantos los exceden.
WITH valores_numericos AS (
    SELECT 'precio_total' AS columna, precio_total AS valor FROM VENTAS
    UNION ALL
    SELECT 'costo_total',            costo_total          FROM VENTAS
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
    ROUND(PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY v.valor), 2) AS p05,
    ROUND(l.q1, 2)                                             AS q1,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY v.valor), 2) AS mediana,
    ROUND(AVG(v.valor), 2)                                     AS promedio,
    ROUND(l.q3, 2)                                             AS q3,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY v.valor), 2) AS p95,
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
-- Tecnica:
--   1. CTE 'conteo': frecuencia por valor (GROUP BY).
--   2. CTE 'ranked': ROW_NUMBER() ordena los valores por frecuencia desc y
--      SUM(frec) OVER () guarda el total de filas para calcular porcentajes.
--   3. SELECT final: los valores con rn <= 10 quedan individuales; el resto
--      se colapsa en la etiqueta '(resto)'. Si la columna tiene <= 10 valores
--      distintos (como aca), '(resto)' simplemente no aparece.
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

-- ---- C3.b: estado_entrega ----
WITH conteo AS (
    SELECT estado_entrega AS valor, COUNT(*) AS frecuencia
    FROM VENTAS
    GROUP BY estado_entrega
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
    'estado_entrega' AS columna,
    CASE WHEN rn <= 10 THEN valor ELSE '(resto)' END AS valor,
    SUM(frecuencia)                                  AS frecuencia,
    ROUND(100.0 * SUM(frecuencia) / MAX(total), 2)   AS porcentaje
FROM ranked
GROUP BY CASE WHEN rn <= 10 THEN valor ELSE '(resto)' END
ORDER BY frecuencia DESC;
