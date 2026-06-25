CREATE INDEX idx_detalle_ventas_producto
ON detalle_ventas (product_id) INCLUDE (cantidad, precio_unidad, costo_unidad);