from pathlib import Path
p=Path('Tests/HymnAppTests/ImportPresentationTests.swift')
s=p.read_text()
a=s.index('    @MainActor private func visibleText(')
b=s.index('    @MainActor private func saveEvidence(', a)
s=s[:a]+'''    @MainActor private func visibleText(_ window: NSWindow?) -> String {
        guard let root = window?.contentView else { return "" }
        var seen = Set<ObjectIdentifier>(), strings: [String] = []
        func add(_ value: Any?) {
            if let text = value as? String { strings.append(text) }
            else if let text = value as? NSAttributedString { strings.append(text.string) }
        }
        func visit(_ value: Any, _ depth: Int) {
            // SwiftUI exposes virtual accessibility elements as well as NSViews.
            // Include NSObjectProtocol implementations (for example proxy nodes),
            // and both the modern and attribute-based in-process AX interfaces.
            guard depth < 40, seen.count < 15000, let object = value as? NSObjectProtocol,
                  seen.insert(ObjectIdentifier(object as AnyObject)).inserted else { return }
            for key in ["accessibilityLabel", "accessibilityValue", "accessibilityTitle", "accessibilityIdentifier"] {
                let selector = NSSelectorFromString(key)
                if object.responds(to: selector) { add(object.perform(selector)?.takeUnretainedValue()) }
            }
            let attribute = NSSelectorFromString("accessibilityAttributeValue:")
            if object.responds(to: attribute) {
                for name in ["AXTitle", "AXValue", "AXDescription", "AXIdentifier"] {
                    add(object.perform(attribute, with: name as NSString)?.takeUnretainedValue())
                }
            }
            let children = NSSelectorFromString("accessibilityChildren")
            if object.responds(to: children), let values = object.perform(children)?.takeUnretainedValue() as? [Any] {
                for child in values { visit(child, depth + 1) }
            }
            if object.responds(to: attribute), let values = object.perform(attribute, with: "AXChildren" as NSString)?.takeUnretainedValue() as? [Any] {
                for child in values { visit(child, depth + 1) }
            }
            if let view = object as? NSView { for child in view.subviews { visit(child, depth + 1) } }
        }
        visit(root, 0)
        return strings.joined(separator: "\\n")
    }
''' + s[b:]
p.write_text(s)
