/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// AIImageFlowView.swift
//
// Container view that manages the entire AI image generation flow.
// Displays appropriate sub-view based on the current generation state.
//

import SwiftUI

struct AIImageFlowView: View {
    @ObservedObject var viewModel: AIImageGenerationViewModel
    
    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                EmptyView()
                
            case .promptInput:
                AIPromptInputView(viewModel: viewModel)
                
            case .generating:
                AIGeneratingView(viewModel: viewModel)
                
            case .completed:
                AIGeneratedImageView(viewModel: viewModel)
                
            case .error(let message):
                AIErrorView(
                    errorMessage: message,
                    onRetry: { viewModel.tryAgain() },
                    onDismiss: { viewModel.dismiss() }
                )
            }
        }
    }
}
