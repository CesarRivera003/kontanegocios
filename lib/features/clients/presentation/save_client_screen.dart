import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/client_model.dart';
import 'client_providers.dart';
import '../../../core/utils/colombia_cities.dart';

// Importa el repositorio donde tienes companyProfileProvider
import '../../settings/data/settings_repository.dart'; 

class SaveClientScreen extends ConsumerStatefulWidget {
  final Client? clientToEdit;
  const SaveClientScreen({super.key, this.clientToEdit});

  @override
  ConsumerState<SaveClientScreen> createState() => _SaveClientScreenState();
}

class _SaveClientScreenState extends ConsumerState<SaveClientScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Obligatorios
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;

  // Opcionales
  late TextEditingController _idNumberCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _cityCtrl;
  late TextEditingController _secondaryCtrl;
  
  // DIAN
  late TextEditingController _daneCodeCtrl;
  
  String _idType = 'CC';
  String _personType = '2'; // 2 = Natural, 1 = Jurídica (Plemsi)
  String _taxRegime = '49'; // 49 = No Responsable, 48 = Responsable (Plemsi)
  
  bool _showOptional = false; 
  bool _isFeEnabled = false; // Controla si activó Facturación Electrónica
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final c = widget.clientToEdit;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _phoneCtrl = TextEditingController(text: c?.phone ?? '');
    _idNumberCtrl = TextEditingController(text: c?.idNumber ?? '');
    _emailCtrl = TextEditingController(text: c?.email ?? '');
    _addressCtrl = TextEditingController(text: c?.address ?? '');
    _cityCtrl = TextEditingController(text: c?.city ?? '');
    _secondaryCtrl = TextEditingController(text: c?.secondaryContact ?? '');
    _idType = c?.idType ?? 'CC';
    
    // Nuevos campos
    _daneCodeCtrl = TextEditingController(text: c?.daneCode ?? '');
    _isFeEnabled = c?.isFeEnabled ?? false;
    _personType = c?.personType ?? '2';
    _taxRegime = c?.taxRegime ?? '49';

    if (c != null && (c.email.isNotEmpty || c.address.isNotEmpty || c.idNumber.isNotEmpty)) {
      _showOptional = true;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Validación manual si FE está activa
    if (_isFeEnabled) {
      if (_idNumberCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty || _addressCtrl.text.trim().isEmpty || _daneCodeCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Para Facturación Electrónica el NIT, Correo, Dirección y Código DANE son obligatorios.'), backgroundColor: Colors.orange)
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final client = Client(
        id: widget.clientToEdit?.id ?? '',
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        idType: _idType,
        idNumber: _idNumberCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        secondaryContact: _secondaryCtrl.text.trim(),
        
        // Datos FE
        isFeEnabled: _isFeEnabled,
        personType: _personType,
        taxRegime: _taxRegime,
        daneCode: _daneCodeCtrl.text.trim(),
      );

      await ref.read(clientRepositoryProvider).saveClient(client)
        .timeout(const Duration(seconds: 2), onTimeout: () {});

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cliente guardado'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Escuchamos el perfil de la empresa para saber qué plan tiene
    final companyProfile = ref.watch(companyProfileProvider).value;
    final isEmpresarial = companyProfile?.subscriptionStatus == 'empresarial';

    return Scaffold(
      appBar: AppBar(title: Text(widget.clientToEdit != null ? 'Editar Cliente' : 'Nuevo Cliente')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Datos Obligatorios', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 15),
              
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre o Razón Social', prefixIcon: Icon(Icons.person), border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono / Celular', prefixIcon: Icon(Icons.phone), border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Requerido' : null,
              ),

              const SizedBox(height: 25),

              // SECCIÓN DESPLEGABLE OPCIONAL
              ListTile(
                title: const Text('Información Adicional (Opcional)', style: TextStyle(fontWeight: FontWeight.bold)),
                trailing: Icon(_showOptional ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                onTap: () => setState(() => _showOptional = !_showOptional),
                contentPadding: EdgeInsets.zero,
              ),
              
              if (_showOptional) ...[
                Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: DropdownButtonFormField<String>(
                        value: _idType,
                        decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15)),
                        items: ['CC', 'NIT', 'TI', 'CE', 'PAS'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                        onChanged: (v) => setState(() => _idType = v!),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _idNumberCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Número Identificación', 
                          border: const OutlineInputBorder(),
                          // Si activó FE, se lo marcamos visualmente como obligatorio
                          suffixIcon: _isFeEnabled ? const Icon(Icons.star, color: Colors.red, size: 12) : null,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Correo Electrónico', 
                    prefixIcon: const Icon(Icons.email), 
                    border: const OutlineInputBorder(),
                    suffixIcon: _isFeEnabled ? const Icon(Icons.star, color: Colors.red, size: 12) : null,
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _addressCtrl, 
                        decoration: InputDecoration(
                          labelText: 'Dirección', 
                          prefixIcon: const Icon(Icons.location_on), 
                          border: const OutlineInputBorder(),
                          suffixIcon: _isFeEnabled ? const Icon(Icons.star, color: Colors.red, size: 12) : null,
                        )
                      ),
                    ),
                    const SizedBox(width: 10),
                    // --- NUEVO AUTOCOMPLETADO INTELIGENTE DE CIUDAD ---
                    Expanded(
                      flex: 2,
                      child: Autocomplete<Map<String, String>>(
                        // 1. ¿Qué opciones mostrar según lo que escribe el usuario?
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<Map<String, String>>.empty();
                          }
                          return colombiaCities.where((city) => 
                            city['name']!.toLowerCase().contains(textEditingValue.text.toLowerCase())
                          );
                        },
                        // 2. ¿Qué texto mostrar en la lista desplegable?
                        displayStringForOption: (option) => option['name']!,
                        // 3. ¿Qué hacer cuando el usuario selecciona una ciudad?
                        onSelected: (option) {
                          _cityCtrl.text = option['name']!;
                          _daneCodeCtrl.text = option['dane']!; // ¡Se llena solo!
                          
                          // Opcional: Mostramos un mini aviso visual de que hicimos el trabajo duro por él
                          if (_isFeEnabled) {
                             ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Código DANE ${option['dane']} asignado automáticamente'), duration: const Duration(seconds: 1), backgroundColor: Colors.indigo)
                             );
                          }
                        },
                        // 4. Diseño del campo de texto principal
                        fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                          // Sincronizamos el controlador interno
                          if (_cityCtrl.text.isNotEmpty && textEditingController.text.isEmpty) {
                            textEditingController.text = _cityCtrl.text;
                          }
                          
                          return TextFormField(
                            controller: textEditingController,
                            focusNode: focusNode,
                            textInputAction: TextInputAction.next, // Sugiere al teclado que el Enter es para "Siguiente"
                            decoration: const InputDecoration(
                              labelText: 'Ciudad', 
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (val) {
                              _cityCtrl.text = val;
                              if (val.isEmpty) _daneCodeCtrl.clear();
                            },
                            // --- AJUSTE: MAGIA AL PRESIONAR ENTER ---
                            onFieldSubmitted: (String value) {
                              if (value.isNotEmpty) {
                                // Buscamos la primera ciudad que coincida con lo que escribió
                                final matches = colombiaCities.where((city) => 
                                  city['name']!.toLowerCase().contains(value.toLowerCase())
                                );
                                
                                // Si hay coincidencias, autocompletamos todo a la fuerza
                                if (matches.isNotEmpty) {
                                  final firstMatch = matches.first;
                                  textEditingController.text = firstMatch['name']!;
                                  _cityCtrl.text = firstMatch['name']!;
                                  _daneCodeCtrl.text = firstMatch['dane']!;
                                }
                              }
                              // Ejecutamos la acción nativa de Flutter (cerrar la lista y soltar foco)
                              onFieldSubmitted();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _secondaryCtrl,
                  decoration: const InputDecoration(labelText: 'Contacto Secundario', prefixIcon: Icon(Icons.perm_contact_calendar), border: OutlineInputBorder(), helperText: 'Ej: Secretaria, Esposa, Socio'),
                ),
              ],

              const SizedBox(height: 15),

              // --- SECCIÓN EXCLUSIVA: FACTURACIÓN ELECTRÓNICA ---
              if (isEmpresarial) ...[
                const Divider(),
                SwitchListTile(
                  title: const Text('Facturación Electrónica', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                  subtitle: const Text('Exige los datos necesarios por la DIAN para este cliente.'),
                  secondary: const Icon(Icons.receipt_long, color: Colors.indigo),
                  value: _isFeEnabled,
                  activeColor: Colors.indigo,
                  onChanged: (val) {
                    setState(() {
                      _isFeEnabled = val;
                      if (val) _showOptional = true; // Forzamos abrir el panel de arriba
                    });
                  },
                ),
                
                if (_isFeEnabled)
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.indigo.shade100)
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Datos DIAN", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                        const SizedBox(height: 15),
                        DropdownButtonFormField<String>(
                          value: _personType,
                          decoration: const InputDecoration(labelText: 'Tipo de Persona', border: OutlineInputBorder(), isDense: true, fillColor: Colors.white, filled: true),
                          items: const [
                            DropdownMenuItem(value: '2', child: Text('Persona Natural')),
                            DropdownMenuItem(value: '1', child: Text('Persona Jurídica (Empresa)')),
                          ],
                          onChanged: (v) => setState(() => _personType = v!),
                        ),
                        const SizedBox(height: 15),
                        DropdownButtonFormField<String>(
                          value: _taxRegime,
                          decoration: const InputDecoration(labelText: 'Responsabilidad Tributaria', border: OutlineInputBorder(), isDense: true, fillColor: Colors.white, filled: true),
                          items: const [
                            DropdownMenuItem(value: '49', child: Text('No Responsable de IVA')),
                            DropdownMenuItem(value: '48', child: Text('Responsable de IVA')),
                          ],
                          onChanged: (v) => setState(() => _taxRegime = v!),
                        ),
                        const SizedBox(height: 15),
                        TextFormField(
                          controller: _daneCodeCtrl,
                          readOnly: true, // <-- CRÍTICO: El usuario no lo puede editar manualmente
                          decoration: const InputDecoration(
                            labelText: 'Código DANE', 
                            border: OutlineInputBorder(), 
                            fillColor: Color(0xFFF1F5F9), // Un color gris clarito para indicar que está bloqueado
                            filled: true,
                            helperText: 'Se llena automáticamente al seleccionar la ciudad arriba ☝️',
                            prefixIcon: Icon(Icons.auto_awesome, color: Colors.amber), // Un toque premium
                            suffixIcon: Icon(Icons.star, color: Colors.red, size: 12)
                          ),
                        ),
                      ],
                    ),
                  ),
              ],

              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _isLoading ? null : _save,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.blue[800], foregroundColor: Colors.white),
                child: _isLoading ? const CircularProgressIndicator() : const Text('GUARDAR CLIENTE'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}