import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Términos y Condiciones"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              "Términos y Condiciones de Uso",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text(
              _termsText, 
              style: TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
              textAlign: TextAlign.justify,
            ),
            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

const String _termsText = """
TÉRMINOS Y CONDICIONES DE USO
Última actualización: Agosto 2026

1. ACEPTACIÓN Y NATURALEZA DEL SERVICIO
Al descargar, instalar, registrarse o utilizar la plataforma Konta Negocios (en adelante "el Software" o "la App"), usted ("el Usuario") acepta estar legalmente vinculado por estos Términos y Condiciones, los cuales constituyen un contrato vinculante al amparo de la Ley 1480 de 2011 (Estatuto del Consumidor de Colombia). 
Konta Negocios es una obra de software desarrollada, operada y de propiedad exclusiva de César Rivera Sanabria (en adelante "el Desarrollador"). 

2. LICENCIA DE USO Y PROPIEDAD INTELECTUAL
El Desarrollador le otorga una licencia de uso personal, revocable, no exclusiva e intransferible para utilizar el Software. Todos los códigos fuente, interfaces, marcas, logos y algoritmos son propiedad exclusiva de César Rivera Sanabria y están protegidos por las leyes de Propiedad Intelectual nacionales y tratados internacionales. Está estrictamente prohibida su descompilación, ingeniería inversa, copia o modificación.

3. CUENTAS, SEGURIDAD Y RESPONSABILIDAD DE ACCESO
El Usuario es el único y absoluto responsable de mantener la confidencialidad de sus credenciales (contraseñas, PIN de autorización) y de cualquier actividad u operación financiera que ocurra en su cuenta, incluyendo las acciones de los empleados o sub-usuarios que autorice. El Desarrollador no asumirá responsabilidad civil, penal ni administrativa por fraudes internos, suplantación o mal manejo del sistema por parte del personal del Usuario.

4. SUSCRIPCIONES Y PASARELAS DE PAGO
El acceso a funciones Premium (planes Pro o Empresariales) requiere el pago de una suscripción. Los pagos son procesados a través de pasarelas de pago de terceros certificadas y vigiladas. El Desarrollador no almacena datos de tarjetas de crédito o débito. Las políticas de contracargos, reembolsos y fallos en la transacción se regirán por los términos de la pasarela de pago utilizada. 

5. FACTURACIÓN ELECTRÓNICA Y RESPONSABILIDAD TRIBUTARIA
El Software actúa únicamente como una interfaz tecnológica que facilita la transmisión de datos hacia la Dirección de Impuestos y Aduanas Nacionales (DIAN) a través de un Proveedor Tecnológico externo autorizado.
- El Usuario es el único responsable legal, contable y tributario de la exactitud de los valores, impuestos, identificaciones y conceptos emitidos en sus comprobantes.
- El Desarrollador queda eximido de toda responsabilidad frente a multas, requerimientos o sanciones impuestas por la DIAN.
- El Desarrollador no será responsable por intermitencias, caídas de la plataforma del Proveedor Tecnológico externo, ni rechazos en la validación previa de los documentos.

6. LIMITACIÓN DE RESPONSABILIDAD EXTREMA
El Software se proporciona "Tal Cual" (As Is) y "Según Disponibilidad". En la máxima medida permitida por la ley aplicable, César Rivera Sanabria declina cualquier garantía implícita o explícita de idoneidad para un fin particular. 
Bajo ninguna circunstancia el Desarrollador será responsable frente al Usuario o terceros por daños directos, indirectos, lucro cesante, pérdida de datos, pérdida de ingresos o cierres de negocio derivados de:
A. Errores, omisiones o inexactitudes en cálculos financieros, de inventario o reportes (el Usuario tiene la obligación de conciliar y verificar su contabilidad).
B. Caídas de los servidores, pérdida de conexión de servicios en la nube o fuerza mayor.

7. INDEMNIDAD
El Usuario acuerda defender, indemnizar y mantener indemne a César Rivera Sanabria frente a cualquier reclamación, demanda, demanda por daños, costos o gastos (incluyendo honorarios de abogados) que surjan de la violación de estos términos o del mal uso de la aplicación por parte del Usuario frente a sus propios clientes o proveedores.

8. TERMINACIÓN
El Desarrollador se reserva el derecho de suspender o eliminar el acceso al Software, sin previo aviso ni derecho a indemnización, ante el incumplimiento de estos términos, fraude, o impago reiterado de las suscripciones.

9. LEY APLICABLE Y JURISDICCIÓN COMPETENTE
Estos Términos y Condiciones se regirán e interpretarán íntegramente de acuerdo con las leyes de la República de Colombia. Para dirimir cualquier conflicto, controversia o reclamación derivada del uso del Software, las partes se someten irrevocablemente y de forma exclusiva a la jurisdicción y competencia de los jueces de la República ubicados en la ciudad de Ibagué, departamento del Tolima, renunciando a cualquier otro fuero que pudiera corresponderles por razón de sus domicilios presentes o futuros.
""";