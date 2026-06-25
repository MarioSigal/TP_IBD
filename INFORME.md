# Trabajo Práctico Grupal — Introducción a Bases de Datos (IBD)

**Universidad de Buenos Aires · 2026**
**Dominio:** comercio minorista de suplementos deportivos

> **Cómo leer este informe.** Cada sección resuelve un punto del enunciado, explica las
> decisiones tomadas y deja indicado dónde insertar la **captura del resultado** correspondiente.
> Los placeholders de captura se marcan así:
>
> 📷 **CAPTURA [N]:** _descripción de qué se debe ver en la imagen._
>
> Reemplazar cada placeholder por la imagen real antes de exportar a PDF
> (sugerencia: guardarlas en una carpeta `capturas/` y enlazarlas con
> `![CAPTURA N](capturas/captura_N.png)`).

---

## Índice

1. [Etapa 1 — Modelo Relacional (PostgreSQL)](#etapa-1--modelo-relacional-postgresql)
2. [Etapa 2 — SQL Avanzado](#etapa-2--sql-avanzado)
3. [Etapa 3 — Procesamiento con Spark](#etapa-3--procesamiento-con-spark)
4. [Etapa 4 — Persistencia Políglota (NoSQL)](#etapa-4--persistencia-políglota-nosql)
5. [Reproducción del entorno](#reproducción-del-entorno)

---

# Etapa 1 — Modelo Relacional (PostgreSQL)

## 1.1 Elección del Modelo

### Dominio elegido y su relevancia

Se modeló el **comercio minorista de suplementos deportivos**: una cadena con varias sucursales
que compra productos a proveedores, mantiene stock por sucursal y los vende a clientes.

Se eligió este dominio porque es **suficientemente rico** para sustentar todas las etapas del TP:

- Tiene **entidades maestras** (categorías, marcas, productos, proveedores, puntos de venta,
  clientes) y **entidades transaccionales** (compras y ventas con sus detalles), lo que permite
  generar un volumen alto de registros y consultas analíticas significativas.
- Genera **métricas de negocio reales** (facturación, profit, ticket promedio, rotación de
  stock, recencia/frecuencia de clientes) ideales para las funciones de ventana y estadísticas
  de la Etapa 2 y los MapReduce de la Etapa 3.
- Admite **nuevos requerimientos** naturales (ventas online con cola de despacho, combos de
  productos, estado actual de stock consultado en tiempo real) que motivan la persistencia
  políglota de la Etapa 4.

### Entidades del modelo (DER)

📷 **CAPTURA 1:** _Diagrama Entidad-Relación (`der.png`) con las 11 tablas y sus relaciones._

| # | Tabla | Tipo | Rol en el dominio |
|---|-------|------|-------------------|
| 1 | `CATEGORIAS` | Maestra | Clasificación de productos (Proteínas, Creatinas, …) |
| 2 | `MARCAS` | Maestra | Marca del producto, con origen e indicador de importado |
| 3 | `PRODUCTOS` | Maestra | Catálogo; referencia a marca y categoría; costo y precio único |
| 4 | `PROVEEDORES` | Maestra | A quién se le compra |
| 5 | `PUNTOS_DE_VENTA` | Maestra | Sucursales |
| 6 | `CLIENTES` | Maestra | Clientes (nombre, apellido, DNI, email) |
| 7 | `STOCK` | Asociativa M:N | Existencias de cada producto en cada sucursal |
| 8 | `COMPRAS` | Transaccional | Cabecera de compra a proveedor |
| 9 | `DETALLE_COMPRAS` | Transaccional | Líneas de cada compra |
| 10 | `VENTAS` | Transaccional | Cabecera de venta a cliente |
| 11 | `DETALLE_VENTAS` | Transaccional | Líneas de cada venta (cantidad, precio y costo unitario) |

### Decisiones de diseño

**Qué se incluyó y por qué:**

- **`STOCK` como tabla asociativa M:N** entre `PRODUCTOS` y `PUNTOS_DE_VENTA`, con clave primaria
  compuesta `(product_id, puntos_de_venta_id)`. Un producto está en muchas sucursales y una
  sucursal tiene muchos productos: la asociativa modela esa relacion sin redundancia y permite
  llevar atributos propios del vínculo (`cantidad`, `stock_minimo`, `fecha_actualizacion`).
- **Patrón cabecera/detalle** en compras y ventas (`COMPRAS`/`DETALLE_COMPRAS`,
  `VENTAS`/`DETALLE_VENTAS`). La cabecera guarda los datos comunes de la transacción (fecha,
  punto de venta, método de pago) y el detalle, una fila por producto. Es el modelo estándar de
  facturación y evita repetir los datos de cabecera en cada línea.
- **Precio único de venta** (`PRODUCTOS.precio`). Se eliminó la lógica de cliente fiel/normal: ya
  no existen `precio_normal`/`precio_fiel` ni `es_cliente_fiel`. El precio aplicado a cada línea
  se guarda como *snapshot* en `DETALLE_VENTAS.precio_unidad` (puede diferir del catálogo a
  futuro, por eso no es derivable del producto).
- **`ultimo_costo` en `PRODUCTOS`:** representa el último costo de reposición conocido; es el
  costo que se imputa al vender (se copia a `DETALLE_VENTAS.costo_unidad` como snapshot).

**Qué se agregó respecto de un modelo mínimo:**

- Atributos de calidad de datos y trazabilidad: `sku` único, `cuit` de proveedores, `dni`/`email`
  de clientes, `numero_factura`, `fecha_actualizacion` de stock.
- `MARCAS.origen` y `MARCAS.es_importado` para habilitar análisis nacional vs. importado.

**Qué se dejó fuera (y por qué):**

- **Atributos derivables (decisión de normalización):** no se almacena nada que pueda calcularse
  a partir de otras columnas. Se eliminaron `subtotal` y `profit` de `DETALLE_VENTAS`
  (`cantidad·precio_unidad` y `cantidad·(precio_unidad−costo_unidad)`), `precio_total` y
  `costo_total` de `VENTAS` (SUM del detalle), `total` de `COMPRAS` y `subtotal` de
  `DETALLE_COMPRAS`. Evita redundancia y elimina el riesgo de que la cabecera quede desfasada del
  detalle. El costo es recalcular en cada consulta analítica (se asume aceptable para el volumen
  del TP).
- **Lógica de fidelización y `estado_entrega`:** se quitaron `es_cliente_fiel`, `precio_normal`,
  `precio_fiel` y `estado_entrega` por simplificación del alcance.
- **Índices:** el enunciado de la Etapa 1 indica expresamente *no* crear índices manuales (se
  retoman en la Etapa 2.3). Ver la aclaración en la sección 1.2.
- **Movimientos de stock como log histórico:** se modela el **saldo actual** de stock, no cada
  movimiento individual; los movimientos quedan implícitos en compras y ventas. Se evitó así una
  tabla de "kardex" que excede el alcance del TP.
- **Direcciones/geolocalización de clientes y sucursales:** no aportan a las consultas pedidas.

### Descripción de cada constraint de negocio

Todos los constraints viven en `creacion_tablas.sql`. Se agrupan por tabla:

**Claves y unicidad**

- PK de carga manual `INTEGER` en todas las tablas (requisito del TP — ver 1.2).
- `UNIQUE` en identificadores naturales: `CATEGORIAS.nombre`, `MARCAS.nombre`, `PRODUCTOS.sku`,
  `PROVEEDORES.cuit`, `PUNTOS_DE_VENTA.nombre`, `CLIENTES.dni`, `CLIENTES.email`.

**Restricciones de dominio (`CHECK`) — precios y montos no negativos**

- `PRODUCTOS`: `ultimo_costo >= 0`, `precio >= 0`.
- `STOCK`: `cantidad >= 0` (no hay stock negativo) y `stock_minimo >= 0`.
- `DETALLE_COMPRAS`: `cantidad > 0`, `costo_unidad >= 0`.
- `DETALLE_VENTAS`: `cantidad > 0`, `precio_unidad >= 0`, `costo_unidad >= 0`.

> Al eliminar los atributos derivables ya no existen los CHECK de coherencia aritmética
> (`subtotal`/`profit`) ni la regla `precio_fiel <= precio_normal`: esos valores se calculan en
> las consultas, no se almacenan, por lo que no pueden quedar inconsistentes por construcción.

**Restricciones de listas de valores (enumerados)**

- `VENTAS.metodo_pago IN ('EFECTIVO','TRANSFERENCIA','TARJETA_CREDITO','TARJETA_DEBITO','MERCADOPAGO','OTRO')`.

**Restricciones de formato y obligatoriedad**

- `CLIENTES.email`: o bien `NULL`, o bien cumple el patrón `^[^@\s]+@[^@\s]+\.[^@\s]+$`
  (validación de email por expresión regular).
- `LENGTH(TRIM(...)) > 0` en nombres/SKU/CUIT/DNI/unidad: evita strings vacíos o solo espacios.
- `NOT NULL` en todas las columnas obligatorias.

**Integridad referencial (FK) y políticas de borrado/actualización**

- `ON UPDATE CASCADE` en todas las FK (si cambia una PK, se propaga).
- `ON DELETE RESTRICT` donde borrar el padre dejaría datos sin sentido (p. ej. un producto con
  ventas, una sucursal con stock).
- `ON DELETE SET NULL` en `VENTAS.cliente_id` y `COMPRAS.proveedor_id`: si se da de baja un
  cliente/proveedor, la transacción histórica se conserva pero queda "anónima".
- `ON DELETE CASCADE` en los detalles (`DETALLE_VENTAS`, `DETALLE_COMPRAS`): borrar una cabecera
  borra sus líneas (no tienen vida propia).

## 1.2 Implementación en PostgreSQL

Script: **`creacion_tablas.sql`**. Crea las 11 tablas con tipos apropiados, PK, FK y constraints.

**Tipos de datos elegidos:**

- `INTEGER` para PK e identificadores.
- `VARCHAR(n)` para textos acotados (nombres, SKU, CUIT, método de pago) y `TEXT` para
  descripciones libres.
- `NUMERIC(12,2)` para dinero y `NUMERIC(10,2)`/`NUMERIC(12,2)` para cantidades: se usa decimal
  exacto (no `FLOAT`) para evitar errores de redondeo en montos.
- `DATE` + `TIME` para fecha y hora de las transacciones; `TIMESTAMP` para
  `STOCK.fecha_actualizacion`.
- `BOOLEAN` para flags (`MARCAS.es_importado`).

**Claves primarias de carga manual.** Por requisito explícito del TP, las PK son `INTEGER`
cargadas manualmente (no `SERIAL`/`IDENTITY`). Esto da control total sobre los identificadores al
generar datos coherentes entre tablas.

**Aclaración sobre índices.** El enunciado pide *no* crear índices en la Etapa 1. Aun así,
PostgreSQL crea **automáticamente** un índice B-tree único para respaldar cada `PRIMARY KEY` y
cada `UNIQUE` (convención de nombre `<tabla>_pkey`). Estos índices son **implícitos e
inevitables** (forman parte de la definición del modelo, no son una optimización agregada). El
único índice manual del TP aparece en la Etapa 2.3 como propuesta de optimización.

📷 **CAPTURA 2:** _Ejecución de `creacion_tablas.sql` con `psql` mostrando los `CREATE TABLE`
exitosos (`\dt` listando las 11 tablas)._

```bash
psql -h localhost -p 5433 -U <usuario> -d <base> -f creacion_tablas.sql
```

## 1.3 Poblado de Datos

### Generación

Script generador: **`generar_datos.py`** → produce **`poblado_datos.sql`**.

Características clave:

- **Semilla fija (`random.seed(42)`)** → reproducible: dos corridas generan el mismo dataset.
- **Datos en memoria antes de escribir:** mantiene listas de productos, clientes, compras y
  ventas en memoria, lo que permite calcular saldos de stock coherentes (stock inicial + compras
  − ventas) y reutilizar la misma fuente para exportar CSVs (Etapa 3).
- **Strings sin acentos** en emails para respetar el `CHECK` de formato.
- `ON CONFLICT DO NOTHING` en cada `INSERT` → el script es **idempotente** (re-ejecutable).

**Volumen generado (cumple el criterio de ≥ 5000 registros en tablas principales):**

| Tabla | Registros |
|-------|-----------|
| `CATEGORIAS` | 6 |
| `MARCAS` | 10 |
| `PROVEEDORES` | 6 |
| `PUNTOS_DE_VENTA` | 4 |
| `PRODUCTOS` | 95 |
| `CLIENTES` | 1 500 |
| `STOCK` | 380 (95 productos × 4 sucursales) |
| `COMPRAS` | 120 |
| `DETALLE_COMPRAS` | 715 |
| **`VENTAS`** | **5 200** ✅ |
| **`DETALLE_VENTAS`** | **13 132** ✅ |

**Variedad y coherencia:** fechas repartidas en 6 meses (ene–jun 2026), 6 métodos de pago,
ventas con y sin cliente identificado, productos de marcas nacionales e importadas con precios
diferenciados.

📷 **CAPTURA 3:** _Salida de `python3 generar_datos.py` con el resumen de totales por tabla._

📷 **CAPTURA 4:** _Ejecución de `poblado_datos.sql` y un `SELECT COUNT(*)` por tabla principal
confirmando los volúmenes._

### Validación de consistencia (`validar_datos.sql`)

Se desarrollaron consultas con funciones de agrupación que **deben devolver 0 filas** si los
datos son consistentes:

- **Validación A — Integridad del detalle vs. venta:** no hay líneas de `DETALLE_VENTAS` cuyo
  `venta_id` no exista en `VENTAS`.
- **Validación B — Integridad del detalle vs. producto:** no hay `product_id` en `DETALLE_VENTAS`
  que no exista en `PRODUCTOS`.
- **Validación C — Cabecera sin líneas:** no hay ventas sin al menos un detalle.
- **Validación D — Coherencia de margen:** no hay líneas con `precio_unidad < costo_unidad`
  (no se vende por debajo del costo, dado el markup del catálogo).

> Como los totales ya no se almacenan, las validaciones dejan de ser "cuadres cabecera vs.
> detalle" (imposibles de descuadrar: el total se calcula del detalle) y pasan a verificar
> integridad referencial y coherencia.

📷 **CAPTURA 5:** _Las 4 validaciones devolviendo 0 filas (datos 100% consistentes)._

### Estadísticos de la tabla (numéricos y categóricos)

El mismo script genera reportes estadísticos al estilo de la práctica, reconstruyendo los montos
por venta desde el detalle con una CTE:

- **C1 — Frecuencias generales:** total de filas, no nulos, % no nulos y valores distintos de
  `cliente_id`, `precio_total` (calculado) y `metodo_pago`.
- **C2 — Estadísticos numéricos de `precio_total` (calculado):** desvío estándar, mínimo, P05, Q1,
  mediana, promedio, Q3, P95, máximo, ceros, negativos y outliers (regla de Tukey con IQR).
- **C3 — Estadísticos categóricos de `metodo_pago`:** frecuencia y porcentaje por categoría,
  ordenado de mayor a menor.

> Nota: la versión completa y generalizada de estos estadísticos (para todas las columnas) se
> desarrolla en la Etapa 2.2.

📷 **CAPTURA 6:** _Salidas de C1, C2 y C3 de `validar_datos.sql`._

---

# Etapa 2 — SQL Avanzado

## 2.1 Funciones de Ventana

Script: **`queries_con_funciones_ventana.sql`**. Dos consultas que **no** se resuelven
trivialmente con `GROUP BY`.

### Consulta 1 — Top 3 productos más rentables *dentro de cada categoría*

**Pregunta de negocio.** "Dentro de cada categoría, ¿cuáles son los 3 productos que más profit
generaron?" Sirve para decidir surtido, negociación con proveedores y dónde concentrar
promociones.

**Por qué función de ventana y no `GROUP BY`.** El ranking (`posicion_en_categoria`) es una
métrica **a nivel grupo** (categoría) que ordena los productos entre sí, pero debe mostrarse en
**cada fila** de producto. Un `GROUP BY` por categoría devuelve una sola fila por categoría y
colapsa el detalle: no puede asignar una posición a cada producto. Además, no existe función de
agregación clásica que produzca un ranking — `RANK`/`DENSE_RANK` **solo** existen como funciones
de ventana. `PARTITION BY` agrupa **sin colapsar**:

```sql
DENSE_RANK() OVER (PARTITION BY categoria_id ORDER BY profit_total DESC) AS posicion_en_categoria
```

Se usa `DENSE_RANK` (no `ROW_NUMBER`) para que los empates compartan posición: si hay empate en
el top, pueden aparecer más de 3 productos por categoría. Como `subtotal`/`profit` ya no se
almacenan, los agregados se calculan al vuelo en la CTE: `ingresos = SUM(cantidad·precio_unidad)`
y `profit_total = SUM(cantidad·(precio_unidad−costo_unidad))`.

**Resultado esperado.** Una fila por producto del top 3 de cada categoría, ordenada por categoría
y posición, con unidades vendidas, ingresos y profit total.

📷 **CAPTURA 7:** _Resultado de la Consulta 1 (top 3 por categoría)._

### Consulta 2 — Comportamiento de compra de cada cliente en el tiempo

**Pregunta de negocio.** Para cada venta de un cliente identificado: ¿qué número de compra es,
cuánto lleva gastado acumulado y cuántos días pasaron desde su compra anterior? Sirve para
analizar recencia/frecuencia, detectar clientes que dejan de comprar y medir el valor acumulado
(CLV simplificado).

**Por qué función de ventana y no `GROUP BY`.** Las tres métricas dependen del **orden** y la
**posición** de cada compra dentro del historial del cliente:

- `ROW_NUMBER() OVER (PARTITION BY cliente ORDER BY fecha)` → número ordinal de compra.
- `SUM(precio_total) OVER (... ORDER BY ... ROWS UNBOUNDED PRECEDING)` → **gasto acumulado**
  (running total), imposible con `GROUP BY`.
- `LAG(fecha) OVER (...)` → fecha de la compra anterior, para medir el intervalo entre compras.

`GROUP BY` no tiene concepto de "fila anterior" ni de orden: colapsaría todas las compras del
cliente en una sola fila y se perdería toda la secuencia temporal. Como `precio_total` ya no es
columna de `VENTAS`, una **CTE previa** lo reconstruye por venta (`SUM(cantidad·precio_unidad)`) y
las funciones de ventana operan sobre esa CTE.

**Resultado esperado.** Una fila por venta de cada cliente, en orden cronológico:
`nro_compra_cliente` crece desde 1, `gasto_acumulado` suma el histórico y
`dias_desde_compra_anterior` es `NULL` en la primera compra y luego mide el espaciamiento.

📷 **CAPTURA 8:** _Resultado de la Consulta 2 para uno o dos clientes con varias compras._

## 2.2 Funciones estadísticas

Script: **`queries_estadisticas.sql`**. Tabla analizada: **`VENTAS`**. Como `VENTAS` ya no
almacena columnas numéricas, las tres consultas parten de una **CTE (`WITH`) `ventas_ext`** que
reconstruye `precio_total`/`costo_total` por venta desde el detalle. Esto cumple además el
requisito de usar Common Table Expressions.

### C1 — Perfil general de cada columna

Para cada una de las 8 columnas de `ventas_ext`: total de filas, filas no nulas, **% no nulas** y
cantidad de valores distintos. Técnica: como cada columna tiene un tipo distinto, se calcula el
perfil por columna y se apilan con `UNION ALL` en **formato largo** (una fila por columna).
`COUNT(col)` ignora `NULL` mientras que `COUNT(*)` cuenta todo: la diferencia revela los nulos
(útil en `cliente_id`, la única columna nullable).

📷 **CAPTURA 9:** _Resultado de C1 (perfil de las columnas; `cliente_id` con % no nulos < 100)._

### C2 — Estadísticos de las columnas numéricas

Para `precio_total` y `costo_total` (calculadas por venta): desvío estándar, mínimo, **P05, Q1,
mediana, promedio, Q3, P95**, máximo, cantidad y % de ceros, cantidad y % de negativos, y
**cantidad de outliers**. Técnicas destacadas:

- Las dos columnas numéricas (reconstruidas) se "despivotan" a formato largo con `UNION ALL` para
  calcular ambas en una sola pasada.
- Percentiles con `PERCENTILE_CONT(p) WITHIN GROUP (ORDER BY valor)` (interpolados).
- Outliers por la **regla de Tukey**: fuera de `[Q1 − 1.5·IQR ; Q3 + 1.5·IQR]`, contados con
  `COUNT(*) FILTER (...)`.

📷 **CAPTURA 10:** _Resultado de C2 (estadísticos de `precio_total` y `costo_total`)._

### C3 — Distribución de frecuencias de las columnas categóricas

Para `metodo_pago` y `puntos_de_venta_id` (la sucursal, ya que `estado_entrega` fue eliminado):
hasta los 10 valores más frecuentes con su frecuencia y porcentaje, agrupando el resto en una fila
`(resto)`. Técnica: CTE de conteo → `ROW_NUMBER() OVER (ORDER BY frecuencia DESC)` para rankear +
`SUM(frecuencia) OVER ()` para el total → `CASE` que separa top 10 de `(resto)`.

📷 **CAPTURA 11:** _Resultado de C3 para `metodo_pago` y `puntos_de_venta_id`._

## 2.3 Análisis de Performance

Documento completo: **`Ejercicio_2.3_Analisis_Performance.docx`**. Índice propuesto:
**`create_index_23.sql`**.

### Consulta analizada

Se eligió la **Consulta 1 de la Etapa 2.1** (ranking de productos más rentables por categoría)
por ser la más compleja: combina join de 3 tablas, `GROUP BY`, función de ventana y dos
ordenamientos. En el nuevo modelo `profit_total` se calcula como
`SUM(cantidad·(precio_unidad−costo_unidad))` (las columnas `subtotal`/`profit` ya no existen).

### Plan de ejecución (`EXPLAIN ANALYZE`)

📷 **CAPTURA 12:** _Salida de `EXPLAIN ANALYZE` de la consulta original (plan completo)._

> Los valores de costo de la tabla son **ilustrativos** (corrida previa); conviene regenerarlos
> con la captura sobre los datos actuales. La estructura del plan y el razonamiento se mantienen.

Estructura del plan (de abajo hacia arriba) y costo que aporta cada operación:

| Operación | Costo total acumulado | Costo que agrega |
|-----------|----------------------:|-----------------:|
| `Seq Scan` sobre `detalle_ventas` | 262 | — |
| `Sort` por `product_id` (entrada del Merge Join) | 1 143 | +880 |
| `Merge Join` + `Nested Loop` con productos/categorías | 1 359 | +216 |
| `Incremental Sort` + `GroupAggregate` (el `GROUP BY`) | 2 366 | +1 007 |
| `Sort` por `(categoria_id, profit_total DESC)` | 5 585 | +3 122 |
| `WindowAgg` (calcula `DENSE_RANK`) | 5 843 | +258 |
| `Sort` final por `(categoria, posicion_en_categoria)` | **9 094** | +3 122 |

**Lectura del plan.** Los **tres nodos `Sort`** concentran casi todo el costo. El `Seq Scan`
sobre `detalle_ventas` (262) es barato y óptimo: como la consulta agrega toda la tabla **sin
`WHERE`**, leerla entera de forma secuencial es lo esperable. El plan incluso muestra
`Run Condition: (dense_rank() OVER w1 <= 3)`: PostgreSQL empuja el filtro `top 3` dentro del
`WindowAgg`, cortando cada partición temprano (optimización automática).

**Por qué aparecen `Index Scan` sin haber creado índices.** Son `productos_pkey` y
`categorias_pkey`, los índices **implícitos** que respaldan las PK. El join se hace por PK
(`c.categoria_id = p.categoria_id`) sobre tablas chicas, y buscar "la fila cuya PK = X" por índice
es óptimo, por eso el planner los elige (con `Memoize` cacheando categorías ya buscadas).

### Solución propuesta y análisis comparativo

De los tres `Sort`, dos **no son indexables** porque ordenan **valores derivados**:
`profit_total` (un `SUM` del `GROUP BY`) y `posicion_en_categoria` (resultado del `DENSE_RANK`).
Ningún índice puede entregar pre-ordenado algo que no existe como columna base. El **único
atacable** es el `Sort` por `product_id` (+880), que ordena una columna real solo para alimentar
el `Merge Join`. Índice propuesto:

```sql
CREATE INDEX idx_detalle_ventas_producto
ON detalle_ventas (product_id) INCLUDE (cantidad, precio_unidad, costo_unidad);
```

- **Elimina el `Sort` por `product_id`:** el índice entrega las filas ya ordenadas por
  `product_id`, justo lo que el `Merge Join` necesita.
- **Habilita un `Index Only Scan`:** el `INCLUDE (cantidad, precio_unidad, costo_unidad)` agrega al índice
  las columnas base con las que la consulta calcula los `SUM`, así PostgreSQL resuelve la lectura
  sin tocar el heap (menos páginas leídas, visible con `EXPLAIN (ANALYZE, BUFFERS)`).

**Impacto esperado:** costo total estimado baja de **~9 094 a ~8 200 (≈10%)**.

📷 **CAPTURA 13:** _`EXPLAIN (ANALYZE, BUFFERS)` luego de crear el índice, mostrando el
`Index Only Scan` ya ordenado en lugar del `Seq Scan` + `Sort`._

**Conclusión.** La mejora del índice es **acotada (~10%)**, y ese es un hallazgo en sí mismo:
como la consulta agrega la tabla completa sin filtro selectivo, no hay un subconjunto pequeño que
un índice permita localizar; el grueso del costo son los dos `Sort` sobre valores derivados,
inherentes a las funciones de ventana. La palanca de mayor impacto sería **reescribir la
consulta** para que los `Sort` muevan filas más angostas: hoy la CTE arrastra los textos de
categoría y producto (`width=370`) por todas las operaciones; si el ranking se calculara solo con
identificadores y números, y los nombres se incorporaran al final con un join, los `Sort` serían
mucho más baratos.

---

# Etapa 3 — Procesamiento con Spark

## 3.1 MapReduce con Spark (RDDs)

Notebook: **`mapreduce_spark.ipynb`**. Tres procesamientos MapReduce con la **API de RDDs** de
PySpark sobre los CSV exportados de la Etapa 1 (`data/ventas.csv`, `data/detalle_ventas.csv`).

> **Requisito de entorno:** Spark corre sobre la JVM → requiere **Java JDK 17**. Los CSV se
> exportan desde las tablas de la Etapa 1 (con encabezado) a la carpeta `data/`.

📷 **CAPTURA 14:** _Celda de configuración: `SparkContext activo: <versión>`._

**Lazy evaluation (transformaciones vs. acciones).** `map`, `filter` y `reduceByKey` son
**transformaciones perezosas (lazy)**: construyen el DAG pero **no computan nada**. El cómputo se
dispara recién al invocar una **acción** (`collect`, `take`, `takeOrdered`), momento en el que
Spark aplica combinadores locales por partición **antes del shuffle**. Los RDD base se cachean
(`.cache()`) porque se reutilizan en varias consultas.

> **Nota del nuevo modelo:** `ventas.csv` ya no trae `precio_total` y `detalle_ventas.csv` ya no
> trae `subtotal`/`profit`. Por eso se reconstruye primero el **monto por venta** desde el detalle
> (`SUM(cantidad·precio_unidad)` con `reduceByKey` por `venta_id`) y se cachea para reutilizarlo.

### Consulta 1 — Facturación, cantidad de ventas y ticket promedio por sucursal

- **Pregunta:** ¿cuánto facturó cada punto de venta y cuál es su ticket promedio?
- **Map:** como `precio_total` ya no existe, se **une** (`join` por `venta_id`) el monto por venta
  con `(venta_id → puntos_de_venta_id)` y se emite `(puntos_de_venta_id, (monto, 1))`.
- **Reduce:** `reduceByKey` sumando las tuplas componente a componente →
  `(suma_facturacion, cantidad_ventas)`. La operación es asociativa y conmutativa, lo que habilita
  el *map-side combine*. Un `mapValues` final deriva el ticket promedio.
- **Acción:** `collect()`.

📷 **CAPTURA 15:** _Tabla por sucursal: facturación total, cantidad de ventas y ticket promedio._

### Consulta 2 — Top 10 productos por profit

- **Pregunta:** ¿cuáles son los 10 productos que más ganancia generaron?
- **Map:** por cada línea de `detalle_ventas` → `(product_id, cantidad·(precio_unidad−costo_unidad))`
  (el profit se calcula al vuelo, ya no es columna).
- **Reduce:** `reduceByKey` sumando el profit → profit total por producto.
- **Acción:** `takeOrdered(10, key=-profit)`, que ordena de forma **distribuida** (parcial por
  partición + combinación) sin traer todo el RDD al driver.

📷 **CAPTURA 16:** _Top 10 `product_id` por profit total acumulado._

### Consulta 3 — Distribución de ventas e ingresos por método de pago

- **Pregunta:** ¿cómo se reparten las ventas (cantidad y monto) entre los métodos de pago?
- **Map:** se **une** el monto por venta con `(venta_id → metodo_pago)` y se emite
  `(metodo_pago, (1, monto))`.
- **Reduce:** `reduceByKey` sumando ambos componentes → `(cantidad_ventas, monto_total)` por
  método. Como hay solo 6 categorías, el shuffle es mínimo.
- **Acción:** `collect()`, y un paso final calcula el porcentaje sobre el total.

📷 **CAPTURA 17:** _Distribución por método de pago (cantidad, % y monto)._

> Cierre: se liberan los RDD cacheados (`unpersist`) y se detiene el `SparkContext`.

---

# Etapa 4 — Persistencia Políglota (NoSQL)

La idea central: usar **la tecnología adecuada para cada patrón de acceso**. PostgreSQL sigue
siendo la **fuente de verdad** transaccional; Redis y MongoDB cubren necesidades que el modelo
relacional resuelve de forma incómoda.

## 4.1 Redis

Notebook: **`redis_nosql.ipynb`**. Entorno: Redis 7.2 local (Docker), `localhost:6379`,
`decode_responses=True`. La notebook es **idempotente**: al inicio borra **solo sus claves** por
prefijo con `SCAN` (no usa `FLUSHDB`).

📷 **CAPTURA 18:** _Celda de conexión: `PING: True` y versión de Redis._

### 4.1.1 Modelo Clave-Valor y Hashes

Se modelan **tres** tipos de datos del dominio, todos consultados frecuentemente por su ID y que
representan el **estado actual** del negocio:

1. **Stock bidireccional (hashes espejo).** Dos hashes:
   - `stock:producto:<id>` con campos `sucursal_id → cantidad`.
   - `stock:sucursal:<id>` con campos `product_id → cantidad`.

   Duplicar el dato es **a propósito**: en Redis se modela según el patrón de acceso. Permite
   responder en **O(1)** "¿cuánto stock del producto P hay en la sucursal S?" con `HGET`, y
   también la dirección inversa. El precio a pagar (escribir en ambos hashes) son operaciones
   O(1) baratas. La **venta** descuenta stock con `HINCRBY` **atómico** sobre ambos hashes dentro
   de una transacción (`MULTI` vía pipeline) para que no se desfasen; luego se **verifica**
   releyendo las dos vistas.
2. **Perfil de producto (hash).** `producto:<id>` con `nombre`, `precio`, `marca`. Se lee un
   campo (`HGET`) o el documento completo (`HGETALL`). **Actualización:** cambio de precio con
   `HSET` y verificación releyendo.
3. **Contador de ventas del día (string).** `ventas:hoy:sucursal:<id>` con `INCR` atómico y
   `caja:sucursal:<id>` con `INCRBYFLOAT`.

📷 **CAPTURA 19:** _Carga y consultas de stock (`HGET` O(1), `HGETALL` en ambas direcciones)._

📷 **CAPTURA 20:** _Venta con `HINCRBY` atómico y verificación de consistencia entre las dos
vistas (`OK`)._

📷 **CAPTURA 21:** _Perfil de producto (`HGET`/`HGETALL`) y actualización de precio verificada._

📷 **CAPTURA 22:** _Contador de ventas (`INCR`) y caja (`INCRBYFLOAT`) tras 5 ventas._

**¿Por qué Redis y no PostgreSQL para estos datos?**

- **Latencia sub-milisegundo por acceso directo a la clave** (RAM + O(1)): el stock y el perfil
  se consultan constantemente y siempre por ID.
- **Operaciones atómicas sin locks de fila:** `INCR`/`HINCRBY` son atómicos por diseño; en
  PostgreSQL un contador muy golpeado genera contención de bloqueos sobre la misma fila.
- **Modelado según el patrón de acceso:** los hashes espejo dan O(1) en **ambas** direcciones,
  lo que en SQL requeriría índices y `JOIN`s.

**Límite (importante):** Redis **no** reemplaza a PostgreSQL como fuente de verdad durable ni para
consultas analíticas o filtros arbitrarios (no hay `WHERE` ni `JOIN`). El esquema correcto es
**políglota**: PostgreSQL es la verdad transaccional y Redis la capa rápida de estado actual, que
se reconstruye desde la base si se pierde.

### 4.1.2 Lista como cola de pedidos (nuevo requerimiento: ventas online con envío)

El negocio incorpora **venta online con envío**: el pedido no se entrega en el acto, queda
**pendiente de despacho**. Se modela una **cola FIFO** con una lista de Redis (`pedidos:pendientes`):

- **Al concretarse una venta** → `RPUSH` (entra por el final).
- **Al despachar** → `LPOP` (sale el más antiguo, del frente).

`RPUSH` + `LPOP` implementan FIFO. Cada pedido se serializa como JSON. Operaciones mostradas:

- **Consulta:** `LRANGE` (ver la cola sin modificarla), `LLEN` (tamaño), `LINDEX 0` (peek del
  próximo a despachar).
- **Gestión:** `LPOP` (despachar), `RPUSH` (encolar nuevo), `RPOP` (cancelar el último ingresado).
- **Simulación del flujo completo:** se intercalan ventas y despachos mostrando cómo crece y se
  vacía la cola en cada paso.

📷 **CAPTURA 23:** _Carga inicial de la cola y `LRANGE`/`LLEN`/`LINDEX`._

📷 **CAPTURA 24:** _Simulación del flujo (eventos venta/despacho con el contador de pendientes)._

### 4.1.3 TTL — Datos con tiempo de vida

Tres claves con TTL distinto y justificado:

| Dato | Clave | TTL | Por qué ese tiempo |
|------|-------|-----|--------------------|
| Carrito de compras | `carrito:cliente:<id>` | 30 min | Conserva la selección mientras el cliente compra; libera carritos abandonados. Se **renueva** con `EXPIRE` en cada acción. |
| Reserva temporal de stock | `reserva:stock:<prod>:<suc>` | 10 min | Reserva unidades mientras el cliente paga; si no concreta, el stock se libera (evita sobreventa sin congelar inventario). |
| Token de sesión | `sesion:token:<token>` | 1 hora | Mantiene logueado al cliente; vence por seguridad ante inactividad. |

Se verifica el tiempo restante con `TTL`/`PTTL` (convención: `-1` = sin expiración, `-2` = ya no
existe) y se demuestra la **expiración real** creando una reserva con TTL corto (2 s) y
comprobando que Redis la borra sola.

📷 **CAPTURA 25:** _Creación de las 3 claves con sus TTL y verificación con `TTL`/`PTTL`._

📷 **CAPTURA 26:** _Renovación del carrito con `EXPIRE` y expiración automática de la reserva
(mensajes "la reserva expiró" / "el token sigue vigente por N segundos")._

## 4.2 MongoDB

Notebook: **`mongodb_documental.ipynb`**.

### Configuración del entorno

Se eligió **MongoDB local con Docker** (imagen oficial, v8.2), por ser 100% reproducible. Pasos:

```bash
docker run -d -p 27017:27017 --name mongo_ibd \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=<password> \
  mongo
pip install pymongo
```

**String de conexión (credenciales anonimizadas):** `mongodb://<usuario>:<password>@localhost:27017/`.
**Alternativa Atlas (nube):** basta cambiar la variable `CONN` por
`mongodb+srv://<usuario>:<password>@<cluster>.mongodb.net/`; el resto del código PyMongo es
idéntico. **Problema típico encontrado:** si el contenedor no está levantado, `ping` lanza
`ServerSelectionTimeoutError`; se resuelve verificando `docker ps` y reiniciando con
`docker start mongo_ibd`. La notebook es **idempotente** (dropea sus colecciones antes de cargar).

📷 **CAPTURA 27:** _Conexión OK con la versión de MongoDB._

### 4.2.1 Diseño de colecciones (nuevo requerimiento: combos)

El negocio quiere vender productos en **combos**. Cada línea de venta referencia **o bien un
producto, o bien un combo**. En el modelo relacional esto obligaría a que `DETALLE_VENTAS`
tuviera a la vez `product_id` **y** `combo_id`, dejando **uno en NULL por fila** más un `CHECK`
que garantice que exactamente uno esté presente. El modelo **documental** evita ese desperdicio:
cada línea lleva **solo los campos que le corresponden**.

Se modelan dos colecciones:

- **`ventas`** — un documento por venta, con las líneas **embebidas** en un array `items[]`
  **polimórfico** (cada ítem es `tipo: "producto"` o `tipo: "combo"`). La venta es un *agregado
  natural*: casi siempre se lee entera y sus líneas no tienen vida propia. Además la cantidad de
  ítems es **acotada** (1–4), ideal para embeber. El `cliente_id` se **referencia** (el cliente
  vive en su propia entidad).
- **`combos`** — catálogo de combos con su composición en un array embebido `componentes[]`. El
  combo **vive por su cuenta** (existe aunque no se haya vendido), por eso es una colección aparte
  y se trae con `$lookup`.

**Decisiones de diseño discutidas:**

- **Embeber vs. referenciar:** se embeben las líneas y los componentes (se leen siempre junto al
  padre); se referencia el cliente y, desde la venta, el `combo_id` (catálogo con vida propia).
- **Campos opcionales / variables:** `cliente_id` (ventas anónimas), `descripcion` de combo
  (opcional), y los campos del ítem varían según el `tipo` (un ítem-combo no tiene
  `precio_unidad`; un ítem-producto no tiene `componentes`). **No hay NULLs**: el campo que no
  aplica simplemente no existe.
- **Diferencia con el relacional:** no hay tabla puente ni FKs nullable ni `CHECK` de
  exclusividad; la venta completa se lee sin joins (en SQL serían 2–3 `JOIN`).

Como parte del **diseño** (4.2.1) se **generan los documentos en memoria**: **100 combos** y
**130 ventas** (≥ 100 documentos por colección, como pide la consigna), con variedad
(solo-producto, producto+combo, con y sin cliente, distintos métodos de pago, fechas en 6 meses;
combos con y sin `descripcion`). La **inserción** en MongoDB no se hace acá, sino en la sección de
CRUD (4.2.2), que es donde la consigna ubica `insert_one`/`insert_many`.

📷 **CAPTURA 28:** _Salida de la generación: 100 combos y 130 ventas construidos en memoria._

### 4.2.2 Operaciones CRUD

Cada operación atada a un caso de uso:

- **Inserción (`insert_one` / `insert_many`):** se insertan los documentos generados en 4.2.1.
  En cada colección se usa `insert_one` (un documento) y `insert_many` (el resto en lote), con
  `drop()` previo para que la notebook sea idempotente. *(Es la primera operación del bloque CRUD,
  como pide la consigna.)*
- **Read con filtros de comparación y lógicos:** ventas entre \$40.000 y \$120.000
  (`$gte`/`$lte`) pagadas con tarjeta o MercadoPago (`$or` dentro de `$and`).
- **Read con proyección:** listado liviano con solo `fecha`, `precio_total`, `metodo_pago`
  (oculta `_id` y el array `items`).
- **Update con `$set`, `$inc`, `$push`:** dar de baja un combo (`$set activo=false`), aumentar
  \$500 el precio de **todos** los combos (`$inc` + `update_many`), agregar un ítem a una venta
  (`$push`) y ajustar su total (`$inc`). Se verifica cada cambio releyendo.
- **Delete con `delete_one` y `delete_many`:** se insertan documentos de prueba marcados con
  `_test` y se borran (sin tocar el dataset de los pipelines).

📷 **CAPTURA 29:** _Filtro `$and`/`$or` con `$gte`/`$lte` (cantidad y ejemplos)._

📷 **CAPTURA 30:** _Proyección, updates (`$set`/`$inc`/`$push`) verificados y deletes._

### 4.2.3 Aggregation Pipelines

**Pipeline A — Top 5 combos más vendidos (con `$lookup`).** ¿Qué combos facturan más y cuál es su
composición vigente? Etapas:

1. `$unwind` `items` → una fila por ítem.
2. `$match` `tipo = "combo"` → solo ítems-combo.
3. `$group` por `combo_id` → suma facturación (`subtotal`) y unidades.
4. `$sort` por facturación desc + `$limit` 5.
5. `$lookup` a `combos` → nombre y `componentes` **vigentes** del catálogo.
6. `$unwind` + `$project` → forma de salida (incluye `$size` de componentes).

> Muestra la independencia entre el **hecho histórico** (facturación del snapshot de la venta) y
> la **definición actual** (nombre/componentes traídos del catálogo).

📷 **CAPTURA 31:** _Salida del Pipeline A (top 5 combos con facturación, unidades y nº de
componentes)._

**Pipeline B — Facturación y ticket promedio por mes.** ¿Cómo evoluciona la facturación mes a
mes? Etapas:

1. `$group` por año-mes de `fecha` → total facturado, ticket promedio (`$avg`) y cantidad.
2. `$sort` cronológico.
3. `$project` → etiqueta `YYYY-MM` legible (`$concat`/`$cond`) y redondeo del promedio.

📷 **CAPTURA 32:** _Salida del Pipeline B (facturación, ventas y ticket promedio por período)._

### Reflexión: PostgreSQL vs. SparkSQL vs. MongoDB

**Dónde MongoDB es más natural en este caso:**

- **Líneas heterogéneas sin NULLs:** ítem producto **o** combo se modela con documentos
  polimórficos; en SQL requería dos FKs (una siempre NULL) + `CHECK` + tabla puente.
- **Lectura de la venta completa sin joins:** venta y líneas en un único documento.
- **Esquema flexible:** campos opcionales no obligan a columnas nulas ni a `ALTER TABLE`.

**Dónde NO sería la mejor opción:**

- **Reporting analítico cruzado:** rankings con ventanas o múltiples joins son más expresivos y
  eficientes en **PostgreSQL** (índices, planes optimizados, funciones de ventana — Etapa 2).
- **Volumen masivo distribuido:** para barrer millones de registros, **SparkSQL** (Etapa 3)
  escala horizontalmente mejor que un pipeline sobre una única instancia.
- **Consistencia snapshot vs. catálogo:** denormalizar (copiar nombre/precio en la venta) implica
  que un cambio en el catálogo **no** se propaga a las ventas históricas. Es lo deseado para datos
  históricos, pero exige disciplina; el relacional evita esa duplicación.

**Conclusión.** La persistencia políglota consiste en usar cada motor donde es fuerte: PostgreSQL
como fuente de verdad transaccional y analítica, Redis para estado actual / colas / TTL con
latencia mínima, MongoDB para agregados ricos y de esquema variable, y Spark para procesamiento
distribuido a escala.

---

# Reproducción del entorno

**Requisitos:** Python 3.10+, Docker, Java JDK 17 (para Spark). Dependencias:
`pip install pymongo redis pyspark faker`.

**Servicios (Docker):**

| Servicio | Imagen | Puerto |
|----------|--------|--------|
| PostgreSQL | `postgis/postgis:16-3.4` | 5433 → 5432 |
| MongoDB | `mongo` (v8.2) | 27017 |
| Redis | `redis:7.2-alpine` | 6379 |

**Pasos:**

```bash
# Etapa 1 — PostgreSQL
psql -h localhost -p 5433 -U <usuario> -d <base> -f creacion_tablas.sql
python3 generar_datos.py            # regenera poblado_datos.sql (semilla fija, reproducible)
psql -h localhost -p 5433 -U <usuario> -d <base> -f poblado_datos.sql
psql -h localhost -p 5433 -U <usuario> -d <base> -f validar_datos.sql

# Etapa 2 — SQL avanzado (contra la base ya poblada)
psql ... -f queries_con_funciones_ventana.sql
psql ... -f queries_estadisticas.sql
psql ... -f create_index_23.sql     # índice de la propuesta 2.3

# Etapa 3 — Spark (requiere Java 17 y los CSV en data/)
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
jupyter notebook mapreduce_spark.ipynb

# Etapa 4 — NoSQL (idempotentes, se entregan con outputs ejecutados)
jupyter notebook redis_nosql.ipynb
jupyter notebook mongodb_documental.ipynb
```

> Todos los scripts y notebooks son **ejecutables de punta a punta sin modificaciones** y están
> comentados en español. Las notebooks se entregan con sus **outputs ejecutados** como evidencia.

---

## Anexo — Índice de archivos del repositorio

| Archivo | Etapa | Contenido |
|---------|-------|-----------|
| `creacion_tablas.sql` | 1.2 | Esquema: tablas, PK, FK, constraints |
| `generar_datos.py` | 1.3 | Generador reproducible → `poblado_datos.sql` |
| `poblado_datos.sql` | 1.3 | INSERTs (> 5000 registros principales) |
| `validar_datos.sql` | 1.3 | Validaciones de consistencia + estadísticos |
| `der.drawio` / `der.png` | 1.1 | Diagrama Entidad-Relación |
| `queries_con_funciones_ventana.sql` | 2.1 | 2 consultas con funciones de ventana |
| `queries_estadisticas.sql` | 2.2 | C1/C2/C3 con CTE |
| `Ejercicio_2.3_Analisis_Performance.docx` | 2.3 | Análisis de `EXPLAIN` |
| `create_index_23.sql` | 2.3 | Índice propuesto |
| `mapreduce_spark.ipynb` | 3.1 | 3 MapReduce con RDDs |
| `redis_nosql.ipynb` | 4.1 | KV/hashes, listas/cola, TTL |
| `mongodb_documental.ipynb` | 4.2 | Diseño documental, CRUD, aggregation |
| `README.md` | — | Instrucciones de reproducción |
