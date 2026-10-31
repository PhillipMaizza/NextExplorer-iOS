#if os(macOS)
    import Carbon

    /// XCUITest types with US key codes, so on another layout (Italian puts [ and ] elsewhere)
    /// ⌘[ becomes some other shortcut and typed names come out wrong. Each Mac test switches to
    /// the ABC layout and puts the person's own layout back when it ends.
    enum KeyboardLayout {
        private static let usLayoutID = "com.apple.keylayout.ABC"

        /// Selects ABC and returns what restores the previous layout, or `nil` when ABC is
        /// already in use or isn't installed.
        static func useUS() -> (() -> Void)? {
            guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                  identifier(of: current) != usLayoutID,
                  let us = installedSource(usLayoutID)
            else { return nil }
            // Enabled only for the test, so the person's input menu is left as it was.
            let wasEnabled = isEnabled(us)
            if !wasEnabled {
                TISEnableInputSource(us)
            }
            TISSelectInputSource(us)
            return {
                TISSelectInputSource(current)
                if !wasEnabled {
                    TISDisableInputSource(us)
                }
            }
        }

        private static func installedSource(_ identifier: String) -> TISInputSource? {
            let filter = [kTISPropertyInputSourceID as String: identifier] as CFDictionary
            let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
            return sources?.first
        }

        private static func identifier(of source: TISInputSource) -> String? {
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
            return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        }

        private static func isEnabled(_ source: TISInputSource) -> Bool {
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else { return false }
            return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
        }
    }
#endif
