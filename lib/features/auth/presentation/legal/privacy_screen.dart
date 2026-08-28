import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Política de Privacidad"),
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
              "Política de Tratamiento de Datos",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text(
              _privacyText,
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

const String _privacyText = """
POLÍTICA DE TRATAMIENTO Y PROTECCIÓN DE DATOS PERSONALES
Última actualización: Agosto 2026

1. INFORMACIÓN GENERAL Y RESPONSABLE DEL TRATAMIENTO
Konta Negocios es una plataforma de software desarrollada, operada y de propiedad exclusiva de César Rivera Sanabria (en adelante, "el Propietario" o "el Desarrollador"). 
En estricto cumplimiento de la Ley Estatutaria 1581 de 2012, el Decreto Reglamentario 1377 de 2013 y demás normatividad aplicable en la República de Colombia (Régimen General de Protección de Datos Personales), esta política describe el tratamiento (recolección, almacenamiento, uso y supresión) de la información.

2. ROLES EN EL TRATAMIENTO DE DATOS
A. Como Responsable: El Propietario actúa como "Responsable del Tratamiento" respecto a los datos de los usuarios (comerciantes o administradores) que se registran en Konta Negocios (ej. nombre, correo, NIT, teléfono).
B. Como Encargado: Respecto a los datos que el usuario ingresa en la plataforma sobre sus propios clientes, empleados y proveedores, el usuario actúa como Responsable y el Propietario actúa únicamente como "Encargado del Tratamiento", proveyendo la infraestructura de almacenamiento.

3. USO DE LA INFORMACIÓN
La información recolectada se utiliza estrictamente para:
- Proveer, mantener y optimizar el servicio de gestión y punto de venta.
- Procesar suscripciones y pagos.
- Facilitar la interoperabilidad con servicios de terceros (ej. facturación electrónica DIAN).
- Enviar notificaciones críticas del sistema, actualizaciones y soporte técnico.

4. ALMACENAMIENTO, TRANSFERENCIA INTERNACIONAL Y SEGURIDAD
Los datos se almacenan en servidores seguros en la nube gestionados por proveedores de primer nivel (ej. Google Firebase). Al aceptar esta política, usted autoriza expresamente la transmisión y/o transferencia internacional de sus datos a servidores ubicados fuera de Colombia, los cuales cuentan con estándares internacionales de seguridad. Aunque se aplican protocolos de cifrado estándar de la industria, no se garantiza la invulnerabilidad absoluta de la red de Internet.

5. COMPARTIR INFORMACIÓN CON TERCEROS
El Propietario no comercializa, alquila ni transfiere a título oneroso los datos personales a terceros. La información solo se comparte con:
- Pasarelas de pago autorizadas para procesar suscripciones.
- Proveedores tecnológicos avalados por la DIAN (cuando el usuario active el módulo de facturación electrónica).
- Autoridades competentes cuando medie una orden judicial.

6. DERECHOS DEL TITULAR (HABEAS DATA)
Conforme al Artículo 8 de la Ley 1581 de 2012, usted tiene derecho a conocer, actualizar y rectificar sus datos personales; solicitar prueba de la autorización otorgada; ser informado sobre el uso de sus datos; revocar la autorización y/o solicitar la supresión del dato (Derecho al olvido).

7. CAMBIOS Y CANALES DE CONTACTO
Nos reservamos el derecho de modificar esta política. Los cambios entrarán en vigor tras su publicación en la App. Para ejercer sus derechos, el usuario puede canalizar sus requerimientos a través del módulo de soporte o contacto oficial de Konta Negocios.
""";