# CLAUDE.md

Contexto del proyecto para asistentes (Claude Code). Trabajo Práctico **grupal** de la materia
**Introducción a Bases de Datos (IBD)** — UBA, 2026.

## De qué se trata

Integra distintos paradigmas de gestión de datos sobre un **dominio único**:
**comercio minorista de suplementos deportivos** (productos, marcas, categorías, clientes,
puntos de venta, compras, ventas y stock).

El enunciado completo está en `IBD_TrabajoPractico.pdf`. El entregable principal es un
**informe PDF (≤15 páginas)** + los scripts/notebooks + este repo. El código debe ser
**ejecutable de punta a punta sin modificaciones** y estar comentado (en español).

## Etapas y archivos

| Etapa | Tema | Archivos | Estado |
|-------|------|----------|--------|
| 1 | Modelo relacional (PostgreSQL) | `creacion_tablas.sql`, `generar_datos.py` → `poblado_datos.sql`, `validar_datos.sql`, `der.drawio`/`der.png` | ✅ |
| 2.1 | Funciones de ventana | `queries_con_funciones_ventana.sql` | ✅ |
| 2.2 | Funciones estadísticas | `queries_estadisticas.sql` | ✅ |
| 2.3 | Análisis de performance (EXPLAIN) | `Ejercicio_2.3_Analisis_Performance.docx`, `create_index_23.sql` | ✅ |
| 3.1 | MapReduce con Spark (PySpark RDDs) | `mapreduce_spark.ipynb` | ⚠️ ver nota |
| 4.1 | Redis (KV/hashes, listas, TTL) | `redis_nosql.ipynb` | ✅ |
| 4.2 | MongoDB (documental) | `mongodb_documental.ipynb` | ✅ |

## Entorno (contenedores Docker ya levantados)

| Servicio | Contenedor | Imagen | Puerto | Credenciales |
|----------|-----------|--------|--------|--------------|
| PostgreSQL | `ibd_postgres_db` | `postgis/postgis:16-3.4` | **5433**→5432 | (las del grupo) |
| MongoDB | `mongo_ibd` | `mongo` (v8.2) | 27017 | `admin` / `secret` |
| Redis | `redis-local-ibd` | `redis:7.2-alpine` | 6379 | sin auth |

Strings de conexión usados en los notebooks:
- Mongo: `mongodb://admin:secret@localhost:27017/` (credenciales anonimizadas en el texto del informe).
- Redis: `redis://localhost:6379` (`decode_responses=True`).

Dependencias Python: `pip install pymongo redis pyspark`. Spark además **requiere Java JDK 17**
(`brew install openjdk@17`; setear `JAVA_HOME`).

## Cómo correr cada cosa

```bash
# Etapa 1 (PostgreSQL en puerto 5433)
psql -h localhost -p 5433 -U <usuario> -d <base> -f creacion_tablas.sql
python3 generar_datos.py            # regenera poblado_datos.sql (seed fija 42, reproducible)
psql -h localhost -p 5433 -U <usuario> -d <base> -f poblado_datos.sql

# Notebooks (4.1 y 4.2): ejecutar de punta a punta
jupyter notebook redis_nosql.ipynb      # idempotente: limpia solo SUS claves por prefijo
jupyter notebook mongodb_documental.ipynb  # idempotente: dropea sus colecciones al cargar
```

Para validar un notebook headless (como se hace al iterar):
`python3 -m jupyter nbconvert --to notebook --execute --inplace --ExecutePreprocessor.timeout=120 <archivo>.ipynb`

## Convenciones y restricciones importantes

- **PKs INTEGER de carga manual** (requisito explícito del TP), no `SERIAL`.
- **Etapa 1 NO debe incluir índices** (lo dice el enunciado). PostgreSQL igual crea índices
  automáticos para PK/UNIQUE (`*_pkey`); el único índice manual aparece en 2.3
  (`create_index_23.sql`), como propuesta de optimización analizada con EXPLAIN.
- Strings de salida/datos generalmente **sin acentos** en código y prints (evita problemas de
  encoding y respeta el `CHECK` de emails en `clientes`).
- Los **constraints de negocio** viven en `creacion_tablas.sql` (CHECKs: precios ≥ 0,
  `precio_fiel ≤ precio_normal`, `subtotal = cantidad * precio`, `profit = subtotal - costo`, etc.).
- `generar_datos.py` mantiene **todos los datos en memoria** antes de escribir el `.sql`
  (listas `ventas`, `detalle_ventas`, `productos`, …). Reutilizar esa fuente si se necesitan CSVs.
- Notebooks: **idempotentes** y se entregan **con outputs ejecutados** (sirven de evidencia
  para el informe). Mantener ese criterio al editarlos.

## Pendientes conocidos

- **Etapa 3 (Spark)**: `mapreduce_spark.ipynb` lee CSVs desde `data/`, que **no existe** aún.
  Falta exportar las tablas de la Etapa 1 a `data/*.csv` (lo natural: que `generar_datos.py`
  también vuelque CSVs reutilizando las listas en memoria). Además, requiere Java 17 instalado.

## Repo

GitHub: `https://github.com/MarioSigal/TP_IBD.git` — rama principal `main`.
