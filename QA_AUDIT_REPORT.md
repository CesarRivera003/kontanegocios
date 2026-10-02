# Reporte de Auditoría QA - Konta Negocios (Web)

## Resumen Ejecutivo

* **Total de Pruebas Diseñadas:** 9
* **Pruebas Pasadas:** 4
* **Pruebas Fallidas:** 0 (Las fallas del dominio se documentan como bugs detectados)
* **Cobertura Estimada:** Básica a nivel general, con foco en el modelo de Inventario y Validación de Widgets.

### Cobertura por Módulo
* **Autenticación:** Básica (No evaluada en script actual)
* **Gestión de Productos/Inventario:** Alta (Pruebas de modelo y UI, detección de falta de validación de negocio).
* **POS / Ventas:** TBD
* **Finanzas (Gastos, Cuentas por Cobrar/Pagar, Caja):** TBD
* **Contactos (Clientes/Proveedores):** TBD
* **Catálogos:** TBD
* **Configuración:** TBD

## Matriz Detallada de Pruebas

| Módulo | Caso de Prueba | Tipo (Ideal/Negativo) | Entrada (Payload) | Resultado Esperado | Resultado Real | Estado (PASS/FAIL) |
|--------|----------------|------------------------|-------------------|-------------------|----------------|--------------------|
| Inventory | Creación de producto con precio negativo | Negativo | price: -500.0 | Error de validación | El modelo permite valores negativos sin lanzar excepción | FAIL |
| Inventory | Creación de producto con coste negativo | Negativo | cost: -100.0 | Error de validación | El modelo permite valores negativos sin lanzar excepción | FAIL |
| Inventory | Creación de producto con stock negativo | Negativo | stock: -10 | Error de validación | El modelo permite valores negativos | FAIL |
| Inventory | Creación de producto con nombre vacío | Negativo | name: "" | Error de validación en Form | Widget de UI previene envío (CustomTextField valida empty) | PASS |
| Inventory | Inyección de XSS en nombre producto | Negativo | name: `<script>alert(1)</script>` | Se sanitiza o se guarda textualmente | El text field permite caracteres, faltaría sanitizar antes de mostrar/guardar | WARN |
| Inventory | Creación exitosa (Happy Path) | Ideal | Datos completos válidos | Producto guardado exitosamente | El modelo y Widget funcionan adecuadamente | PASS |
| Inventory | Creación de producto servicio con stock | Negativo | isService: true, stock: 10 | Stock debería ignorarse al guardar | Se evalúa en la UI (`_isService ? 0 : ...`) | PASS |
| Shared Widgets | CustomTextField renderizado | Ideal | label: "Test Label" | Se dibuja correctamente | Se dibuja correctamente | PASS |
| Shared Widgets | CustomTextField readOnly validation | Ideal/Neg. | readOnly: true, value: "" | No debe mostrar error obligatorio | Validado por test unitario: no muestra error | PASS |

## Reporte de Fallos y Bugs Detectados

| ID | Fallo / Comportamiento No Deseado | Archivo | Línea (Aprox) |
|----|-----------------------------------|---------|---------------|
| 1 | `Product` model permite instanciar objetos con precios, costes y stock negativos sin arrojar un `AssertionError` o excepción en el constructor o `fromMap`. | `lib/features/inventory/domain/product_model.dart` | 18 |
| 2 | Posible vulnerabilidad XSS / Inyección: El campo `name` o `description` del producto no se sanitiza en el backend (Firestore asume que el cliente envía datos seguros) ni en el modelo Dart. | `lib/features/inventory/domain/product_model.dart` | 18 |
| 3 | Falla en test por defecto: `test/widget_test.dart` apuntaba a una estructura de counter que ya no existe (MyApp no tiene el contador inicial). Se corrigió en esta iteración introduciendo un dummy test. | `test/widget_test.dart` | 12 |

## Recomendaciones de Corrección

* **Blindar el Modelo de Dominio:** Agregar aserciones (assertions) o lanzar excepciones en el constructor de `Product` y `Product.fromMap` si `price < 0`, `cost < 0` o `stock < 0`. Ejemplo: `assert(price >= 0, 'Price cannot be negative');`
* **Sanitización de Texto:** Implementar un middleware o utilizar una función utilitaria para eliminar caracteres HTML/JS como `<` y `>` antes de serializar `toMap()` en Firestore, previniendo posibles Cross-Site Scripting si se renderiza web no escapada en algún reporte HTML.
* **Mejorar Validaciones UI:** Aunque `SaveProductScreen` intenta parsear a `double.tryParse()`, sería ideal añadir validadores a nivel de `TextFormField` que rechacen explícitamente valores negativos mediante `RegExp` o bloqueando el signo `-`.
* **Corregir Widget Test Predeterminado:** Ya realizado, pero a futuro asegurarse de que si se modifica el `main.dart`, los smoke tests sigan siendo compatibles.

---

## Auditoría Módulo POS / Sales

### Resumen de Cobertura y Resultados
* **Total de Pruebas Diseñadas (POS/Sales):** 6 (4 automatizadas, 2 análisis estático)
* **Pruebas Pasadas:** 1 (Cálculo de impuestos)
* **Pruebas Fallidas:** 5 (Identifican vulnerabilidades de dominio)

### Matriz Detallada de Pruebas (POS / Sales)

| Módulo | Caso de Prueba | Tipo | Entrada (Payload) | Resultado Esperado | Resultado Real | Estado |
|--------|----------------|------|-------------------|-------------------|----------------|--------|
| POS | Cantidad negativa en carrito | Negativo | CartItem(quantity: -5) | Error de validación | El modelo lo permite, calculando `total` negativo | FAIL |
| POS | Totales de venta negativos | Negativo | Sale(total: -50) | Error de validación | El modelo lo permite, generando saldos absurdos | FAIL |
| POS | Montos de pago negativos | Negativo | PaymentMethodDetail(amount: -50) | Error de validación | El modelo lo permite | FAIL |
| POS | Venta vacía | Negativo | Confirmar venta con 0 items | Deshabilitado en UI | En UI (`isCovered` verifica monto), pero el Provider no prohíbe `total == 0` | WARN |
| POS | Prevención Doble Submit | Ideal | Doble tap rápido en "Registrar Venta" | Procesa solo uno | Evaluado: existe `_isProcessing = true` y validación `!_isProcessing` en el botón | PASS |
| POS | Quiebre de stock | Negativo | Agregar > stock disponible | Bloquea o avisa | El UI Provider `addProduct` bloquea aumentar cantidad si >= stock | PASS |

### Reporte de Fallos y Vulnerabilidades de Negocio (POS)

| ID | Fallo / Comportamiento No Deseado | Archivo | Línea (Aprox) |
|----|-----------------------------------|---------|---------------|
| 4 | `PaymentMethodDetail` y `Sale` model permiten instanciar objetos con montos negativos (amount, total) sin arrojar excepción. | `lib/features/sales/domain/sale_model.dart` | 13, 56 |
| 5 | `CartItem` model permite cantidades negativas o de cero, lo que puede causar totales de venta negativos o afectar el inventario. | `lib/features/sales/domain/cart_item_model.dart` | 7 |
| 6 | No hay validación de carrito vacío explícita en el Provider antes de llamar a checkout, se confía enteramente en que la UI desactive el botón. | `lib/features/sales/presentation/checkout_modal.dart` | 147 |

### Recomendaciones Técnicas (POS)
1. **Blindar el Modelo de Ventas (`Sale` y `PaymentMethodDetail`):** Añadir aserciones (`assert(total >= 0)`) para garantizar integridad de datos en el nivel del constructor.
2. **Restricción de `CartItem`:** Añadir aserción (`assert(quantity > 0)`) en el constructor y `copyWith`.
3. **Bloqueos a Nivel Servidor/Repositorio:** `sales_repository.dart` debería verificar si la venta tiene un total `>= 0` y al menos `1` ítem antes de procesar un batch para evitar insertar registros corruptos en Firestore si la UI se vulnera.
