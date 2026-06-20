-- Script de creación del modelo relacional en PostgreSQL
-- Ejercicio 1.2 - TP IBD
-- Diseñado basándose en las especificaciones del diagrama der.drawio y ajustes acordados.
-- NOTA: Se utilizan claves primarias tipo INTEGER de carga manual a requerimiento del TP.

-- 1. CATEGORIAS
CREATE TABLE IF NOT EXISTS CATEGORIAS (
    categoria_id INTEGER PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE CHECK (LENGTH(TRIM(nombre)) > 0),
    descripcion TEXT
);

-- 2. MARCAS
CREATE TABLE IF NOT EXISTS MARCAS (
    marca_id INTEGER PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE CHECK (LENGTH(TRIM(nombre)) > 0),
    origen VARCHAR(100),
    es_importado BOOLEAN NOT NULL DEFAULT FALSE
);

-- 3. PRODUCTOS
CREATE TABLE IF NOT EXISTS PRODUCTOS (
    product_id INTEGER PRIMARY KEY,
    sku VARCHAR(50) NOT NULL UNIQUE CHECK (LENGTH(TRIM(sku)) > 0),
    nombre VARCHAR(150) NOT NULL CHECK (LENGTH(TRIM(nombre)) > 0),
    marca_id INTEGER NOT NULL REFERENCES MARCAS(marca_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    categoria_id INTEGER NOT NULL REFERENCES CATEGORIAS(categoria_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    unidad VARCHAR(50) NOT NULL DEFAULT 'unidad' CHECK (LENGTH(TRIM(unidad)) > 0),
    descripcion_medida VARCHAR(100),
    ultimo_costo NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (ultimo_costo >= 0), --es el ultimo costo registrado en compras, se actualiza con cada compra nueva. Al hacer una venta, este es el costo del producto.
    precio_normal NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (precio_normal >= 0),
    precio_fiel NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (precio_fiel >= 0),
    CONSTRAINT chk_precios_producto CHECK (precio_fiel <= precio_normal)
);

-- 4. PROVEEDORES
CREATE TABLE IF NOT EXISTS PROVEEDORES (
    proveedor_id INTEGER PRIMARY KEY,
    nombre VARCHAR(150) NOT NULL CHECK (LENGTH(TRIM(nombre)) > 0),
    cuit VARCHAR(20) NOT NULL UNIQUE CHECK (LENGTH(TRIM(cuit)) > 0)
);

-- 5. PUNTOS_DE_VENTA
CREATE TABLE IF NOT EXISTS PUNTOS_DE_VENTA (
    puntos_de_venta_id INTEGER PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL UNIQUE CHECK (LENGTH(TRIM(nombre)) > 0),
    telefono VARCHAR(50)
);

-- 6. CLIENTES
CREATE TABLE IF NOT EXISTS CLIENTES (
    cliente_id INTEGER PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL CHECK (LENGTH(TRIM(nombre)) > 0),
    apellido VARCHAR(100) NOT NULL CHECK (LENGTH(TRIM(apellido)) > 0),
    dni VARCHAR(20) NOT NULL UNIQUE CHECK (LENGTH(TRIM(dni)) > 0),
    email VARCHAR(150) UNIQUE CHECK (email IS NULL OR email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    es_cliente_fiel BOOLEAN NOT NULL DEFAULT FALSE
);

-- 7. STOCK (Asociativa M:N entre PRODUCTOS y PUNTOS_DE_VENTA)
CREATE TABLE IF NOT EXISTS STOCK (
    product_id INTEGER NOT NULL REFERENCES PRODUCTOS(product_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    puntos_de_venta_id INTEGER NOT NULL REFERENCES PUNTOS_DE_VENTA(puntos_de_venta_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    cantidad NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (cantidad >= 0),
    stock_minimo NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (stock_minimo >= 0),
    fecha_actualizacion TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (product_id, puntos_de_venta_id)
);

-- 8. COMPRAS
CREATE TABLE IF NOT EXISTS COMPRAS (
    compra_id INTEGER PRIMARY KEY,
    proveedor_id INTEGER REFERENCES PROVEEDORES(proveedor_id) ON UPDATE CASCADE ON DELETE SET NULL,
    puntos_de_venta_id INTEGER NOT NULL REFERENCES PUNTOS_DE_VENTA(puntos_de_venta_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    fecha DATE NOT NULL DEFAULT CURRENT_DATE,
    hora TIME NOT NULL DEFAULT CURRENT_TIME,
    numero_factura VARCHAR(50),
    total NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (total >= 0)
);

-- 9. DETALLE_COMPRAS
CREATE TABLE IF NOT EXISTS DETALLE_COMPRAS (
    detalle_compra_id INTEGER PRIMARY KEY,
    compra_id INTEGER NOT NULL REFERENCES COMPRAS(compra_id) ON UPDATE CASCADE ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES PRODUCTOS(product_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    cantidad NUMERIC(10, 2) NOT NULL CHECK (cantidad > 0),
    costo_unidad NUMERIC(12, 2) NOT NULL CHECK (costo_unidad >= 0),
    subtotal NUMERIC(12, 2) NOT NULL CHECK (subtotal >= 0),
    CONSTRAINT chk_subtotal_compra CHECK (subtotal = cantidad * costo_unidad)
);

-- 10. VENTAS
CREATE TABLE IF NOT EXISTS VENTAS (
    venta_id INTEGER PRIMARY KEY,
    cliente_id INTEGER REFERENCES CLIENTES(cliente_id) ON UPDATE CASCADE ON DELETE SET NULL,
    puntos_de_venta_id INTEGER NOT NULL REFERENCES PUNTOS_DE_VENTA(puntos_de_venta_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    fecha DATE NOT NULL DEFAULT CURRENT_DATE,
    hora TIME NOT NULL DEFAULT CURRENT_TIME,
    precio_total NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (precio_total >= 0),
    costo_total NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (costo_total >= 0),
    metodo_pago VARCHAR(50) NOT NULL CHECK (metodo_pago IN ('EFECTIVO', 'TRANSFERENCIA', 'TARJETA_CREDITO', 'TARJETA_DEBITO', 'MERCADOPAGO', 'OTRO')),
    estado_entrega VARCHAR(50) NOT NULL DEFAULT 'PENDIENTE' CHECK (estado_entrega IN ('PENDIENTE', 'ENTREGADO'))
);

-- 11. DETALLE_VENTAS
CREATE TABLE IF NOT EXISTS DETALLE_VENTAS (
    detalle_venta_id INTEGER PRIMARY KEY,
    venta_id INTEGER NOT NULL REFERENCES VENTAS(venta_id) ON UPDATE CASCADE ON DELETE CASCADE,
    product_id INTEGER NOT NULL REFERENCES PRODUCTOS(product_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    cantidad NUMERIC(10, 2) NOT NULL CHECK (cantidad > 0),
    precio_unidad NUMERIC(12, 2) NOT NULL CHECK (precio_unidad >= 0),
    costo_unidad NUMERIC(12, 2) NOT NULL CHECK (costo_unidad >= 0),
    subtotal NUMERIC(12, 2) NOT NULL CHECK (subtotal >= 0),
    profit NUMERIC(12, 2) NOT NULL,
    CONSTRAINT chk_subtotal_venta CHECK (subtotal = cantidad * precio_unidad),
    CONSTRAINT chk_profit_venta CHECK (profit = subtotal - (cantidad * costo_unidad))
);
