import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/currency_formatter.dart'; // Verifica que esta ruta sea correcta en tu proyecto

class DenominationCalculatorDialog extends StatefulWidget {
  final Function(double) onConfirm;
  const DenominationCalculatorDialog({super.key, required this.onConfirm});

  @override
  State<DenominationCalculatorDialog> createState() => _DenominationCalculatorDialogState();
}

class _DenominationCalculatorDialogState extends State<DenominationCalculatorDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // --- ESTADO PESTAÑA DENOMINACIONES ---
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, FocusNode> _focusNodes = {}; 
  
  final List<int> _denominations = [
    100000, 50000, 20000, 10000, 5000, 2000, 1000, 500, 200, 100, 50
  ];

  final Map<int, int> _counts = {};

  // --- ESTADO PESTAÑA CALCULADORA ---
  final FocusNode _calcFocusNode = FocusNode(); 
  String _calcInput = "";
  double _calcTotal = 0;
  String _history = ""; 

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        _calcFocusNode.requestFocus(); 
      }
    });

    for (var denom in _denominations) {
      _counts[denom] = 0;
      _controllers[denom] = TextEditingController(text: "0");
      
      _focusNodes[denom] = FocusNode()..addListener(() {
        if (_focusNodes[denom]!.hasFocus) {
          _controllers[denom]!.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _controllers[denom]!.text.length
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _calcFocusNode.dispose();
    for (var c in _controllers.values) c.dispose();
    for (var f in _focusNodes.values) f.dispose();
    super.dispose();
  }

  // --- LÓGICA BILLETES ---
  double get _totalDenominations => _counts.entries.fold(0, (sum, entry) => sum + (entry.key * entry.value));

  void _updateCountFromText(int denom, String value) {
    String clean = value.replaceAll(RegExp(r'[^0-9]'), '');
    int newCount = int.tryParse(clean) ?? 0;
    setState(() {
      _counts[denom] = newCount;
    });
  }

  void _changeCount(int denom, int delta) {
    setState(() {
      int current = _counts[denom] ?? 0;
      int newVal = current + delta;
      if (newVal < 0) newVal = 0;
      _counts[denom] = newVal;
      _controllers[denom]?.text = newVal.toString();
    });
  }

  // --- LÓGICA CALCULADORA ---
  void _calcHandleKey(String key) {
    if (key == 'C') {
      _calcClear();
    } else if (key == 'BACKSPACE') {
      _calcBackspace();
    } else if (key == 'ENTER') {
      _calcSum();
    } else {
      _calcAddDigit(key);
    }
  }

  void _calcAddDigit(String digit) {
    if (_calcInput == "0" && digit == "0") return;
    if (_calcInput == "0" && digit != "0") _calcInput = "";

    setState(() {
      if (digit == '00') {
        _calcInput += '00';
      } else {
        _calcInput += digit;
      }
    });
  }

  void _calcSum() {
    if (_calcInput.isEmpty) return;
    final val = double.tryParse(_calcInput) ?? 0;
    if (val > 0) {
      setState(() {
        _calcTotal += val;
        _history += _history.isEmpty ? CurrencyFormatter.format(val) : " + ${CurrencyFormatter.format(val)}";
        _calcInput = "";
      });
    }
  }

  void _calcClear() {
    setState(() {
      _calcInput = "";
      _calcTotal = 0;
      _history = "";
    });
  }
  
  void _calcBackspace() {
    setState(() {
      if (_calcInput.isNotEmpty) {
        _calcInput = _calcInput.substring(0, _calcInput.length - 1);
      }
    });
  }

// --- FUNCIÓN BLINDADA PARA CUALQUIER TECLADO ---
  void _handlePhysicalKey(KeyEvent event) {
    // Solo actuamos cuando la tecla se presiona (KeyDown)
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;
    final String? char = event.character;

    // 1. Detección Inteligente de NÚMEROS (0-9)
    // Verificamos si la tecla generó un carácter numérico. 
    // Esto funciona para el teclado de arriba Y el numérico (si Bloq Num está activo).
    if (char != null && int.tryParse(char) != null) {
      _calcHandleKey(char);
      return; 
    }

    // 2. Teclas de Acción (Enter, Sumar, Borrar)
    if (key == LogicalKeyboardKey.enter || 
        key == LogicalKeyboardKey.numpadEnter || 
        key == LogicalKeyboardKey.numpadAdd) { // Tecla + del Numpad
      _calcHandleKey('ENTER');
    }
    else if (key == LogicalKeyboardKey.backspace) {
      _calcHandleKey('BACKSPACE');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      titlePadding: EdgeInsets.zero,
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
            decoration: const BoxDecoration(
              color: Colors.indigo,
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) {
                final isCalc = _tabController.index == 1;
                final currentTotal = isCalc ? _calcTotal : _totalDenominations;
                
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Total a ingresar:", style: TextStyle(color: Colors.white70, fontSize: 14)),
                    Text(
                      CurrencyFormatter.format(currentTotal),
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ],
                );
              },
            ),
          ),
          TabBar(
            controller: _tabController,
            labelColor: Colors.indigo,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.indigo,
            onTap: (_) => setState((){}),
            tabs: const [
              Tab(icon: Icon(Icons.money), text: "Billetes"),
              Tab(icon: Icon(Icons.calculate), text: "Calculadora"),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildDenominationTab(),
            _buildCalculatorTab(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
        ),
        FilledButton.icon(
          onPressed: () {
            final isCalc = _tabController.index == 1;
            final finalVal = isCalc ? _calcTotal : _totalDenominations;
            widget.onConfirm(finalVal);
            Navigator.pop(context);
          }, 
          icon: const Icon(Icons.check),
          label: const Text("Usar Total"),
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
        ),
      ],
    );
  }

  Widget _buildDenominationTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          color: Colors.grey[100],
          child: const Row(
            children: [
              Expanded(flex: 2, child: Text("Denominación", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Expanded(flex: 3, child: Center(child: Text("Cantidad", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
              Expanded(flex: 2, child: Align(alignment: Alignment.centerRight, child: Text("Subtotal", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(10, 5, 10, 10),
            itemCount: _denominations.length,
            separatorBuilder: (_,__) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final denom = _denominations[index];
              final count = _counts[denom] ?? 0;
              final subtotal = denom * count;
              
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        CurrencyFormatter.format(denom.toDouble()).replaceAll('.00', ''),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Focus(
                            canRequestFocus: false, 
                            descendantsAreFocusable: false,
                            child: _CircleButton(
                              icon: Icons.remove, 
                              onTap: () => _changeCount(denom, -1),
                              color: Colors.red[100]!,
                              iconColor: Colors.red,
                            ),
                          ),
                          Container(
                            width: 70,
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                            child: TextField(
                              controller: _controllers[denom],
                              focusNode: _focusNodes[denom],
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (val) => _updateCountFromText(denom, val),
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          Focus(
                            canRequestFocus: false,
                            descendantsAreFocusable: false,
                            child: _CircleButton(
                              icon: Icons.add, 
                              onTap: () => _changeCount(denom, 1),
                              color: Colors.green[100]!,
                              iconColor: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        CurrencyFormatter.format(subtotal.toDouble()),
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCalculatorTab() {
    return KeyboardListener(
      focusNode: _calcFocusNode,
      onKeyEvent: _handlePhysicalKey, // <--- Usamos la nueva función robusta
      child: Column(
        children: [
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: Colors.grey[50],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _history.isEmpty ? "Empezar suma..." : _history,
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (_calcInput.isNotEmpty || _calcTotal > 0)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: _calcClear,
                          tooltip: "Limpiar Todo",
                        ),
                      Text(
                        _calcInput.isEmpty ? "0" : CurrencyFormatter.format(double.tryParse(_calcInput) ?? 0),
                        style: TextStyle(
                          fontSize: 32, 
                          fontWeight: FontWeight.bold, 
                          color: _calcInput.isEmpty ? Colors.grey[300] : Colors.black87
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Expanded(child: Row(children: [_btn('7'), _btn('8'), _btn('9')])),
                  Expanded(child: Row(children: [_btn('4'), _btn('5'), _btn('6')])),
                  Expanded(child: Row(children: [_btn('1'), _btn('2'), _btn('3')])),
                  Expanded(child: Row(
                    children: [
                      _btn('00'),
                      _btn('0'),
                      _btn('⌫', color: Colors.orange[50], textColor: Colors.orange[800], onTap: _calcBackspace),
                    ]
                  )),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: ElevatedButton.icon(
                        onPressed: _calcSum,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.add_circle, size: 28),
                        label: const Text("SUMAR (+)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _btn(String label, {Color? color, Color? textColor, VoidCallback? onTap}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: InkWell(
          onTap: onTap ?? () => _calcAddDigit(label),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: color ?? Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(color: Colors.grey.shade200, blurRadius: 2, offset: const Offset(0, 2))
              ]
            ),
            alignment: Alignment.center,
            child: Text(
              label, 
              style: TextStyle(
                fontSize: 22, 
                fontWeight: FontWeight.bold, 
                color: textColor ?? Colors.grey[800]
              )
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color iconColor;

  const _CircleButton({required this.icon, required this.onTap, required this.color, required this.iconColor});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }
}