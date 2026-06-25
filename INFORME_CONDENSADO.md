# Trabajo Práctico — Introducción a Bases de Datos (UBA, 2026)

**Dominio:** comercio minorista de suplementos deportivos.
Cadena con varias sucursales que compra a proveedores, mantiene stock por sucursal y vende a
clientes.

> Los recuadros 📷 **CAPTURA N** indican dónde insertar la imagen del resultado. Reemplazar por
> `![CAPTURA N](capturas/captura_N.png)` antes de exportar a PDF.

---

# Etapa 1 — Modelo Relacional (PostgreSQL)

## 1.1 Elección del modelo

**Por qué este dominio.** Es lo bastante rico para sustentar todas las etapas: tiene entidades
maestras (categorías, marcas, productos, proveedores, sucursales, clientes) y transaccionales
(compras y ventas con detalle), genera métricas reales (facturación, profit, ticket, stock,
recencia de clientes) y admite nuevos requerimientos (ventas online, combos, estado de stock en
tiempo real) que motivan la persistencia políglota de la Etapa 4.

📷 **CAPTURA 1:** DER (`der.png`) con las 11 tablas y sus relaciones.

| Maestras | Asociativa | Transaccionales |
|---|---|---|
| `CATEGORIAS`, `MARCAS`, `PRODUCTOS`, `PROVEEDORES`, `PUNTOS_DE_VENTA`, `CLIENTES` | `STOCK` (M:N producto–sucursal) | `COMPRAS`/`DETALLE_COMPRAS`, `VENTAS`/`DETALLE_VENTAS` |

**Decisiones de diseño.**
- *Incluido:* `STOCK` como asociativa M:N con PK compuesta `(product_id, puntos_de_venta_id)` y
  atributos del vínculo (`cantidad`, `stock_minimo`, `fecha_actualizacion`); patrón
  **cabecera/detalle** en compras y ventas; **un único `precio`** de venta por producto;
  `ultimo_costo` como costo de venta (`precio_unidad`/`costo_unidad` se guardan como *snapshot*
  en el detalle).
- *Agregado:* identificadores naturales (`sku`, `cuit`, `dni`, `email`), `MARCAS.origen` y
  `es_importado` (análisis nacional vs. importado).
- *Dejado fuera (decisión de normalización):* **no se almacenan atributos derivables** — se
  calculan al vuelo. Se eliminaron `subtotal`/`profit` de `DETALLE_VENTAS`
  (`cantidad·precio_unidad` y `cantidad·(precio_unidad−costo_unidad)`), `precio_total`/
  `costo_total` de `VENTAS` (SUM del detalle), `total` de `COMPRAS` y `subtotal` de
  `DETALLE_COMPRAS`. También se eliminó la **lógica fiel/normal** (`es_cliente_fiel`,
  `precio_normal`, `precio_fiel`) y `estado_entrega`. Evita redundancia y riesgo de
  inconsistencia. *Otros descartes:* índices manuales (lo pide el enunciado; ver 1.2); kardex de
  stock (se guarda el **saldo actual**); datos geográficos.

**Constraints de negocio** (todos en `creacion_tablas.sql`):
- **PK** `INTEGER` manual en todas; **UNIQUE** en `nombre`(categorías/marcas/sucursales), `sku`,
  `cuit`, `dni`, `email`.
- **No negatividad (`CHECK`):** `precio`, `ultimo_costo`, `precio_unidad`, `costo_unidad`,
  `STOCK.cantidad`, `stock_minimo` `>= 0`; `cantidad > 0` en los detalles.
- **Enumerados:** `metodo_pago ∈ {EFECTIVO, TRANSFERENCIA, TARJETA_CREDITO, TARJETA_DEBITO,
  MERCADOPAGO, OTRO}`.
- *(Al eliminar los campos derivables ya no aplican los CHECK de coherencia `subtotal`/`profit`
  ni la regla `precio_fiel ≤ precio_normal`.)*
- **Formato:** `email` válido por regex o `NULL`; `LENGTH(TRIM(...)) > 0` (sin strings vacíos);
  `NOT NULL` en obligatorias.
- **FK:** `ON UPDATE CASCADE`; `ON DELETE RESTRICT` (producto/sucursal con datos),
  `SET NULL` (cliente/proveedor → la transacción histórica se conserva anónima),
  `CASCADE` en los detalles (no tienen vida propia).

## 1.2 Implementación en PostgreSQL — `creacion_tablas.sql`

**Tipos:** `INTEGER` (PK/IDs), `VARCHAR(n)`/`TEXT` (textos), **`NUMERIC(12,2)`** para dinero
(decimal exacto, no `FLOAT`), `DATE`+`TIME`/`TIMESTAMP`, `BOOLEAN` (flags). PK de **carga manual**
por requisito del TP.

**Índices:** el enunciado pide no crear índices manuales en esta etapa. PostgreSQL igual crea
índices B-tree **implícitos** para respaldar cada `PRIMARY KEY`/`UNIQUE` (`<tabla>_pkey`): son
inevitables, parte de la definición del modelo, no una optimización. El único índice manual está
en 2.3.

📷 **CAPTURA 2:** `creacion_tablas.sql` ejecutado + `\dt` con las 11 tablas.

## 1.3 Poblado y validación

`generar_datos.py` → `poblado_datos.sql`. **Semilla fija (`seed=42`)** → reproducible; mantiene
los datos en memoria para calcular saldos de stock coherentes; emails sin acentos (respeta el
`CHECK`); `ON CONFLICT DO NOTHING` → idempotente.

| Tabla | Reg. | Tabla | Reg. |
|---|---:|---|---:|
| CATEGORIAS | 6 | CLIENTES | 1 500 |
| MARCAS | 10 | STOCK | 380 |
| PROVEEDORES | 6 | COMPRAS | 120 |
| PUNTOS_DE_VENTA | 4 | DETALLE_COMPRAS | 715 |
| PRODUCTOS | 95 | **VENTAS** | **5 200** ✅ |
| | | **DETALLE_VENTAS** | **13 132** ✅ |

**Variedad:** fechas en 6 meses, 6 métodos de pago, ventas con y sin cliente, marcas
nacionales/importadas con precios distintos.

**Validación (`validar_datos.sql`)** — deben devolver 0 filas: integridad referencial del detalle
(venta y producto existentes), ventas sin líneas (cabecera huérfana) y coherencia de margen
(ninguna línea con `precio_unidad < costo_unidad`). Incluye estadísticos C1/C2/C3 al estilo de la
práctica reconstruyendo los montos desde el detalle (generalizados en 2.2).

📷 **CAPTURA 3:** totales de `generar_datos.py` + `COUNT(*)` por tabla.
📷 **CAPTURA 4:** las 4 validaciones devolviendo 0 filas y las salidas C1/C2/C3.

---

# Etapa 2 — SQL Avanzado

## 2.1 Funciones de ventana — `queries_con_funciones_ventana.sql`

**Consulta 1 — Top 3 productos más rentables por categoría.** *Negocio:* decidir surtido y
promociones por categoría. *Por qué ventana:* el ranking es una métrica de grupo que debe verse
en **cada** fila de producto; un `GROUP BY` por categoría colapsa el detalle y no puede asignar
posición a cada producto, y `RANK`/`DENSE_RANK` **solo** existen como funciones de ventana.
`DENSE_RANK() OVER (PARTITION BY categoria_id ORDER BY profit_total DESC)` agrupa sin colapsar; se
usa `DENSE_RANK` para que los empates compartan posición. Como `profit` ya no se almacena,
`profit_total` se calcula al vuelo: `SUM(cantidad·(precio_unidad−costo_unidad))`.

📷 **CAPTURA 5:** resultado top 3 por categoría.

**Consulta 2 — Historial de compra por cliente.** *Negocio:* recencia/frecuencia y valor
acumulado (CLV). Para cada venta: nº de compra, gasto acumulado y días desde la compra anterior.
*Por qué ventana:* las tres métricas dependen del **orden** y la **posición** dentro del historial
del cliente — `ROW_NUMBER()` (ordinal), `SUM() OVER (... ROWS UNBOUNDED PRECEDING)` (running
total) y `LAG(fecha)` (fila anterior) — imposibles con `GROUP BY`, que no tiene noción de orden ni
de "fila previa". Como `precio_total` ya no es columna, una CTE previa lo reconstruye por venta
(`SUM(cantidad·precio_unidad)`) y la ventana opera sobre esa CTE.

📷 **CAPTURA 6:** resultado para un cliente con varias compras.

## 2.2 Funciones estadísticas — `queries_estadisticas.sql`

Tabla `VENTAS`. Como ya no guarda columnas numéricas, las tres consultas parten de una **CTE
(`WITH`) `ventas_ext`** que reconstruye `precio_total`/`costo_total` por venta desde el detalle
(cumple además el requisito de CTE).
- **C1 — perfil de cada columna:** total de filas, no nulos, % no nulos y valores distintos de las
  8 columnas de `ventas_ext`. Formato largo con `UNION ALL`; `COUNT(col)` vs `COUNT(*)` revela los
  nulos (`cliente_id` es la única < 100%).
- **C2 — numéricas (`precio_total`, `costo_total`, calculadas):** desvío, mín, P05, Q1, mediana,
  promedio, Q3, P95, máx, % ceros, % negativos y **outliers** por regla de Tukey
  (`[Q1−1.5·IQR ; Q3+1.5·IQR]`). Percentiles con `PERCENTILE_CONT WITHIN GROUP`.
- **C3 — categóricas (`metodo_pago`, `puntos_de_venta_id`):** top 10 valores por frecuencia y %,
  agrupando el resto en `(resto)` (vía `ROW_NUMBER()` + `SUM() OVER ()`). *(Se usa la sucursal como
  segunda categórica porque `estado_entrega` fue eliminado.)*

📷 **CAPTURA 7:** salidas de C1, C2 y C3.

## 2.3 Análisis de performance — `Ejercicio_2.3_Analisis_Performance.docx`, `create_index_23.sql`

Se analiza la **Consulta 1 de 2.1** (la más compleja: 3 joins + `GROUP BY` + ventana + 2 sorts).

Ahora `profit_total` se calcula como `SUM(cantidad·(precio_unidad−costo_unidad))` e `ingresos`
como `SUM(cantidad·precio_unidad)` (las columnas `subtotal`/`profit` ya no existen).

📷 **CAPTURA 8:** `EXPLAIN ANALYZE` de la consulta original.

> Valores de costo ilustrativos (de la corrida previa); regenerar con la captura sobre los datos
> actuales. La **estructura** del plan y el razonamiento se mantienen.

| Operación | Costo acum. | Agrega |
|---|---:|---:|
| `Seq Scan` detalle_ventas | 262 | — |
| `Sort` por product_id (Merge Join) | 1 143 | +880 |
| `Merge Join` + `Nested Loop` | 1 359 | +216 |
| `GroupAggregate` (GROUP BY) | 2 366 | +1 007 |
| `Sort` (categoria_id, profit_total) | 5 585 | +3 122 |
| `WindowAgg` (DENSE_RANK) | 5 843 | +258 |
| `Sort` final | **9 094** | +3 122 |

**Lectura.** Los tres `Sort` concentran casi todo el costo. El `Seq Scan` (262) es óptimo: la
consulta agrega toda la tabla **sin `WHERE`**, leerla entera es lo esperable. Aparece
`Run Condition: dense_rank() <= 3` → el motor empuja el filtro top-3 dentro del `WindowAgg`. Los
`Index Scan` `productos_pkey`/`categorias_pkey` son los índices **implícitos** de las PK (el join
es por PK sobre tablas chicas).

**Propuesta.** De los 3 `Sort`, dos ordenan **valores derivados** (`profit_total` = `SUM`;
`posicion_en_categoria` = resultado del `DENSE_RANK`) → **no indexables**. El único atacable es el
`Sort` por `product_id` (+880), que ordena una columna base solo para el `Merge Join`:

```sql
CREATE INDEX idx_detalle_ventas_producto
ON detalle_ventas (product_id) INCLUDE (cantidad, precio_unidad, costo_unidad);
```

Elimina ese `Sort` (entrega las filas ya ordenadas) y habilita **`Index Only Scan`** (el
`INCLUDE` cubre las columnas base que necesitan los `SUM` —ahora `precio_unidad`/`costo_unidad`—
sin tocar el heap). Costo estimado **~9 094 → ~8 200 (≈10%)**.

📷 **CAPTURA 9:** `EXPLAIN (ANALYZE, BUFFERS)` con el índice (`Index Only Scan` reemplaza
`Seq Scan`+`Sort`).

**Conclusión.** La mejora es acotada (~10%) — hallazgo en sí mismo: sin filtro selectivo no hay
subconjunto pequeño que indexar; el grueso son los 2 `Sort` sobre valores derivados, inherentes a
las funciones de ventana. La mayor palanca sería **reescribir** la consulta para que los `Sort`
muevan filas angostas (rankear solo con IDs/números y unir los nombres al final), reduciendo el
`width=370` que hoy arrastra los textos por todo el plan.

---

# Etapa 3 — MapReduce con Spark (RDDs) — `mapreduce_spark.ipynb`

Tres procesamientos con la **API de RDDs** sobre los CSV de la Etapa 1 (`data/`). Requiere
**Java JDK 17** (Spark sobre JVM).

**Lazy evaluation.** `map`/`filter`/`reduceByKey` son **transformaciones perezosas**: arman el DAG
sin computar. El cómputo se dispara con una **acción** (`collect`, `takeOrdered`), aplicando
*combine* local por partición antes del shuffle. Los RDD base se cachean (se reusan).

Como `precio_total`/`profit` ya no son columnas, primero se reconstruye el **monto por venta**
desde `detalle_ventas` (`SUM(cantidad·precio_unidad)`, `reduceByKey` por `venta_id`) y se reutiliza.

| # | Pregunta | Map → (clave, valor) | Reduce | Acción |
|---|---|---|---|---|
| 1 | Facturación, nº ventas y ticket por sucursal | `join`(monto×ventas) → `(pdv_id, (monto, 1))` | `reduceByKey` suma componente a componente; `mapValues` deriva ticket | `collect` |
| 2 | Top 10 productos por profit | `(product_id, cantidad·(precio_unidad−costo_unidad))` | `reduceByKey` suma profit | `takeOrdered(10)` (orden distribuido) |
| 3 | Ventas e ingresos por método de pago | `join`(monto×ventas) → `(metodo_pago, (1, monto))` | `reduceByKey` suma ambos | `collect` + % |

Las operaciones de reduce son asociativas y conmutativas → habilitan el *map-side combine*.

📷 **CAPTURA 10:** `SparkContext` activo + resultados de las Consultas 1, 2 y 3.

---

# Etapa 4 — Persistencia Políglota (NoSQL)

PostgreSQL sigue siendo la **fuente de verdad**; Redis y MongoDB cubren patrones que el relacional
resuelve de forma incómoda.

## 4.1 Redis — `redis_nosql.ipynb`

Redis 7.2 (Docker), `localhost:6379`, `decode_responses=True`. Idempotente: borra **solo sus
claves** por prefijo con `SCAN` (no `FLUSHDB`).

**4.1.1 Clave-valor y hashes** — tres datos del estado actual, consultados por ID:
1. **Stock bidireccional** → dos hashes espejo `stock:producto:<id>` y `stock:sucursal:<id>`.
   Duplicar es a propósito (modelado por patrón de acceso): responde en **O(1)** "stock del
   producto P en sucursal S" con `HGET`, y la dirección inversa. La **venta** descuenta con
   `HINCRBY` atómico sobre ambos hashes en una transacción (`MULTI`/pipeline); se verifica
   releyendo las dos vistas.
2. **Perfil de producto** → hash `producto:<id>` (`HGET`/`HGETALL`); update de precio con `HSET`
   verificado.
3. **Contador de ventas del día** → string con `INCR` atómico; caja con `INCRBYFLOAT`.

*Por qué Redis y no PostgreSQL:* latencia sub-ms por acceso O(1) en RAM; atomicidad sin locks de
fila (`INCR`/`HINCRBY`); modelado por patrón de acceso (O(1) en ambas direcciones). *Límite:* no
reemplaza a PostgreSQL como verdad durable ni para `WHERE`/`JOIN`; se reconstruye desde la base.

📷 **CAPTURA 11:** stock (`HGET`/`HGETALL` ambas vistas), venta con `HINCRBY` y verificación de
consistencia, perfil + update de precio, contador `INCR`/`INCRBYFLOAT`.

**4.1.2 Lista como cola (ventas online con envío).** El pedido online no se entrega en el acto:
cola **FIFO** en `pedidos:pendientes`. Venta → `RPUSH` (final); despacho → `LPOP` (frente, el más
antiguo). Consulta: `LRANGE`/`LLEN`/`LINDEX 0` (peek). Gestión: `LPOP`/`RPUSH`/`RPOP` (cancelar el
último). Se simula el flujo completo intercalando ventas y despachos.

📷 **CAPTURA 12:** carga de la cola, `LRANGE`/`LLEN` y simulación del flujo.

**4.1.3 TTL — datos que expiran solos:**

| Dato | Clave | TTL | Por qué |
|---|---|---|---|
| Carrito | `carrito:cliente:<id>` | 30 min | Conserva la selección; libera abandonados; se renueva con `EXPIRE`. |
| Reserva de stock | `reserva:stock:<p>:<s>` | 10 min | Reserva mientras paga; si no concreta, libera (evita sobreventa). |
| Token de sesión | `sesion:token:<t>` | 1 h | Mantiene logueado; vence por seguridad. |

Se verifica con `TTL`/`PTTL` (`-1` sin expiración, `-2` ya no existe) y se demuestra la expiración
real con un TTL corto (2 s).

📷 **CAPTURA 13:** creación de las 3 claves con TTL, verificación y expiración automática.

## 4.2 MongoDB — `mongodb_documental.ipynb`

**Entorno:** MongoDB local (Docker, v8.2), reproducible. Conexión (anonimizada):
`mongodb://<usuario>:<password>@localhost:27017/`. Alternativa Atlas: cambiar `CONN` por
`mongodb+srv://...`. *Problema típico:* contenedor apagado → `ServerSelectionTimeoutError`
(`docker ps` / `docker start`). Idempotente (dropea sus colecciones al cargar).

**4.2.1 Diseño (nuevo requerimiento: combos).** Cada línea de venta referencia un producto **o**
un combo. En el relacional obligaría a tener `product_id` **y** `combo_id` con uno **NULL por
fila** + `CHECK` de exclusividad. El modelo documental lo evita: cada ítem lleva **solo sus
campos**. Dos colecciones:
- **`ventas`**: un documento por venta con líneas **embebidas** en `items[]` **polimórfico**
  (`tipo: "producto"|"combo"`). La venta es un agregado natural (se lee entera) y los ítems son
  acotados (1–4). `cliente_id` se **referencia**.
- **`combos`**: catálogo con composición embebida (`componentes[]`); vive por su cuenta (existe
  aunque no se haya vendido), se trae con `$lookup`.

*Embeber vs. referenciar:* se embeben líneas y componentes; se referencia cliente y combo.
*Opcionales/variables:* `cliente_id` (anónimas), `descripcion`, y campos según `tipo` — **sin
NULLs**. *Vs. relacional:* sin tabla puente ni FKs nullable ni `CHECK`; venta completa sin joins.
Como parte del diseño se **generan** los documentos en memoria: **100 combos** y **130 ventas**
(≥100 por colección, como pide la consigna). *(La inserción en MongoDB se hace en 4.2.2.)*

**4.2.2 CRUD.** Empieza por la **inserción** de los documentos generados (`insert_one` para uno y
`insert_many` para el lote, con `drop()` previo idempotente, en ambas colecciones). Luego: read con
`$gte`/`$lte` + `$and`/`$or` (ventas de monto alto con tarjeta/MP);
proyección (reporte liviano); update con `$set` (baja de combo), `$inc`+`update_many` (aumento a
todos), `$push` (agregar ítem a una venta); delete con `delete_one`/`delete_many` sobre docs de
prueba `_test`.

**4.2.3 Aggregation pipelines.**
- **A — Top 5 combos (con `$lookup`):** `$unwind` items → `$match tipo=combo` → `$group` por
  `combo_id` (facturación, unidades) → `$sort`+`$limit 5` → `$lookup` a `combos` →
  `$unwind`+`$project`. Separa el **hecho histórico** (subtotal del snapshot) de la **definición
  vigente** (nombre/componentes del catálogo).
- **B — Facturación y ticket por mes:** `$group` por año-mes (`$sum`, `$avg`) → `$sort`
  cronológico → `$project` con etiqueta `YYYY-MM` (`$concat`/`$cond`).

📷 **CAPTURA 14:** conteos de carga (>100 c/u), CRUD verificado y salidas de los pipelines A y B.

**Reflexión PostgreSQL vs. SparkSQL vs. MongoDB.** *Mongo natural acá:* líneas heterogéneas sin
NULLs (documentos polimórficos), lectura de la venta completa sin joins, esquema flexible. *No es
la mejor opción:* reporting analítico cruzado y ventanas → **PostgreSQL**; volumen masivo
distribuido → **SparkSQL**; consistencia snapshot/catálogo → la denormalización exige disciplina
(el cambio de catálogo no se propaga a ventas históricas, deseado pero a vigilar). **La
persistencia políglota usa cada motor donde es fuerte.**

---

# Reproducción del entorno

Python 3.10+, Docker, Java 17. `pip install pymongo redis pyspark faker`.

| Servicio | Imagen | Puerto |
|---|---|---|
| PostgreSQL | `postgis/postgis:16-3.4` | 5433→5432 |
| MongoDB | `mongo` (v8.2) | 27017 |
| Redis | `redis:7.2-alpine` | 6379 |

```bash
# Etapa 1
psql -h localhost -p 5433 -U <u> -d <db> -f creacion_tablas.sql
python3 generar_datos.py && psql ... -f poblado_datos.sql && psql ... -f validar_datos.sql
# Etapa 2
psql ... -f queries_con_funciones_ventana.sql -f queries_estadisticas.sql -f create_index_23.sql
# Etapa 3 (Java 17 + CSV en data/)
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"; jupyter notebook mapreduce_spark.ipynb
# Etapa 4 (idempotentes, con outputs ejecutados)
jupyter notebook redis_nosql.ipynb mongodb_documental.ipynb
```

Todos los scripts/notebooks son ejecutables de punta a punta sin modificaciones, comentados en
español; las notebooks se entregan con sus outputs como evidencia.
