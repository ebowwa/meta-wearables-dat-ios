/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// CircleButton.swift
//
// Reusable circular button component used in streaming controls and UI actions.
//

import SwiftUI

struct CircleButton: View {
  let icon: String
  let text: String?
  let backgroundColor: Color
  let foregroundColor: Color
  let isDisabled: Bool
  let action: () -> Void

  init(icon: String, text: String? = nil, backgroundColor: Color = .white, foregroundColor: Color = .black, isDisabled: Bool = false, action: @escaping () -> Void) {
    self.icon = icon
    self.text = text
    self.backgroundColor = backgroundColor
    self.foregroundColor = foregroundColor
    self.isDisabled = isDisabled
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      if let text {
        VStack(spacing: 2) {
          Image(systemName: icon)
            .font(.system(size: 14))
          Text(text)
            .font(.system(size: 10, weight: .medium))
        }
      } else {
        Image(systemName: icon)
          .font(.system(size: 16))
      }
    }
    .disabled(isDisabled)
    .foregroundColor(isDisabled ? foregroundColor.opacity(0.4) : foregroundColor)
    .frame(width: 56, height: 56)
    .background(isDisabled ? backgroundColor.opacity(0.5) : backgroundColor)
    .clipShape(Circle())
  }
}
