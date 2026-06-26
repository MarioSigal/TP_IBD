-- ============================================================================
-- SCRIPT DE VALIDACION DE CONSISTENCIA Y ESTADISTICOS - TP IBD (EJERCICIO 1.3)
-- ============================================================================
-- Este script realiza comprobaciones logicas sobre los datos poblados
-- y genera reportes estadisticos para variables numericas y categoricas.
--
-- NUEVO MODELO: VENTAS ya no guarda precio_total/costo_total/estado_entrega y
-- los detalles ya no guardan subtotal/profit (son derivables). Por eso los
-- montos por venta se RECONSTRUYEN desde DETALLE_VENTAS con funciones de
-- agrupacion.
-- ============================================================================

-- ============================================================================
-- 1. CONSULTAS DE VALIDACION DE CONSISTENCIA LOGICA
--    (todas deben retornar 0 filas si los datos son consistentes)
-- ============================================================================

-- VALIDACION A: Integridad referencial de la venta en el detalle
-- Busca lineas de DETALLE_VENTAS cuyo venta_id no exista en VENTAS.
SELECT dv.*
FROM DETALLE_VENTAS dv
LEFT JOIN VENTAS v ON v.venta_id = dv.venta_id
WHERE v.venta_id IS NULL;

-- VALIDACION B: Integridad referencial de producto en el detalle de ventas
-- Busca filas cuyo product_id no exista en PRODUCTOS.
SELECT dv.*
FROM DETALLE_VENTAS dv
LEFT JOIN PRODUCTOS p ON p.product_id = dv.product_id
WHERE p.product_id IS NULL;

-- VALIDACION C: Ventas sin ninguna linea de detalle (cabecera huerfana)
-- Una venta siempre debe tener al menos un producto.
SELECT v.venta_id
FROM VENTAS v
LEFT JOIN DETALLE_VENTAS dv ON dv.venta_id = v.venta_id
WHERE dv.venta_id IS NULL;

-- VALIDACION D: Coherencia de margen (no se vende por debajo del costo)
-- Como el precio de catalogo se fija con markup sobre el costo, no deberia
-- existir ninguna linea con precio_unidad < costo_unidad (profit negativo).
SELECT dv.detalle_venta_id, dv.venta_id, dv.product_id,
       dv.precio_unidad, dv.costo_unidad
FROM DETALLE_VENTAS dv
WHERE dv.precio_unidad < dv.costo_unidad;


-- ============================================================================
-- 2. REPORTES ESTADISTICOS (estilo practica)
-- ============================================================================
-- Se reconstruyen los totales por venta desde el detalle en una CTE comun.

-- CONSULTA C1: Frecuencias generales de columnas de la venta
-- Total de filas, no nulos, % no nulos y valores unicos para campos clave.
WITH ventas_ext AS (
    SELECT
        v.venta_id,
        v.cliente_id,
        mp.nombre AS metodo_pago,
        SUM(dv.cantidad * dv.precio_unidad) AS precio_total
    FROM VENTAS v
    JOIN DETALLE_VENTAS dv ON dv.venta_id = v.venta_id
    JOIN METODOS_PAGO  mp ON mp.metodo_pago_id = v.metodo_pago_id
    GROUP BY v.venta_id, v.cliente_id, mp.nombre
)
SELECT
    COUNT(*) AS total_registros,
    -- Columna cliente_id (nullable)
    COUNT(cliente_id) AS cant_no_nulo_cliente,
    ROUND(COUNT(cliente_id) * 100.0 / COUNT(*), 2) AS pct_no_nulo_cliente,
    COUNT(DISTINCT cliente_id) AS cant_distintos_cliente,
    -- Columna precio_total (calculada)
    COUNT(precio_total) AS cant_no_nulo_monto,
    ROUND(COUNT(precio_total) * 100.0 / COUNT(*), 2) AS pct_no_nulo_monto,
    COUNT(DISTINCT precio_total) AS cant_distintos_monto,
    -- Columna metodo_pago
    COUNT(metodo_pago) AS cant_no_nulo_pago,
    ROUND(COUNT(metodo_pago) * 100.0 / COUNT(*), 2) AS pct_no_nulo_pago,
    COUNT(DISTINCT metodo_pago) AS cant_distintos_pago
FROM ventas_ext;


-- CONSULTA C2: Estadisticos numericos completos (precio_total por venta)
-- Desviacion estandar, percentiles (P05, Q1, Mediana, Q3, P95), outliers, etc.
WITH ventas_ext AS (
    SELECT
        v.venta_id,
        SUM(dv.cantidad * dv.precio_unidad) AS precio_total
    FROM VENTAS v
    JOIN DETALLE_VENTAS dv ON dv.venta_id = v.venta_id
    GROUP BY v.venta_id
),
EstadisticosBase AS (
    SELECT
        COUNT(*) AS N,
        COUNT(precio_total) AS N_NoNulo,
        MIN(precio_total) AS Minimo,
        MAX(precio_total) AS Maximo,
        AVG(precio_total) AS Promedio,
        STDDEV(precio_total) AS Desvio_Estandard,
        PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY precio_total) AS P05,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY precio_total) AS Q1,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY precio_total) AS Mediana,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY precio_total) AS Q3,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY precio_total) AS P95,
        COUNT(CASE WHEN precio_total = 0 THEN 1 END) AS Cant_Ceros,
        COUNT(CASE WHEN precio_total < 0 THEN 1 END) AS Cant_Negativos
    FROM ventas_ext
),
LimitesOutliers AS (
    SELECT
        *,
        (Q3 - Q1) AS IQR,
        (Q1 - 1.5 * (Q3 - Q1)) AS Limite_Inferior,
        (Q3 + 1.5 * (Q3 - Q1)) AS Limite_Superior
    FROM EstadisticosBase
)
SELECT
    N,
    N_NoNulo,
    ROUND(N_NoNulo * 100.0 / N, 2) AS Pct_NoNulo,
    ROUND(Promedio, 2) AS Promedio,
    ROUND(Desvio_Estandard, 2) AS Desvio_Estandard,
    Minimo, P05, Q1, Mediana, Q3, P95, Maximo,
    Cant_Ceros,
    ROUND(Cant_Ceros * 100.0 / N, 2) AS Pct_Ceros,
    Cant_Negativos,
    ROUND(Cant_Negativos * 100.0 / N, 2) AS Pct_Negativos,
    (SELECT COUNT(*) FROM ventas_ext
     WHERE precio_total < LimitesOutliers.Limite_Inferior
        OR precio_total > LimitesOutliers.Limite_Superior) AS Cant_Outliers
FROM LimitesOutliers;


-- CONSULTA C3: Estadisticos categoricos (metodo de pago)
-- metodo_pago ahora es una entidad: se resuelve el nombre via JOIN a METODOS_PAGO.
-- Frecuencia y porcentaje de participacion de cada categoria, de mayor a menor.
WITH PagoFrecuencias AS (
    SELECT
        mp.nombre AS metodo_pago,
        COUNT(*) AS Frecuencia,
        COUNT(*) * 100.0 / (SELECT COUNT(*) FROM VENTAS) AS Porcentaje
    FROM VENTAS v
    JOIN METODOS_PAGO mp ON mp.metodo_pago_id = v.metodo_pago_id
    GROUP BY mp.nombre
)
SELECT
    COALESCE(metodo_pago, 'NULO/DESCONOCIDO') AS Categoria,
    Frecuencia,
    ROUND(Porcentaje, 2) AS Porcentaje_Participacion
FROM PagoFrecuencias
ORDER BY Frecuencia DESC;
