WITH profit_por_producto AS (
    SELECT
        c.categoria_id,
        c.nombre                         AS categoria,
        p.product_id,
        p.nombre                         AS producto,
        SUM(dv.cantidad)                                       AS unidades_vendidas,
        -- subtotal y profit se calculan al vuelo (ya no son columnas):
        SUM(dv.cantidad * dv.precio_unidad)                    AS ingresos,
        SUM(dv.cantidad * (dv.precio_unidad - dv.costo_unidad)) AS profit_total
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


WITH ventas_con_total AS (
    SELECT
        v.venta_id,
        v.cliente_id,
        v.fecha,
        v.hora,
        SUM(dv.cantidad * dv.precio_unidad) AS precio_total
    FROM VENTAS v
    JOIN DETALLE_VENTAS dv ON dv.venta_id = v.venta_id
    GROUP BY v.venta_id, v.cliente_id, v.fecha, v.hora
)
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
FROM ventas_con_total v
JOIN CLIENTES c ON c.cliente_id = v.cliente_id   -- solo ventas con cliente identificado
ORDER BY c.cliente_id, nro_compra_cliente;
