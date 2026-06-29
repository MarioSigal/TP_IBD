# TP IBD - Introducción a Bases de Datos

Dominio: **comercio minorista de suplementos deportivos**.

Este repositorio contiene la resolución del Trabajo Práctico Grupal, organizada por etapas.
Todos los scripts y notebooks están pensados para ejecutarse de punta a punta.

## Requisitos generales

- **Python 3.10+**
- **Docker** (para levantar PostgreSQL, MongoDB y Redis localmente)
- Dependencias de Python: `pip install pyspark pymongo redis notebook`
- **Java JDK 17 o 21** (solo para la Etapa 3 / Spark; ver detalle en esa sección)

---

## Etapa 1 - Modelo Relacional (PostgreSQL)

Archivos: `creacion_tablas.sql`, `generar_datos.py`, `poblado_datos.sql`,
`validar_datos.sql`, `der_viejo.drawio` / `der_nuevo.drawio` (diagramas DER, versiones
antigua y nueva).

**Entorno (Docker local):**

```bash
# Levantar PostgreSQL (puerto 5433 en el host -> 5432 en el contenedor)
docker run -d -p 5433:5432 --name ibd_postgres_db \
  -e POSTGRES_USER=<usuario> \
  -e POSTGRES_PASSWORD=<password> \
  -e POSTGRES_DB=<base> \
  postgis/postgis:16-3.4
```

**Ejecución:**

```bash
# 1) Crear el esquema
psql -h localhost -p 5433 -U <usuario> -d <base> -f creacion_tablas.sql

# 2) (Opcional) regenerar el poblado de datos
python3 generar_datos.py        # produce poblado_datos.sql

# 3) Poblar la base
psql -h localhost -p 5433 -U <usuario> -d <base> -f poblado_datos.sql

# 4) (Opcional) validar consistencia (debe devolver 0 filas en A-D)
psql -h localhost -p 5433 -U <usuario> -d <base> -f validar_datos.sql
```

## Etapa 2 - SQL Avanzado

Archivos: `queries_con_funciones_ventana.sql` (2.1), `queries_estadisticas.sql` (2.2),
`create_index_23.sql` + `Ejercicio_2.3_Analisis_Performance.docx` (2.3).

Se ejecutan con `psql` contra la base ya poblada, p. ej.:

```bash
psql -h localhost -p 5433 -U <usuario> -d <base> -f queries_con_funciones_ventana.sql
psql -h localhost -p 5433 -U <usuario> -d <base> -f queries_estadisticas.sql
psql -h localhost -p 5433 -U <usuario> -d <base> -f create_index_23.sql   # indice propuesto en 2.3
```

## Etapa 3 - Procesamiento con Spark (PySpark)

Notebook: `mapreduce_spark.ipynb`. Implementa 3 procesamientos MapReduce con la API de RDDs.

**Requiere Java (JDK 17 o 21)**, porque Spark corre sobre la JVM:

```bash
brew install openjdk@17
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
pip install pyspark
```

La notebook lee los datos desde CSV en la carpeta `data/` (separados por coma y con
encabezado). Hay que exportar tres tablas de la Etapa 1 **antes** de ejecutarla. Con la base
ya poblada:

```bash
mkdir -p data
psql -h localhost -p 5433 -U <usuario> -d <base> \
  -c "\copy ventas        TO 'data/ventas.csv'        WITH (FORMAT csv, HEADER true)"
psql -h localhost -p 5433 -U <usuario> -d <base> \
  -c "\copy detalle_ventas TO 'data/detalle_ventas.csv' WITH (FORMAT csv, HEADER true)"
psql -h localhost -p 5433 -U <usuario> -d <base> \
  -c "\copy metodos_pago  TO 'data/metodos_pago.csv'  WITH (FORMAT csv, HEADER true)"
```

Luego ejecutar la notebook de arriba a abajo (*Restart & Run All*).

## Etapa 4 - Persistencia Políglota (NoSQL)

### 4.1 Redis - `redis_nosql.ipynb`

Modelo clave-valor y hashes (punto 4.1.1) sobre el estado actual del negocio.

**Entorno (Docker local):**

```bash
docker run -d -p 6379:6379 --name redis-local-ibd redis:7.2-alpine
pip install redis
```

**Ejecución:**

1. Verificar que el contenedor de Redis esté corriendo (`docker ps`).
2. Ejecutar la notebook de arriba a abajo (*Restart & Run All*). Es idempotente: al inicio
   borra **solo sus claves** por prefijo con `SCAN` (no usa `FLUSHDB`, así no afecta otros
   datos en Redis).

**4.1.1 - Clave-valor y hashes.** Cubre los 3 tipos de datos pedidos: **stock bidireccional**
(dos hashes espejo `stock:producto:<id>` y `stock:sucursal:<id>`, consulta puntual en O(1) con
`HGET` y venta con `HINCRBY` atómico), **perfil de producto** (hash con `HGET`/`HGETALL` +
actualización) y **contador de ventas** (string con `INCR`/`INCRBYFLOAT`). Incluye la
justificación de Redis sobre PostgreSQL.

**4.1.2 - Lista como cola.** Los pedidos a entregar como **cola FIFO** (`pedidos:pendientes`):
la venta encola con `RPUSH`, el despacho saca el más antiguo con `LPOP`. Incluye consultas
(`LRANGE`, `LLEN`, `LINDEX`), gestión (`LPOP`/`RPUSH`/`RPOP`) y una simulación del flujo
completo. Motivado por el nuevo requerimiento de **ventas online con envío**.

**4.1.3 - TTL (tiempo de vida).** Tres datos que expiran solos, con TTL distinto y justificado:
**carrito de compras** (`carrito:cliente:<id>`, 30 min, se renueva con `EXPIRE`), **reserva
temporal de stock** (`reserva:stock:<prod>:<suc>`, 10 min) y **token de sesión**
(`sesion:token:<token>`, 1 hora). Verifica el tiempo restante con `TTL`/`PTTL` y demuestra la
expiración automática.

### 4.2 MongoDB - `mongodb_documental.ipynb`

Rediseño documental motivado por el nuevo requerimiento de **combos**: cada línea de venta
referencia un producto **o** un combo (en el modelo relacional generaría un NULL por fila).

**Entorno (Docker local con autenticación):**

```bash
docker run -d -p 27017:27017 --name mongo_ibd \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=<password> \
  mongo:7

pip install pymongo
```

**Ejecución:**

1. Verificar que el contenedor de Mongo esté corriendo (`docker ps`).
2. Ajustar el string de conexión `CONN` al principio de la notebook
   (`mongodb://<usuario>:<password>@localhost:27017/`), o reemplazarlo por el de MongoDB Atlas.
3. Ejecutar la notebook de arriba a abajo (*Restart & Run All*). Es idempotente: limpia sus
   colecciones (`ventas`, `combos`) antes de cargar, así puede re-ejecutarse sin duplicar.

Cubre: configuración del entorno, diseño de colecciones (`ventas` con `items[]` embebidos y
polimórficos + `combos` con `componentes[]`), carga de >100 documentos por colección
(`insert_one` / `insert_many`), CRUD completo (filtros `$gte`/`$lte`/`$and`/`$or`, proyección,
`$set`/`$inc`/`$push`, `delete_one`/`delete_many`) y 2 aggregation pipelines (incluye
`$lookup` entre `ventas` y `combos`).
