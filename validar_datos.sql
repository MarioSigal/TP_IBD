-- ============================================================================
-- SCRIPT DE VALIDACIÓN DE CONSISTENCIA Y ESTADÍSTICOS - TP IBD (EJERCICIO 1.3)
-- ============================================================================
-- Este script realiza comprobaciones lógicas sobre los datos poblados
-- y genera reportes estadísticos para variables numéricas y categóricas.

-- ============================================================================
-- 1. CONSULTAS DE VALIDACIÓN DE CONSISTENCIA LÓGICA
-- ============================================================================

-- VALIDACIÓN A: Cuadre de montos de Ventas (Cabecera vs Detalle)
-- Verifica si hay alguna diferencia entre el total cobrado en VENTAS y la suma de subtotales.
-- La consulta debe retornar 0 filas si los datos son 100% consistentes.
SELECT 
    v.venta_id, 
    v.precio_total AS total_cabecera, 
    SUM(d.subtotal) AS total_detalle,
    ABS(v.precio_total - SUM(d.subtotal)) AS diferencia
FROM VENTAS v
JOIN DETALLE_VENTAS d ON v.venta_id = d.venta_id
GROUP BY v.venta_id, v.precio_total
HAVING ABS(v.precio_total - SUM(d.subtotal)) > 0.01;

-- VALIDACIÓN B: Cuadre de costo y ganancia en Ventas (Cabecera vs Detalle)
-- Verifica si la suma de costos y profit calculados en los detalles de cada venta 
-- coinciden con costo_total y gross_profit registrados en la cabecera.
SELECT 
    v.venta_id, 
    v.costo_total AS costo_cabecera, 
    SUM(d.cantidad * d.costo_unidad) AS costo_detalle_calculado,
    v.precio_total - v.costo_total AS profit_cabecera,
    SUM(d.profit) AS profit_detalle_calculado,
    ABS(v.costo_total - SUM(d.cantidad * d.costo_unidad)) AS dif_costo,
    ABS((v.precio_total - v.costo_total) - SUM(d.profit)) AS dif_profit
FROM VENTAS v
JOIN DETALLE_VENTAS d ON v.venta_id = d.venta_id
GROUP BY v.venta_id, v.costo_total, v.precio_total
HAVING ABS(v.costo_total - SUM(d.cantidad * d.costo_unidad)) > 0.01 
   OR ABS((v.precio_total - v.costo_total) - SUM(d.profit)) > 0.01;

-- VALIDACIÓN C: Cuadre de compras (Cabecera vs Detalle)
-- Verifica si hay diferencias entre el total facturado por el proveedor y la suma de detalles de compra.
SELECT 
    c.compra_id, 
    c.total AS total_cabecera, 
    SUM(dc.subtotal) AS total_detalle,
    ABS(c.total - SUM(dc.subtotal)) AS diferencia
FROM COMPRAS c
JOIN DETALLE_COMPRAS dc ON c.compra_id = dc.compra_id
GROUP BY c.compra_id, c.total
HAVING ABS(c.total - SUM(dc.subtotal)) > 0.01;

-- VALIDACIÓN D: Integridad referencial de producto en Detalle de Ventas
-- Busca filas cuyo product_id no exista en PRODUCTOS (no debería retornar ninguna).
SELECT dv.*
FROM DETALLE_VENTAS dv
LEFT JOIN PRODUCTOS p ON p.product_id = dv.product_id
WHERE p.product_id IS NULL;


-- ============================================================================
-- 2. REPORTES ESTADÍSTICOS (EJERCICIO 2.2 / PRÁCTICA)
-- ============================================================================

-- CONSULTA C1: Frecuencias generales de columnas de la tabla VENTAS
-- Total de filas, nulos, porcentaje no nulos y valores únicos para campos clave.
SELECT 
    -- Fila total
    COUNT(*) AS total_registros,
    
    -- Columna cliente_id
    COUNT(cliente_id) AS cant_no_nulo_cliente,
    ROUND(COUNT(cliente_id) * 100.0 / COUNT(*), 2) AS pct_no_nulo_cliente,
    COUNT(DISTINCT cliente_id) AS cant_distintos_cliente,
    
    -- Columna precio_total
    COUNT(precio_total) AS cant_no_nulo_monto,
    ROUND(COUNT(precio_total) * 100.0 / COUNT(*), 2) AS pct_no_nulo_monto,
    COUNT(DISTINCT precio_total) AS cant_distintos_monto,
    
    -- Columna metodo_pago
    COUNT(metodo_pago) AS cant_no_nulo_pago,
    ROUND(COUNT(metodo_pago) * 100.0 / COUNT(*), 2) AS pct_no_nulo_pago,
    COUNT(DISTINCT metodo_pago) AS cant_distintos_pago
FROM VENTAS;


-- CONSULTA C2: Estadísticos Numéricos Completos (para precio_total en VENTAS)
-- Incluye desviación estándar, percentiles (P05, Q1, Mediana, Q3, P95), outliers y más.
WITH EstadisticosBase AS (
    SELECT 
        COUNT(*) AS N,
        COUNT(precio_total) AS N_NoNulo,
        MIN(precio_total) AS Minimo,
        MAX(precio_total) AS Maximo,
        AVG(precio_total) AS Promedio,
        STDDEV(precio_total) AS Desvio_Estandard,
        
        -- Percentiles en PostgreSQL
        PERCENTILE_CONT(0.05) WITHIN GROUP (ORDER BY precio_total) AS P05,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY precio_total) AS Q1,
        PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY precio_total) AS Mediana,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY precio_total) AS Q3,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY precio_total) AS P95,
        
        -- Conteos específicos
        COUNT(CASE WHEN precio_total = 0 THEN 1 END) AS Cant_Ceros,
        COUNT(CASE WHEN precio_total < 0 THEN 1 END) AS Cant_Negativos
    FROM VENTAS
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
    Minimo,
    P05,
    Q1,
    Mediana,
    Q3,
    P95,
    Maximo,
    Cant_Ceros,
    ROUND(Cant_Ceros * 100.0 / N, 2) AS Pct_Ceros,
    Cant_Negativos,
    ROUND(Cant_Negativos * 100.0 / N, 2) AS Pct_Negativos,
    -- Conteo de outliers (valores fuera de [Q1 - 1.5*IQR, Q3 + 1.5*IQR])
    (SELECT COUNT(*) FROM VENTAS WHERE precio_total < LimitesOutliers.Limite_Inferior OR precio_total > LimitesOutliers.Limite_Superior) AS Cant_Outliers
FROM LimitesOutliers;


-- CONSULTA C3: Estadísticos Categóricos (Método de Pago en VENTAS)
-- Muestra la frecuencia y el porcentaje de participación de cada categoría ordenada de mayor a menor.
WITH PagoFrecuencias AS (
    SELECT 
        metodo_pago,
        COUNT(*) AS Frecuencia,
        COUNT(*) * 100.0 / (SELECT COUNT(*) FROM VENTAS) AS Porcentaje
    FROM VENTAS
    GROUP BY metodo_pago
)
SELECT 
    COALESCE(metodo_pago, 'NULO/DESCONOCIDO') AS Categoria,
    Frecuencia,
    ROUND(Porcentaje, 2) AS Porcentaje_Participacion
FROM PagoFrecuencias
ORDER BY Frecuencia DESC;
