//
//  AISettingsView.swift
//  Redactor
//
//  Purpose: Settings container - AWS credentials loaded from environment variables
//  Organization: 3 Big Things
//

import SwiftUI

// MARK: - Settings Container View

/// Container for all settings tabs
/// Note: AI Settings removed - credentials are now loaded from environment variables:
///   - AWS_ACCESS_KEY_ID
///   - AWS_SECRET_ACCESS_KEY
///   - AWS_REGION (optional, defaults to ap-southeast-2)
struct SettingsContainerView: View {

    var body: some View {
        ExclusionSettingsView()
            .frame(width: 500, height: 450)
    }
}

// MARK: - Preview

#if DEBUG
struct SettingsContainerView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsContainerView()
    }
}
#endif
