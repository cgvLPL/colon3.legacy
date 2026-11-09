import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// iOS 15 support. colon3 is written against the current SDK; everything here wraps an API that
// is newer than iOS 15 so that iOS 16+ keeps the native behaviour and older systems get the
// closest equivalent (or nothing, for purely cosmetic touches like symbol animations).
//
// Naming: every wrapper starts with `compat` / `Compat` so call sites make it obvious.

// MARK: - UIKit helpers

@MainActor
enum CompatUIKit {
    /// The frontmost view controller, for presenting UIKit sheets and alerts on iOS 15.
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController, !presented.isBeingDismissed {
            controller = presented
        }
        return controller
    }

    /// The share sheet, presented from whatever is on screen.
    static func share(_ items: [Any]) {
        Task { @MainActor in
            // Give a menu or context menu that triggered this time to finish dismissing.
            try? await Task.sleep(nanoseconds: 350_000_000)
            let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
            topViewController()?.present(sheet, animated: true)
        }
    }

    /// Width a sideways shelf lays its pages out in: the screen minus its 20 pt margins.
    /// (colon3 is portrait-only on iPhone, so the screen width is the container width.)
    static var shelfContainerWidth: CGFloat { UIScreen.main.bounds.width - 40 }
}

enum CompatLocale {
    /// The user's region code ("US", "GB"…).
    static var regionCode: String? {
        if #available(iOS 16, *) {
            return Locale.current.region?.identifier
        } else {
            return Locale.current.regionCode
        }
    }
}

// MARK: - SF Symbols

enum CompatSymbol {
    /// `modern` on iOS `since` and later, else `fallback`. Symbols newer than the running
    /// system draw nothing, so older systems get the closest symbol they have.
    static func name(_ modern: String, since major: Int, fallback: String) -> String {
        let version = OperatingSystemVersion(majorVersion: major, minorVersion: 0, patchVersion: 0)
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(version) ? modern : fallback
    }
}

// MARK: - onChange

extension View {
    /// `onChange(of:)` without the iOS 17 deprecation, on every system.
    @ViewBuilder
    func compatOnChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(iOS 17, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
        }
    }
}

// MARK: - Navigation

/// NavigationStack on iOS 16+, a stack-style NavigationView on iOS 15.
struct CompatNavigationStack<Root: View>: View {
    private let root: Root

    init(@ViewBuilder root: () -> Root) {
        self.root = root()
    }

    var body: some View {
        if #available(iOS 16, *) {
            NavigationStack { root }
        } else {
            NavigationView { root }
                .navigationViewStyle(.stack)
        }
    }
}

/// Destinations registered with `compatNavigationDestination(for:)`, used on iOS 15 where
/// value-based navigation doesn't exist. Links look their value's type up here.
struct CompatDestinations {
    fileprivate var builders: [ObjectIdentifier: (Any) -> AnyView] = [:]

    fileprivate func view<Value>(for value: Value) -> AnyView? {
        builders[ObjectIdentifier(Value.self)]?(value)
    }
}

private struct CompatDestinationsKey: EnvironmentKey {
    static let defaultValue = CompatDestinations()
}

extension EnvironmentValues {
    var compatDestinations: CompatDestinations {
        get { self[CompatDestinationsKey.self] }
        set { self[CompatDestinationsKey.self] = newValue }
    }
}

private struct CompatDestinationModifier<Value: Hashable, Destination: View>: ViewModifier {
    let type: Value.Type
    let destination: (Value) -> Destination
    @Environment(\.compatDestinations) private var inherited

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content.navigationDestination(for: type, destination: destination)
        } else {
            content.environment(\.compatDestinations, registered)
        }
    }

    private var registered: CompatDestinations {
        var all = inherited
        let build = destination
        all.builders[ObjectIdentifier(Value.self)] = { value in
            guard let value = value as? Value else { return AnyView(EmptyView()) }
            return AnyView(build(value))
        }
        return all
    }
}

private struct CompatPresentedDestinationModifier<Destination: View>: ViewModifier {
    @Binding var isPresented: Bool
    let destination: Destination

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content.navigationDestination(isPresented: $isPresented) { destination }
        } else {
            content.background(
                NavigationLink(destination: destination, isActive: $isPresented) { EmptyView() }
                    .hidden()
            )
        }
    }
}

extension View {
    func compatNavigationDestination<Value: Hashable, Destination: View>(
        for type: Value.Type, @ViewBuilder destination: @escaping (Value) -> Destination
    ) -> some View {
        modifier(CompatDestinationModifier(type: type, destination: destination))
    }

    func compatNavigationDestination<Destination: View>(
        isPresented: Binding<Bool>, @ViewBuilder destination: () -> Destination
    ) -> some View {
        modifier(CompatPresentedDestinationModifier(isPresented: isPresented, destination: destination()))
    }
}

/// `NavigationLink(value:)` on iOS 16+; on iOS 15 a destination link built from the
/// destinations registered further up with `compatNavigationDestination(for:)`.
struct CompatNavigationLink<Value: Hashable, Label: View>: View {
    private let value: Value?
    private let label: Label
    @Environment(\.compatDestinations) private var destinations

    init(value: Value?, @ViewBuilder label: () -> Label) {
        self.value = value
        self.label = label()
    }

    var body: some View {
        if #available(iOS 16, *) {
            NavigationLink(value: value) { label }
        } else {
            NavigationLink(destination: legacyDestination) { label }
        }
    }
}

extension CompatNavigationLink {
    private var legacyDestination: some View {
        Group {
            if let value, let view = destinations.view(for: value) {
                view
            } else {
                EmptyView()
            }
        }
        // Links on the pushed screen can reach the same destinations.
        .environment(\.compatDestinations, destinations)
    }
}

extension ToolbarItemPlacement {
    static var compatTrailing: ToolbarItemPlacement {
        if #available(iOS 17, *) { return .topBarTrailing }
        return .navigationBarTrailing
    }

    static var compatLeading: ToolbarItemPlacement {
        if #available(iOS 17, *) { return .topBarLeading }
        return .navigationBarLeading
    }
}

// MARK: - Sheets and presentation

extension View {
    /// Half-height sheet that can be pulled to full height, with a grabber. iOS 15 sets the
    /// same detents on the sheet's UISheetPresentationController.
    @ViewBuilder
    func compatMediumLargeDetents() -> some View {
        if #available(iOS 16, *) {
            presentationDetents([.medium, .large])
        } else {
            background(SheetConfigurator { sheet, _ in
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            })
        }
    }

    @ViewBuilder
    func compatHiddenDragIndicator() -> some View {
        if #available(iOS 16, *) {
            presentationDragIndicator(.hidden)
        } else {
            background(SheetConfigurator { sheet, _ in sheet.prefersGrabberVisible = false })
        }
    }

    @ViewBuilder
    func compatPresentationBackground(_ color: Color) -> some View {
        if #available(iOS 16.4, *) {
            presentationBackground(color)
        } else {
            background(SheetConfigurator { _, presented in
                presented.view.backgroundColor = UIColor(color)
            })
        }
    }

    @ViewBuilder
    func compatContextMenu<MenuItems: View, Preview: View>(
        @ViewBuilder menuItems: () -> MenuItems, @ViewBuilder preview: () -> Preview
    ) -> some View {
        let items = menuItems()
        if #available(iOS 16, *) {
            let previewView = preview()
            contextMenu { items } preview: { previewView }
        } else {
            contextMenu { items }
        }
    }

    /// A one-text-field alert ("New Playlist", "Save Preset"…). Text fields in SwiftUI alerts
    /// need iOS 16, so iOS 15 gets a UIAlertController with the same buttons.
    func compatTextFieldAlert(
        _ title: String, isPresented: Binding<Bool>, text: Binding<String>, placeholder: String = "Name",
        confirm: String, action: @escaping () -> Void
    ) -> some View {
        modifier(CompatTextFieldAlert(title: title, isPresented: isPresented, text: text,
                                      placeholder: placeholder, confirm: confirm, action: action))
    }
}

private struct CompatTextFieldAlert: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    @Binding var text: String
    let placeholder: String
    let confirm: String
    let action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content.alert(title, isPresented: $isPresented) {
                TextField(placeholder, text: $text)
                Button("Cancel", role: .cancel) {}
                Button(confirm, action: action)
            }
        } else {
            content.compatOnChange(of: isPresented) { shown in
                if shown { present() }
            }
        }
    }

    @MainActor
    private func present() {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = text
            field.placeholder = placeholder
            field.autocapitalizationType = .sentences
            field.clearButtonMode = .whileEditing
        }
        let binding = $text
        let shown = $isPresented
        let confirmAction = action
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            shown.wrappedValue = false
        })
        alert.addAction(UIAlertAction(title: confirm, style: .default) { [weak alert] _ in
            binding.wrappedValue = alert?.textFields?.first?.text ?? ""
            shown.wrappedValue = false
            confirmAction()
        })
        guard let presenter = CompatUIKit.topViewController() else {
            shown.wrappedValue = false
            return
        }
        presenter.present(alert, animated: true)
    }
}

/// Reaches the UIKit controller SwiftUI presented a sheet with, to configure what SwiftUI
/// can't on older systems.
private struct SheetConfigurator: UIViewControllerRepresentable {
    let configure: (UISheetPresentationController, UIViewController) -> Void

    func makeUIViewController(context: Context) -> Controller { Controller(configure: configure) }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        private let configure: (UISheetPresentationController, UIViewController) -> Void

        init(configure: @escaping (UISheetPresentationController, UIViewController) -> Void) {
            self.configure = configure
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func loadView() {
            view = UIView(frame: .zero)
            view.isUserInteractionEnabled = false
        }

        override func willMove(toParent parent: UIViewController?) {
            super.willMove(toParent: parent)
            apply()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        private func apply() {
            // The top of the parent chain is the controller the sheet presented.
            var root: UIViewController = self
            while let parent = root.parent { root = parent }
            guard root.presentingViewController != nil, let sheet = root.sheetPresentationController else { return }
            configure(sheet, root)
        }
    }
}

// MARK: - Lists and scrolling

extension View {
    /// `scrollContentBackground(.hidden)`. On iOS 15 (UITableView-backed lists) the table's
    /// background is cleared directly.
    @ViewBuilder
    func compatHiddenScrollBackground() -> some View {
        if #available(iOS 16, *) {
            scrollContentBackground(.hidden)
        } else {
            background(ClearTableBackground())
        }
    }

    @ViewBuilder
    func compatSelectionDisabled() -> some View {
        if #available(iOS 17, *) {
            selectionDisabled()
        } else {
            self
        }
    }

    /// The stack inside a sideways shelf: snapping targets on iOS 17+, plain margins before.
    @ViewBuilder
    func compatShelfContent() -> some View {
        if #available(iOS 17, *) {
            scrollTargetLayout()
        } else {
            padding(.horizontal, 20)
        }
    }

    /// The sideways shelf's ScrollView: 20 pt content margins and paging by item on iOS 17+
    /// (earlier systems get the margins from `compatShelfContent` and snapping from
    /// `compatShelfSnapping`).
    @ViewBuilder
    func compatShelfPaging() -> some View {
        if #available(iOS 17, *) {
            contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
        } else {
            self
        }
    }

    /// Goes on the shelf's content (iOS 15/16): installs the snapping on its scroll view.
    @ViewBuilder
    func compatShelfSnapping(interval: CGFloat) -> some View {
        if #available(iOS 17, *) {
            self
        } else {
            background(ScrollSnapper(interval: interval))
        }
    }

    /// A shelf page as wide as the shelf, less `inset`.
    @ViewBuilder
    func compatShelfWidth(inset: CGFloat) -> some View {
        if #available(iOS 17, *) {
            containerRelativeFrame(.horizontal) { width, _ in width - inset }
        } else {
            frame(width: CompatUIKit.shelfContainerWidth - inset)
        }
    }

    /// `count` cards to a shelf width.
    @ViewBuilder
    func compatShelfWidth(count: Int, spacing: CGFloat) -> some View {
        if #available(iOS 17, *) {
            containerRelativeFrame(.horizontal, count: count, spacing: spacing)
        } else {
            frame(width: (CompatUIKit.shelfContainerWidth - spacing * CGFloat(count - 1)) / CGFloat(count))
        }
    }
}

/// Finds the enclosing UIScrollView and makes it stop on item boundaries, one item per swipe,
/// like iOS 17's `.scrollTargetBehavior(.viewAligned)`.
private struct ScrollSnapper: UIViewRepresentable {
    let interval: CGFloat

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let interval = interval
        Task { @MainActor in
            var ancestor = view.superview
            while let current = ancestor, !(current is UIScrollView) { ancestor = current.superview }
            guard let scrollView = ancestor as? UIScrollView else { return }
            SnapDelegate.install(on: scrollView, interval: interval)
        }
    }
}

/// Sits in front of SwiftUI's own scroll view delegate, forwarding everything to it and only
/// adjusting where a swipe comes to rest.
private final class SnapDelegate: NSObject, UIScrollViewDelegate {
    private static var key = 0
    weak var original: UIScrollViewDelegate?
    var interval: CGFloat

    private init(original: UIScrollViewDelegate?, interval: CGFloat) {
        self.original = original
        self.interval = interval
    }

    static func install(on scrollView: UIScrollView, interval: CGFloat) {
        if let current = scrollView.delegate as? SnapDelegate {
            current.interval = interval
            return
        }
        let snap = SnapDelegate(original: scrollView.delegate, interval: interval)
        // The scroll view holds its delegate weakly; keep ours alive alongside it.
        objc_setAssociatedObject(scrollView, &key, snap, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        scrollView.decelerationRate = .fast
        scrollView.delegate = snap
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : nil
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        original?.scrollViewWillEndDragging?(scrollView, withVelocity: velocity,
                                             targetContentOffset: targetContentOffset)
        guard interval > 1 else { return }
        let position = scrollView.contentOffset.x / interval
        let page: CGFloat
        if velocity.x > 0.2 {
            page = floor(position) + 1
        } else if velocity.x < -0.2 {
            page = ceil(position) - 1
        } else {
            page = position.rounded()
        }
        let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        targetContentOffset.pointee.x = min(max(0, page * interval), maxOffset)
    }
}

/// Finds the UITableView a List sits on (iOS 15) and makes its background clear.
private struct ClearTableBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        Task { @MainActor in
            var ancestor = view.superview
            for _ in 0..<6 {
                guard let current = ancestor else { return }
                if let table = Self.table(in: current) {
                    table.backgroundColor = .clear
                    return
                }
                ancestor = current.superview
            }
        }
    }

    private static func table(in view: UIView) -> UITableView? {
        if let table = view as? UITableView { return table }
        for child in view.subviews {
            if let table = table(in: child) { return table }
        }
        return nil
    }
}

// MARK: - Symbols, haptics, styles

enum CompatFeedback {
    case selection
    case success
    case lightImpact

    @available(iOS 17, *)
    var native: SensoryFeedback {
        switch self {
        case .selection: return .selection
        case .success: return .success
        case .lightImpact: return .impact(weight: .light)
        }
    }

    @MainActor
    func play() {
        switch self {
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .lightImpact: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

private struct CompatSensoryFeedback<T: Equatable>: ViewModifier {
    let feedback: CompatFeedback
    let trigger: T
    let condition: ((T, T) -> Bool)?
    @State private var previous: T?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            if let condition {
                content.sensoryFeedback(feedback.native, trigger: trigger, condition: condition)
            } else {
                content.sensoryFeedback(feedback.native, trigger: trigger)
            }
        } else {
            content
                .onAppear { previous = trigger }
                .compatOnChange(of: trigger) { newValue in
                    let oldValue = previous ?? newValue
                    previous = newValue
                    if condition?(oldValue, newValue) ?? true { feedback.play() }
                }
        }
    }
}

extension View {
    func compatSensoryFeedback<T: Equatable>(_ feedback: CompatFeedback, trigger: T) -> some View {
        modifier(CompatSensoryFeedback(feedback: feedback, trigger: trigger, condition: nil))
    }

    func compatSensoryFeedback<T: Equatable>(
        _ feedback: CompatFeedback, trigger: T, condition: @escaping (T, T) -> Bool
    ) -> some View {
        modifier(CompatSensoryFeedback(feedback: feedback, trigger: trigger, condition: condition))
    }

    /// The symbol swap animation (play ⇄ pause, star ⇄ filled star). Before iOS 17 the old
    /// symbol shrinks and fades out as the new one grows in (and drops in, for `downUp`).
    /// `value` is whatever decides which symbol shows.
    @ViewBuilder
    func compatSymbolReplaceTransition<V: Hashable>(value: V, downUp: Bool = false) -> some View {
        if #available(iOS 17, *) {
            if downUp {
                contentTransition(.symbolEffect(.replace.downUp))
            } else {
                contentTransition(.symbolEffect(.replace))
            }
        } else {
            ZStack {
                id(value)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5).combined(with: .opacity)
                            .combined(with: .offset(y: downUp ? -6 : 0)),
                        removal: .scale(scale: 0.5).combined(with: .opacity)
                            .combined(with: .offset(y: downUp ? 6 : 0))))
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: value)
        }
    }

    /// The animated "now playing" waveform. Before iOS 17 it pulses instead.
    @ViewBuilder
    func compatVariableColorEffect(isActive: Bool) -> some View {
        if #available(iOS 17, *) {
            symbolEffect(.variableColor.iterative, isActive: isActive)
        } else {
            modifier(PulseEffect(isActive: isActive))
        }
    }
}

private struct PulseEffect: ViewModifier {
    let isActive: Bool
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.35 : 1)
            .onAppear { update(isActive) }
            .compatOnChange(of: isActive) { update($0) }
    }

    private func update(_ active: Bool) {
        if active {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { dimmed = true }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { dimmed = false }
        }
    }
}

extension Color {
    /// `color.gradient` on iOS 16+, the flat colour before.
    var compatGradient: AnyShapeStyle {
        if #available(iOS 16, *) { return AnyShapeStyle(gradient) }
        return AnyShapeStyle(self)
    }
}

// MARK: - Views that are new in iOS 16 / 17

/// `LabeledContent`: a title on the left, a secondary value on the right.
struct CompatLabeledContent<Content: View>: View {
    private let title: LocalizedStringKey
    private let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        if #available(iOS 16, *) {
            LabeledContent(title) { content }
        } else {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                content
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

extension CompatLabeledContent where Content == Text {
    init<S: StringProtocol>(_ title: LocalizedStringKey, value: S) {
        self.init(title) { Text(value) }
    }
}

/// `ContentUnavailableView`: a big symbol, a title, an explanation and optional buttons.
struct CompatUnavailableView<Actions: View>: View {
    private let title: String
    private let systemImage: String
    private let description: Text?
    private let actions: Actions

    init(_ title: String, systemImage: String, description: Text? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actions = actions()
    }

    var body: some View {
        if #available(iOS 17, *) {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                if let description { description }
            } actions: {
                actions
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 6)
                Text(title)
                    .font(.title2.weight(.bold))
                if let description {
                    description
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                actions
                    .padding(.top, 6)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension CompatUnavailableView where Actions == EmptyView {
    init(_ title: String, systemImage: String, description: Text? = nil) {
        self.init(title, systemImage: systemImage, description: description) { EmptyView() }
    }
}

/// `ShareLink` for a file. iOS 15 gets a button that opens the share sheet.
struct CompatShareLink<Label: View>: View {
    private let item: URL
    private let label: Label

    init(item: URL, @ViewBuilder label: () -> Label) {
        self.item = item
        self.label = label()
    }

    var body: some View {
        if #available(iOS 16, *) {
            ShareLink(item: item) { label }
        } else {
            Button { CompatUIKit.share([item]) } label: { label }
        }
    }
}

/// `PasteButton` for text. iOS 15 gets a plain Paste button (which shows the system's paste
/// permission prompt the first time).
struct CompatPasteButton: View {
    let onPaste: (String) -> Void

    var body: some View {
        if #available(iOS 16, *) {
            PasteButton(payloadType: String.self) { strings in
                guard let first = strings.first else { return }
                Task { @MainActor in onPaste(first) }
            }
        } else {
            Button {
                if let text = UIPasteboard.general.string { onPaste(text) }
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.bordered)
        }
    }
}

/// A text field that grows to three lines on iOS 16+; single-line on iOS 15.
struct CompatGrowingTextField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        if #available(iOS 16, *) {
            TextField(title, text: $text, axis: .vertical)
                .lineLimit(1...3)
        } else {
            TextField(title, text: $text)
        }
    }
}

// MARK: - Photo picker

extension View {
    /// Picks one photo and hands back its data (nil if it couldn't be read).
    @ViewBuilder
    func compatPhotoPicker(isPresented: Binding<Bool>, onPick: @escaping (Data?) -> Void) -> some View {
        if #available(iOS 16, *) {
            modifier(ModernPhotoPicker(isPresented: isPresented, onPick: onPick))
        } else {
            modifier(LegacyPhotoPicker(isPresented: isPresented, onPick: onPick))
        }
    }
}

@available(iOS 16, *)
private struct ModernPhotoPicker: ViewModifier {
    @Binding var isPresented: Bool
    let onPick: (Data?) -> Void
    @State private var item: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented, selection: $item, matching: .images)
            .compatOnChange(of: item) { picked in
                guard let picked else { return }
                item = nil
                Task { @MainActor in
                    onPick(try? await picked.loadTransferable(type: Data.self))
                }
            }
    }
}

private struct LegacyPhotoPicker: ViewModifier {
    @Binding var isPresented: Bool
    let onPick: (Data?) -> Void

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            LegacyPhotoPickerController(isPresented: $isPresented, onPick: onPick)
                .ignoresSafeArea()
        }
    }
}

private struct LegacyPhotoPickerController: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: LegacyPhotoPickerController

        init(_ parent: LegacyPhotoPickerController) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            guard let provider = results.first?.itemProvider else { return }
            let onPick = parent.onPick
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                DispatchQueue.main.async { onPick(data) }
            }
        }
    }
}
