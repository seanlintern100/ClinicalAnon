//
//  PhaseIndicator.swift
//  Redactor
//
//  Purpose: Horizontal stepper showing workflow progress
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Phase Indicator

/// Horizontal stepper showing: ● Redact ─── ○ Improve ─── ○ Restore
struct PhaseIndicator: View {

    // MARK: - Properties

    @ObservedObject var viewModel: WorkflowViewModel

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            ForEach(WorkflowPhase.allCases, id: \.self) { phase in
                PhaseStep(
                    phase: phase,
                    currentPhase: viewModel.currentPhase,
                    onTap: {
                        // Only allow navigating backward to completed phases
                        if phase.stepNumber < viewModel.currentPhase.stepNumber {
                            viewModel.goToPhase(phase)
                        }
                    }
                )

                // Connector line between phases
                if !phase.isLast {
                    PhaseConnector(isCompleted: phase.stepNumber < viewModel.currentPhase.stepNumber)
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.large)
        .padding(.vertical, DesignSystem.Spacing.medium)
    }
}

// MARK: - Phase Step

/// Individual phase step with circle and label
private struct PhaseStep: View {

    let phase: WorkflowPhase
    let currentPhase: WorkflowPhase
    let onTap: () -> Void

    private var state: StepState {
        if phase == currentPhase {
            return .current
        } else if phase.stepNumber < currentPhase.stepNumber {
            return .completed
        } else {
            return .upcoming
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: DesignSystem.Spacing.xs) {
                ZStack {
                    Circle()
                        .fill(circleBackground)
                        .frame(width: 28, height: 28)

                    if state == .completed {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    } else if state == .current {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                    }
                }

                Text(phase.displayName)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(state == .current ? .semibold : .regular)
                    .foregroundColor(textColor)
            }
        }
        .buttonStyle(.plain)
        .disabled(state == .upcoming)
    }

    private var circleBackground: Color {
        switch state {
        case .completed:
            return DesignSystem.Colors.success
        case .current:
            return DesignSystem.Colors.primaryTeal
        case .upcoming:
            return DesignSystem.Colors.textSecondary.opacity(0.3)
        }
    }

    private var textColor: Color {
        switch state {
        case .completed, .current:
            return DesignSystem.Colors.textPrimary
        case .upcoming:
            return DesignSystem.Colors.textSecondary
        }
    }
}

// MARK: - Phase Connector

/// Horizontal line connecting phase steps
private struct PhaseConnector: View {

    let isCompleted: Bool

    var body: some View {
        Rectangle()
            .fill(isCompleted ? DesignSystem.Colors.success : DesignSystem.Colors.textSecondary.opacity(0.3))
            .frame(width: 60, height: 2)
            .padding(.bottom, 20) // Align with circle center
    }
}

// MARK: - Step State

private enum StepState {
    case completed
    case current
    case upcoming
}

// MARK: - Preview

#if DEBUG
struct PhaseIndicator_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            // Redact phase
            PhaseIndicator(viewModel: {
                let vm = WorkflowViewModel()
                vm.currentPhase = .redact
                return vm
            }())

            // Improve phase
            PhaseIndicator(viewModel: {
                let vm = WorkflowViewModel()
                vm.currentPhase = .improve
                return vm
            }())

            // Restore phase
            PhaseIndicator(viewModel: {
                let vm = WorkflowViewModel()
                vm.currentPhase = .restore
                return vm
            }())
        }
        .padding()
        .background(DesignSystem.Colors.background)
    }
}
#endif
