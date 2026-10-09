import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Definimos un estado simple para el Wizard
class SetupWizardState {
  final int currentStep;
  final bool isLoading;
  final String errorMessage;

  SetupWizardState({
    this.currentStep = 0,
    this.isLoading = false,
    this.errorMessage = '',
  });

  SetupWizardState copyWith({
    int? currentStep,
    bool? isLoading,
    String? errorMessage,
  }) {
    return SetupWizardState(
      currentStep: currentStep ?? this.currentStep,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

// Notifier para manejar el estado del Wizard
class SetupWizardNotifier extends Notifier<SetupWizardState> {
  @override
  SetupWizardState build() {
    return SetupWizardState();
  }

  void setStep(int step) {
    state = state.copyWith(currentStep: step);
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void setError(String error) {
    state = state.copyWith(errorMessage: error);
  }

  void nextStep() {
    if (state.currentStep < 2) {
      state = state.copyWith(currentStep: state.currentStep + 1);
    }
  }

  void previousStep() {
    if (state.currentStep > 0) {
      state = state.copyWith(currentStep: state.currentStep - 1);
    }
  }
}

final setupWizardProvider =
    NotifierProvider<SetupWizardNotifier, SetupWizardState>(() {
      return SetupWizardNotifier();
    });
