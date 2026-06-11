import random
import datetime
import math

# Intentar importar Faker, si no, usar generadores locales simples
try:
    from faker import Faker
    fake = Faker('es_AR')
except ImportError:
    fake = None
    print("Faker no está instalado. Se utilizarán generadores de texto internos.")

# --- DATOS SEMILLA ---
CATEGORIAS = [
    (1, "Proteínas", "Suplementos de proteína en polvo para desarrollo muscular"),
    (2, "Creatinas", "Creatina monohidratada y fórmulas para fuerza y potencia"),
    (3, "Aminoácidos", "BCAAs, Glutamina y otros aminoácidos para recuperación"),
    (4, "Quemadores de Grasa", "Termogénicos y lipotrópicos para pérdida de peso"),
    (5, "Pre-Entrenamientos", "Fórmulas de energía, óxido nítrico y enfoque"),
    (6, "Vitaminas y Salud", "Multivitamínicos, Omega 3 y salud general")
]

MARCAS = [
    (1, "Ena Sport", "Argentina", False),
    (2, "Star Nutrition", "Argentina", False),
    (3, "Nutrilab", "Argentina", False),
    (4, "Hoch Sport", "Argentina", False),
    (5, "Pulver", "Argentina", False),
    (6, "Optimum Nutrition", "EEUU", True),
    (7, "Dymatize", "EEUU", True),
    (8, "Universal Nutrition", "EEUU", True),
    (9, "BSN", "EEUU", True),
    (10, "MuscleTech", "EEUU", True)
]

SABORES = ["Chocolate", "Vainilla", "Frutilla", "Cookies & Cream", "Banana", "Neutra", "Manzana", "Limón"]
MEDIDAS = ["1 kg", "2 kg", "500 g", "300 g", "90 serv", "60 serv", "30 serv", "120 tabs", "90 caps"]

PRODUCTOS_PLANTILLA = [
    # (nombre, categoria_id, unidad, descripccion_medida, costo_base, precio_base)
    ("Whey Protein 100%", 1, "pote", "1 kg", 20000.00, 29000.00),
    ("Isolate Whey Protein", 1, "pote", "1 kg", 28000.00, 42000.00),
    ("Creatina Monohidrato", 2, "pote", "300 g", 15000.00, 22000.00),
    ("Creatina Micronizada", 2, "pote", "300 g", 18000.00, 26000.00),
    ("BCAA 2:1:1 en Polvo", 3, "pote", "300 g", 10000.00, 15000.00),
    ("Glutamina Micronizada", 3, "pote", "300 g", 9000.00, 13500.00),
    ("Colágeno Hidrolizado", 3, "pote", "250 g", 12000.00, 18500.00),
    ("Quemador Termogénico Lipocut", 4, "caja", "90 caps", 8000.00, 12500.00),
    ("L-Carnitina Líquida", 4, "botella", "500 ml", 7000.00, 11000.00),
    ("Pre-Entrenamiento Pump", 5, "pote", "30 serv", 11000.00, 16900.00),
    ("Pre-Entrenamiento C4", 5, "pote", "30 serv", 22000.00, 33000.00),
    ("Multivitamínico Diario", 6, "pote", "120 tabs", 5000.00, 8000.00),
    ("Omega 3 Ultra", 6, "pote", "90 caps", 6500.00, 9900.00),
]

PUNTOS_DE_VENTA = [
    (1, "Sucursal Palermo", "Av. Santa Fe 3400, CABA", "11-4822-1234"),
    (2, "Sucursal Belgrano", "Av. Cabildo 2100, CABA", "11-4788-5678"),
    (3, "Sucursal Centro", "Lavalle 600, CABA", "11-4322-9012"),
    (4, "Sucursal Caballito", "Av. Rivadavia 5100, CABA", "11-4901-3456")
]

PROVEEDORES = [
    (1, "Distribuidora NutriArg", "30-71458922-5"),
    (2, "Suplementos Mayoristas S.A.", "30-58441239-1"),
    (3, "Importadora Fitness Group", "30-66235899-2"),
    (4, "Laboratorio Ena Argentina", "30-50114498-3"),
    (5, "NutriBrand Distribuciones", "30-71885623-6"),
    (6, "Suplementos Deportivos Importados", "30-71112223-9")
]

METODOS_PAGO = ["EFECTIVO", "TRANSFERENCIA", "TARJETA_CREDITO", "TARJETA_DEBITO", "MERCADOPAGO", "OTRO"]
ESTADOS_ENTREGA = ["PENDIENTE", "ENTREGADO"]

def escape_sql(val):
    if val is None:
        return "NULL"
    if isinstance(val, bool):
        return "TRUE" if val else "FALSE"
    if isinstance(val, (int, float)):
        return str(val)
    # Reemplazar comillas simples para evitar SQL injection
    escaped = str(val).replace("'", "''")
    return f"'{escaped}'"

def generar_datos_sql():
    print("Iniciando generación de datos...")
    
    # 1. CATEGORIAS y MARCAS
    sql_lines = []
    sql_lines.append("-- === 1. CATEGORIAS ===")
    for cat in CATEGORIAS:
        sql_lines.append(f"INSERT INTO CATEGORIAS (categoria_id, nombre, descripcion) VALUES ({cat[0]}, {escape_sql(cat[1])}, {escape_sql(cat[2])}) ON CONFLICT DO NOTHING;")
        
    sql_lines.append("\n-- === 2. MARCAS ===")
    for m in MARCAS:
        sql_lines.append(f"INSERT INTO MARCAS (marca_id, nombre, origen, es_importado) VALUES ({m[0]}, {escape_sql(m[1])}, {escape_sql(m[2])}, {escape_sql(m[3])}) ON CONFLICT DO NOTHING;")

    sql_lines.append("\n-- === 4. PROVEEDORES ===")
    for p in PROVEEDORES:
        sql_lines.append(f"INSERT INTO PROVEEDORES (proveedor_id, nombre, cuit) VALUES ({p[0]}, {escape_sql(p[1])}, {escape_sql(p[2])}) ON CONFLICT DO NOTHING;")

    sql_lines.append("\n-- === 5. PUNTOS_DE_VENTA ===")
    for pv in PUNTOS_DE_VENTA:
        sql_lines.append(f"INSERT INTO PUNTOS_DE_VENTA (puntos_de_venta_id, nombre, direccion, telefono) VALUES ({pv[0]}, {escape_sql(pv[1])}, {escape_sql(pv[2])}, {escape_sql(pv[3])}) ON CONFLICT DO NOTHING;")

    # 2. PRODUCTOS
    # Generar unos 120 productos combinando plantillas, marcas y sabores/medidas
    sql_lines.append("\n-- === 3. PRODUCTOS ===")
    productos = []
    prod_id = 1
    
    # Asegurar reproducibilidad
    random.seed(42)
    
    for brand_id, brand_name, brand_origin, is_imp in MARCAS:
        # Elegir de 8 a 12 productos de la plantilla para cada marca
        plantillas_seleccionadas = random.sample(PRODUCTOS_PLANTILLA, k=random.randint(8, 11))
        for nombre_base, cat_id, unidad, med_default, costo_base, precio_base in plantillas_seleccionadas:
            medida = random.choice(MEDIDAS) if "kg" not in nombre_base else med_default
            sabor = random.choice(SABORES) if cat_id in [1, 3, 5] else "Sin Sabor"
            
            # Ajustar precios si es importado
            costo = costo_base * (1.5 if is_imp else 1.0) * random.uniform(0.9, 1.1)
            precio_normal = precio_base * (1.5 if is_imp else 1.0) * random.uniform(0.95, 1.15)
            # Asegurar consistencia de profit y precios no negativos
            costo = round(costo, 2)
            precio_normal = max(round(precio_normal, 2), round(costo * 1.1, 2)) # al menos 10% de markup
            precio_fiel = round(precio_normal * random.uniform(0.88, 0.95), 2)  # entre 5% y 12% de descuento para clientes fieles
            
            nombre_completo = f"{brand_name} {nombre_base} ({sabor}, {medida})"
            # SKU: BRAND-NAME-MEDIDA-SABOR
            sku_parts = [
                brand_name.upper().replace(" ", "")[:4],
                nombre_base.upper().replace(" ", "").replace("100%", "")[:6],
                medida.upper().replace(" ", "")[:4],
                sabor.upper()[:4]
            ]
            sku = "-".join(sku_parts) + f"-{prod_id}"
            
            prod_record = {
                'product_id': prod_id,
                'sku': sku,
                'nombre': nombre_completo,
                'marca_id': brand_id,
                'categoria_id': cat_id,
                'unidad': unidad,
                'descripccion_medida': medida,
                'sabor': sabor,
                'costo_promedio': costo,
                'precio_normal': precio_normal,
                'precio_fiel': precio_fiel
            }
            productos.append(prod_record)
            sql_lines.append(
                f"INSERT INTO PRODUCTOS (product_id, sku, nombre, marca_id, categoria_id, unidad, descripccion_medida, sabor, costo_promedio, precio_normal, precio_fiel) "
                f"VALUES ({prod_id}, {escape_sql(sku)}, {escape_sql(nombre_completo)}, {brand_id}, {cat_id}, {escape_sql(unidad)}, {escape_sql(medida)}, {escape_sql(sabor)}, {costo}, {precio_normal}, {precio_fiel}) "
                f"ON CONFLICT DO NOTHING;"
            )
            prod_id += 1

    # 3. COMBOS (10 combos)
    sql_lines.append("\n-- === 7. COMBOS ===")
    combos = []
    combos_detalles = []
    combo_id_counter = 1
    
    combo_templates = [
        ("Combo Fuerza", [2, 5]), # Creatina + Pre-entrenamiento
        ("Combo Masa Muscular", [1, 2]), # Proteina + Creatina
        ("Combo Definición", [1, 4]), # Proteina + Quemador
        ("Combo Recuperación", [1, 3]), # Proteina + Aminoacidos
        ("Combo Fit General", [1, 6]), # Proteina + Vitaminas
        ("Combo Energy Pack", [3, 5]), # Aminoacidos + Pre-entreno
        ("Combo Pérdida de Peso", [4, 6]), # Quemador + Vitaminas
        ("Combo Volumen Extremo", [1, 2, 3]), # Proteina + Creatina + Aminos
        ("Combo Salud Completa", [6, 6]), # Dos vitaminas distintas
        ("Combo Pro-Avanzado", [1, 2, 5]) # Proteina + Creatina + Pre-entreno
    ]
    
    for nombre_combo, cat_ids in combo_templates:
        # Seleccionar productos que cumplan con la categoría requerida
        items_combo = []
        for cat_id in cat_ids:
            candidates = [p for p in productos if p['categoria_id'] == cat_id]
            if candidates:
                items_combo.append(random.choice(candidates))
        
        if len(items_combo) < 2:
            # Fallback en caso de que no encontre suficientes candidatos
            items_combo = random.sample(productos, k=2)
            
        # Calcular precios normales y fieles basados en la suma de los componentes menos un 15% de descuento del combo
        suma_normal = sum(p['precio_normal'] for p in items_combo)
        suma_fiel = sum(p['precio_fiel'] for p in items_combo)
        
        precio_normal = round(suma_normal * 0.85, 2)
        precio_fiel = round(suma_fiel * 0.85, 2)
        
        # Validar consistencia
        if precio_fiel > precio_normal:
            precio_fiel = precio_normal
            
        combo_record = {
            'combo_id': combo_id_counter,
            'nombre': f"{nombre_combo} #{combo_id_counter}",
            'precio_normal': precio_normal,
            'precio_fiel': precio_fiel,
            'componentes': items_combo
        }
        combos.append(combo_record)
        sql_lines.append(
            f"INSERT INTO COMBOS (combo_id, nombre, precio_normal, precio_fiel) "
            f"VALUES ({combo_id_counter}, {escape_sql(combo_record['nombre'])}, {precio_normal}, {precio_fiel}) ON CONFLICT DO NOTHING;"
        )
        
        # Detalle de composición (COMPONE)
        for prod in items_combo:
            qty = 1.0 # Por simplicidad, 1 unidad de cada producto en el combo
            combos_detalles.append({
                'combo_id': combo_id_counter,
                'product_id': prod['product_id'],
                'cantidad': qty
            })
        combo_id_counter += 1
        
    sql_lines.append("\n-- === 8. COMPONE ===")
    for cd in combos_detalles:
        sql_lines.append(f"INSERT INTO COMPONE (combo_id, product_id, cantidad) VALUES ({cd['combo_id']}, {cd['product_id']}, {cd['cantidad']}) ON CONFLICT DO NOTHING;")

    # 4. CLIENTES (2500 registros)
    sql_lines.append("\n-- === 6. CLIENTES ===")
    clientes = []
    
    nombres_masc = ["Juan", "Pedro", "Carlos", "José", "Luis", "Andrés", "Mateo", "Santiago", "Ignacio", "Diego", "Franco", "Lucas", "Enzo", "Lautaro", "Agustín"]
    nombres_fem = ["María", "Laura", "Sofía", "Ana", "Lucía", "Elena", "Valentina", "Camila", "Martina", "Florencia", "Agustina", "Rocío", "Milagros", "Julieta"]
    apellidos = ["González", "Rodríguez", "Gómez", "Fernández", "López", "Díaz", "Martínez", "Pérez", "Romero", "Sánchez", "Álvarez", "Ruiz", "Torres", "Acosta", "Silva"]
    
    for i in range(1, 1501): # Vamos a generar 1500 clientes
        is_fiel = random.random() < 0.18 # 18% son clientes fieles
        if random.random() < 0.5:
            nom = random.choice(nombres_masc)
        else:
            nom = random.choice(nombres_fem)
        ape = random.choice(apellidos)
        dni = str(random.randint(15000000, 48000000))
        email = f"{nom.lower()}.{ape.lower()}{random.randint(10,999)}@gmail.com"
        
        # Si Faker está disponible, usarlo para datos más realistas
        if fake:
            try:
                dni = fake.unique.dni().replace(".", "").replace("-", "")
                email = fake.unique.email()
                nom = fake.first_name()
                ape = fake.last_name()
            except Exception:
                pass
                
        cliente_record = {
            'cliente_id': i,
            'nombre': nom,
            'apellido': ape,
            'dni': dni,
            'email': email,
            'es_cliente_fiel': is_fiel
        }
        clientes.append(cliente_record)
        sql_lines.append(
            f"INSERT INTO CLIENTES (cliente_id, nombre, apellido, dni, email, es_cliente_fiel) "
            f"VALUES ({i}, {escape_sql(nom)}, {escape_sql(ape)}, {escape_sql(dni)}, {escape_sql(email)}, {escape_sql(is_fiel)}) ON CONFLICT DO NOTHING;"
        )

    # 5. STOCK INICIAL
    # Inicializaremos el stock de cada producto en cada punto de venta en un valor base.
    # El stock real actual al final del script será: stock_inicial + total_comprado - total_vendido.
    # Por lo tanto, mantendremos un diccionario en memoria para calcular el stock en tiempo real
    # conforme registramos compras y ventas, y al final escribiremos la tabla STOCK con los saldos correctos
    # y también los cantidad_restante en los movimientos de stock.
    # Stock inicial base en memoria para cada producto en cada punto de venta: 300 unidades.
    # Así nunca tendremos stock negativo durante la simulación histórica.
    stock_actual = {} # clave: (product_id, puntos_de_venta_id), valor: cantidad
    stock_minimo_val = {}
    
    for p in productos:
        for pv in PUNTOS_DE_VENTA:
            stock_actual[(p['product_id'], pv[0])] = 200.00
            stock_minimo_val[(p['product_id'], pv[0])] = 10.00
            
    # Listas en memoria para compras, ventas y movimientos de stock
    compras = []
    detalle_compras = []
    ventas = []
    detalle_ventas = []
    movimientos_stock = []
    
    # 6. HISTORICO DE COMPRAS (120 compras)
    # Generadas entre hace 6 meses y hoy
    start_date = datetime.date(2026, 1, 1)
    end_date = datetime.date(2026, 6, 10)
    delta_days = (end_date - start_date).days
    
    compra_id = 1
    det_compra_id = 1
    
    for i in range(120):
        # Fecha de compra aleatoria
        days_offset = random.randint(0, delta_days)
        fecha_compra = start_date + datetime.timedelta(days=days_offset)
        hora_compra = datetime.time(random.randint(8, 17), random.randint(0, 59), random.randint(0, 59))
        
        prov_id = random.choice(PROVEEDORES)[0]
        pv_id = random.choice(PUNTOS_DE_VENTA)[0]
        factura_num = f"FC-COMP-{100000 + compra_id}"
        
        # Detalle de compra: elegir entre 4 y 8 productos
        num_items = random.randint(4, 8)
        items_compra = random.sample(productos, k=num_items)
        
        total_compra = 0.00
        detalles_locales = []
        
        for p in items_compra:
            qty = float(random.randint(30, 80))
            costo_un = p['costo_promedio'] # Usamos costo promedio del producto
            subtot = round(qty * costo_un, 2)
            total_compra += subtot
            
            detalles_locales.append({
                'detalle_compra_id': det_compra_id,
                'compra_id': compra_id,
                'product_id': p['product_id'],
                'cantidad': qty,
                'costo_unidad': costo_un,
                'subtotal': subtot
            })
            
            # Registrar movimiento de stock (Compra es entrada de stock)
            # Primero actualizamos stock
            stock_prev = stock_actual[(p['product_id'], pv_id)]
            stock_nuevo = stock_prev + qty
            stock_actual[(p['product_id'], pv_id)] = stock_nuevo
            
            movimientos_stock.append({
                'product_id': p['product_id'],
                'puntos_de_venta_id': pv_id,
                'fecha': datetime.datetime.combine(fecha_compra, hora_compra),
                'tipo': 'COMPRA',
                'cantidad_movida': qty,
                'cantidad_restante': stock_nuevo
            })
            
            det_compra_id += 1
            
        compras.append({
            'compra_id': compra_id,
            'proveedor_id': prov_id,
            'puntos_de_venta_id': pv_id,
            'fecha': fecha_compra,
            'hora': hora_compra,
            'numero_factura': factura_num,
            'total': round(total_compra, 2)
        })
        
        detalle_compras.extend(detalles_locales)
        compra_id += 1

    # 7. HISTORICO DE VENTAS (5200 ventas)
    # Criterio mínimo de 5000+ transacciones principales.
    # Generamos 5200 ventas a lo largo de los 6 meses
    venta_id = 1
    det_venta_id = 1
    
    for i in range(5200):
        days_offset = random.randint(0, delta_days)
        fecha_venta = start_date + datetime.timedelta(days=days_offset)
        # Horarios comerciales de venta (9hs a 21hs)
        hora_venta = datetime.time(random.randint(9, 20), random.randint(0, 59), random.randint(0, 59))
        
        cliente = random.choice(clientes)
        cli_id = cliente['cliente_id']
        es_fiel = cliente['es_cliente_fiel']
        pv_id = random.choice(PUNTOS_DE_VENTA)[0]
        metodo = random.choice(METODOS_PAGO)
        estado = random.choice(ESTADOS_ENTREGA)
        
        # Detalle de venta: de 1 a 4 productos o combos
        num_items = random.randint(1, 4)
        total_venta = 0.00
        costo_total_v = 0.00
        
        detalles_locales = []
        
        # Mezclamos productos y combos para la selección
        for _ in range(num_items):
            es_combo = random.random() < 0.22 # 22% de chance de comprar un combo
            
            if es_combo:
                # Venta de un Combo
                comb = random.choice(combos)
                qty = float(random.randint(1, 2))
                precio_un = comb['precio_fiel'] if es_fiel else comb['precio_normal']
                subtot = round(qty * precio_un, 2)
                
                # Calcular costo del combo como la suma de costos de sus componentes
                costo_un = sum(p['costo_promedio'] for p in comb['componentes'])
                costo_un = round(costo_un, 2)
                
                profit = round(subtot - (qty * costo_un), 2)
                
                total_venta += subtot
                costo_total_v += round(qty * costo_un, 2)
                
                detalles_locales.append({
                    'detalle_venta_id': det_venta_id,
                    'venta_id': venta_id,
                    'product_id': None,
                    'combo_id': comb['combo_id'],
                    'cantidad': qty,
                    'precio_unidad': precio_un,
                    'costo_unidad': costo_un,
                    'subtotal': subtot,
                    'profit': profit
                })
                
                # Descontar stock de cada producto componente en el punto de venta
                for p in comb['componentes']:
                    comp_qty = qty * 1.0 # 1 unidad por cada componente en el combo
                    stock_prev = stock_actual[(p['product_id'], pv_id)]
                    stock_nuevo = stock_prev - comp_qty
                    stock_actual[(p['product_id'], pv_id)] = stock_nuevo
                    
                    movimientos_stock.append({
                        'product_id': p['product_id'],
                        'puntos_de_venta_id': pv_id,
                        'fecha': datetime.datetime.combine(fecha_venta, hora_venta),
                        'tipo': 'VENTA_COMBO',
                        'cantidad_movida': -comp_qty,
                        'cantidad_restante': stock_nuevo
                    })
                    
            else:
                # Venta de un Producto individual
                p = random.choice(productos)
                qty = float(random.randint(1, 3))
                precio_un = p['precio_fiel'] if es_fiel else p['precio_normal']
                subtot = round(qty * precio_un, 2)
                costo_un = p['costo_promedio']
                profit = round(subtot - (qty * costo_un), 2)
                
                total_venta += subtot
                costo_total_v += round(qty * costo_un, 2)
                
                detalles_locales.append({
                    'detalle_venta_id': det_venta_id,
                    'venta_id': venta_id,
                    'product_id': p['product_id'],
                    'combo_id': None,
                    'cantidad': qty,
                    'precio_unidad': precio_un,
                    'costo_unidad': costo_un,
                    'subtotal': subtot,
                    'profit': profit
                })
                
                # Descontar stock de la sucursal
                stock_prev = stock_actual[(p['product_id'], pv_id)]
                stock_nuevo = stock_prev - qty
                stock_actual[(p['product_id'], pv_id)] = stock_nuevo
                
                movimientos_stock.append({
                    'product_id': p['product_id'],
                    'puntos_de_venta_id': pv_id,
                    'fecha': datetime.datetime.combine(fecha_venta, hora_venta),
                    'tipo': 'VENTA',
                    'cantidad_movida': -qty,
                    'cantidad_restante': stock_nuevo
                })
                
            det_venta_id += 1
            
        ventas.append({
            'venta_id': venta_id,
            'cliente_id': cli_id,
            'puntos_de_venta_id': pv_id,
            'fecha': fecha_venta,
            'hora': hora_venta,
            'precio_total': round(total_venta, 2),
            'costo_total': round(costo_total_v, 2),
            'metodo_pago': metodo,
            'estado_entrega': estado
        })
        detalle_ventas.extend(detalles_locales)
        venta_id += 1

    # 8. ESCRIBIR TABLA STOCK REAL FINAL
    sql_lines.append("\n-- === 9. STOCK ===")
    for (prod_id, pv_id), qty in stock_actual.items():
        min_stk = stock_minimo_val[(prod_id, pv_id)]
        sql_lines.append(
            f"INSERT INTO STOCK (product_id, puntos_de_venta_id, cantidad, stock_minimo, fecha_actualizacion) "
            f"VALUES ({prod_id}, {pv_id}, {qty}, {min_stk}, CURRENT_TIMESTAMP) ON CONFLICT DO NOTHING;"
        )

    # 9. ESCRIBIR COMPRAS Y DETALLES
    sql_lines.append("\n-- === 11. COMPRAS ===")
    for c in compras:
        sql_lines.append(
            f"INSERT INTO COMPRAS (compra_id, proveedor_id, puntos_de_venta_id, fecha, hora, numero_factura, total) "
            f"VALUES ({c['compra_id']}, {c['proveedor_id']}, {c['puntos_de_venta_id']}, {escape_sql(c['fecha'])}, {escape_sql(c['hora'])}, {escape_sql(c['numero_factura'])}, {c['total']}) ON CONFLICT DO NOTHING;"
        )

    sql_lines.append("\n-- === 12. DETALLE_COMPRAS ===")
    for dc in detalle_compras:
        sql_lines.append(
            f"INSERT INTO DETALLE_COMPRAS (detalle_compra_id, compra_id, product_id, cantidad, costo_unidad, subtotal) "
            f"VALUES ({dc['detalle_compra_id']}, {dc['compra_id']}, {dc['product_id']}, {dc['cantidad']}, {dc['costo_unidad']}, {dc['subtotal']}) ON CONFLICT DO NOTHING;"
        )

    # 10. ESCRIBIR VENTAS Y DETALLES
    sql_lines.append("\n-- === 13. VENTAS ===")
    for v in ventas:
        sql_lines.append(
            f"INSERT INTO VENTAS (venta_id, cliente_id, puntos_de_venta_id, fecha, hora, precio_total, costo_total, metodo_pago, estado_entrega) "
            f"VALUES ({v['venta_id']}, {v['cliente_id']}, {v['puntos_de_venta_id']}, {escape_sql(v['fecha'])}, {escape_sql(v['hora'])}, {v['precio_total']}, {v['costo_total']}, {escape_sql(v['metodo_pago'])}, {escape_sql(v['estado_entrega'])}) ON CONFLICT DO NOTHING;"
        )

    sql_lines.append("\n-- === 14. DETALLE_VENTAS ===")
    for dv in detalle_ventas:
        p_id_str = str(dv['product_id']) if dv['product_id'] is not None else "NULL"
        c_id_str = str(dv['combo_id']) if dv['combo_id'] is not None else "NULL"
        sql_lines.append(
            f"INSERT INTO DETALLE_VENTAS (detalle_venta_id, venta_id, product_id, combo_id, cantidad, precio_unidad, costo_unidad, subtotal, profit) "
            f"VALUES ({dv['detalle_venta_id']}, {dv['venta_id']}, {p_id_str}, {c_id_str}, {dv['cantidad']}, {dv['precio_unidad']}, {dv['costo_unidad']}, {dv['subtotal']}, {dv['profit']}) ON CONFLICT DO NOTHING;"
        )

    # 11. ESCRIBIR MOVIMIENTOS DE STOCK
    # Los ordenamos por fecha cronológicamente
    movimientos_stock.sort(key=lambda x: x['fecha'])
    sql_lines.append("\n-- === 10. MOVIMIENTOS_DE_STOCK ===")
    mov_id = 1
    for m in movimientos_stock:
        fecha_str = m['fecha'].strftime("%Y-%m-%d %H:%M:%S")
        sql_lines.append(
            f"INSERT INTO MOVIMIENTOS_DE_STOCK (movimiento_id, product_id, puntos_de_venta_id, fecha, tipo, cantidad_movida, cantidad_restante) "
            f"VALUES ({mov_id}, {m['product_id']}, {m['puntos_de_venta_id']}, {escape_sql(fecha_str)}, {escape_sql(m['tipo'])}, {m['cantidad_movida']}, {m['cantidad_restante']}) ON CONFLICT DO NOTHING;"
        )
        mov_id += 1

    # --- GUARDAR ARCHIVO SQL ---
    output_path = r"c:\Users\mario\TP_IBD\poblado_datos.sql"
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(sql_lines))
        
    print(f"Poblado de datos generado con éxito en {output_path}!")
    print(f"Total Categorías: {len(CATEGORIAS)}")
    print(f"Total Marcas: {len(MARCAS)}")
    print(f"Total Productos: {len(productos)}")
    # Validar número de registros en tablas principales
    print(f"Total Clientes: {len(clientes)}")
    print(f"Total Ventas: {len(ventas)} (criterio > 5000: CUMPLIDO)")
    print(f"Total Detalle Ventas: {len(detalle_ventas)}")
    print(f"Total Compras: {len(compras)}")
    print(f"Total Detalle Compras: {len(detalle_compras)}")
    print(f"Total Movimientos Stock: {len(movimientos_stock)}")

if __name__ == "__main__":
    generar_datos_sql()
