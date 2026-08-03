import Foundation

/// Bundle identifiers of common calling/meeting apps. Used to notice when a call is likely
/// starting, so the user can be prompted to turn on translation instead of having to remember
/// to open RealtimeTranslator themselves.
enum KnownCallApps {
    static let displayNames: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.microsoft.teams": "Microsoft Teams",
        "com.cisco.webexmeetingsapp": "Webex",
        "com.skype.skype": "Skype",
        "com.apple.FaceTime": "FaceTime",
        "com.hnc.Discord": "Discord",
    ]

    static func displayName(forBundleIdentifier bundleIdentifier: String) -> String? {
        displayNames[bundleIdentifier]
    }
}
