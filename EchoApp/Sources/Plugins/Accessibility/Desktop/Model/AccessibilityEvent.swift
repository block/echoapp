enum AccessibilityEvent: Codable {
    case requestSnapshot
    case snapshot(Snapshot)
    case sendLiveUpdates(Bool)
}
