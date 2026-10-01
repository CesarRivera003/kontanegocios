class UserCodeGenerator {
  static const Set<String> _particles = {
    'DE', 'DEL', 'LA', 'LAS', 'LOS', 'SAN', 'SANTA'
  };

  static String _cleanString(String text) {
    const withAccents = 'ÁÉÍÓÚáéíóúÀÈÌÒÙàèìòùÄËÏÖÜäëïöüÑñ';
    const withoutAccents = 'AEIOUaeiouAEIOUaeiouAEIOUaeiouNn';

    String result = text;
    for (int i = 0; i < withAccents.length; i++) {
      result = result.replaceAll(withAccents[i], withoutAccents[i]);
    }
    return result.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
  }

  /// Extrae el primer nombre y el primer apellido de una cadena única
  static Map<String, String> extractFirstAndLastName(String fullName) {
    final rawTokens = fullName.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (rawTokens.isEmpty) return {'firstName': 'US', 'lastName': ''};

    final cleanedTokens = rawTokens.map(_cleanString).where((s) => s.isNotEmpty).toList();
    if (cleanedTokens.isEmpty) return {'firstName': 'US', 'lastName': ''};

    if (cleanedTokens.length == 1) {
      return {'firstName': cleanedTokens[0], 'lastName': ''};
    } else if (cleanedTokens.length == 2) {
      return {'firstName': cleanedTokens[0], 'lastName': cleanedTokens[1]};
    } else if (cleanedTokens.length == 3) {
      // Si la palabra del medio es partícula (ej: Ana de Gómez)
      if (_particles.contains(cleanedTokens[1])) {
        return {'firstName': cleanedTokens[0], 'lastName': cleanedTokens[2]};
      }
      // Estándar 3 palabras: Nombre Apellido1 Apellido2 (ej: César Rivera Sanabria)
      return {'firstName': cleanedTokens[0], 'lastName': cleanedTokens[1]};
    } else {
      // 4 o más palabras: Filtramos partículas (ej: Juan Carlos Pérez Rodríguez)
      final nonParticles = cleanedTokens.where((t) => !_particles.contains(t)).toList();
      if (nonParticles.length >= 3) {
        return {'firstName': nonParticles[0], 'lastName': nonParticles[2]};
      } else if (nonParticles.length == 2) {
        return {'firstName': nonParticles[0], 'lastName': nonParticles[1]};
      }
      return {'firstName': cleanedTokens[0], 'lastName': cleanedTokens[1]};
    }
  }

  static String generateUsername({
    required String fullName,
    required List<String> existingUsernames,
  }) {
    final names = extractFirstAndLastName(fullName);
    final fn = names['firstName']!;
    final ln = names['lastName']!;

    final firstTwo = fn.length >= 2 ? fn.substring(0, 2) : fn.padRight(2, 'X');
    String base = '$firstTwo$ln';

    if (base.length > 10) {
      base = base.substring(0, 10);
    }

    final upperExisting = existingUsernames.map((u) => u.toUpperCase()).toSet();
    if (!upperExisting.contains(base)) {
      return base;
    }

    int counter = 2;
    while (true) {
      final counterStr = counter.toString();
      final maxBaseLength = 10 - counterStr.length;
      final truncatedBase = base.length > maxBaseLength ? base.substring(0, maxBaseLength) : base;
      final candidate = '$truncatedBase$counterStr';

      if (!upperExisting.contains(candidate)) {
        return candidate;
      }
      counter++;
    }
  }

  static String generateRoleCode({
    required String roleName,
    required List<String> existingRoleCodes,
  }) {
    String prefix;
    switch (roleName.toLowerCase()) {
      case 'admin':
        prefix = 'A';
        break;
      case 'supervisor':
      case 'manager':
        prefix = 'S';
        break;
      case 'cashier':
      default:
        prefix = 'C';
        break;
    }

    final Set<int> usedNumbers = {};
    for (final rawCode in existingRoleCodes) {
      final code = rawCode.trim().toUpperCase();
      if (code.startsWith(prefix)) {
        final numberPart = code.substring(prefix.length);
        final parsed = int.tryParse(numberPart);
        if (parsed != null && parsed > 0) {
          usedNumbers.add(parsed);
        }
      }
    }

    int targetNumber = 1;
    while (usedNumbers.contains(targetNumber)) {
      targetNumber++;
    }

    final String formattedNumber = targetNumber < 100
        ? targetNumber.toString().padLeft(2, '0')
        : targetNumber.toString();

    return '$prefix$formattedNumber';
  }
}