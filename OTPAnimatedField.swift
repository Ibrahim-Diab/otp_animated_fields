//
//  OTPAnimatedField.swift
//
//  A one-time-code input whose boxes become the loading indicator. On submit
//  the boxes fly from the row onto a circle and orbit it while the code is
//  verified, then collapse into a check mark or return to the row and shake.
//
//  SwiftUI port of https://github.com/draz26648/otp_animated_fields (Flutter).
//  iOS 17+. Swift package, or drop this single file into a target; no dependencies.
//
//  Performance notes:
//  - Every animation is a pure function of time (`OTPMotion`), evaluated in
//    one `TimelineView` that is paused whenever nothing moves, so an idle
//    field costs no frames.
//  - Boxes move with `offset` / `scaleEffect` / `opacity`, which are
//    render-time effects: no layout pass per frame.
//  - Box bodies are `Equatable`, so per-frame re-evaluation skips them unless
//    their visual state actually changes.
//  - Rings, dots and the check mark are drawn in a single `Canvas`.
//

import SwiftUI
import UIKit

// MARK: - Status & controller

public enum OTPStatus: Equatable {
    /// Accepts input; boxes sit in a row.
    case idle
    /// Code submitted; boxes orbit while verification runs.
    case verifying
    /// Boxes collapse into a check mark and stay there until `reset()`.
    case success
    /// Boxes return to the row, shake, then the field returns to `idle`.
    case error
}

/// Holds the entered code and the verification status of an `OTPAnimatedField`.
///
/// ```swift
/// otp.verify()   // row -> orbit
/// otp.succeed()  // orbit -> check mark
/// otp.fail()     // orbit -> row, shake, back to idle
/// otp.reset()    // anything -> empty row
/// ```
@MainActor
@Observable
public final class OTPFieldController {
    public var code: String
    public private(set) var status: OTPStatus = .idle

    public init(code: String = "") {
        self.code = code
    }

    /// Submits the code. Has no effect unless idle; an incomplete code shakes.
    public func verify() {
        guard status == .idle else { return }
        status = .verifying
    }

    /// Resolves verification as successful. Use when the field has no `onVerify`.
    public func succeed() {
        guard status == .idle || status == .verifying else { return }
        status = .success
    }

    /// Resolves verification as failed. Use when the field has no `onVerify`.
    public func fail() {
        guard status == .idle || status == .verifying else { return }
        status = .error
    }

    /// Returns to `idle` from any status, e.g. after resending a code.
    public func reset(clearCode: Bool = true) {
        status = .idle
        if clearCode { code = "" }
    }
}

// MARK: - Style

/// Colors, sizes and timings of an `OTPAnimatedField`.
public struct OTPFieldStyle: Equatable {
    public var fillColor: Color
    public var borderColor: Color
    public var accentColor: Color
    public var ringColor: Color
    public var textColor: Color
    public var errorColor = Color(hex: 0xFF4D4F)
    public var successColor = Color(hex: 0x2ECC71)
    public var cursorColor: Color?

    public var fontSize: CGFloat = 24
    public var fontWeight: Font.Weight = .semibold
    public var fontDesign: Font.Design = .rounded

    public var boxSize: CGFloat = 58
    public var gap: CGFloat = 12
    public var cornerRadius: CGFloat = 16
    public var borderWidth: CGFloat = 1.5
    public var glowRadius: CGFloat = 18
    /// Size of a box on the orbit relative to `boxSize`, in (0, 1].
    public var orbitBoxScale: CGFloat = 0.64
    /// Fixed orbit radius. When nil it grows with the code length.
    public var orbitRadius: CGFloat?

    public var morphDuration: TimeInterval = 0.7
    public var orbitPeriod: TimeInterval = 2.6
    public var errorDuration: TimeInterval = 0.9
    public var successDuration: TimeInterval = 1.0
    public var styleDuration: TimeInterval = 0.22

    /// Creates a style from its five base colors; everything else keeps its
    /// default and can be changed afterwards (`style.boxSize = 64`).
    public init(fillColor: Color, borderColor: Color, accentColor: Color, ringColor: Color, textColor: Color) {
        self.fillColor = fillColor
        self.borderColor = borderColor
        self.accentColor = accentColor
        self.ringColor = ringColor
        self.textColor = textColor
    }

    /// The coral accent of the presets (#FF5A3C).
    public static let defaultAccent = Color(red: 1, green: 0x5A / 255, blue: 0x3C / 255)

    public static func dark(accent: Color = OTPFieldStyle.defaultAccent) -> OTPFieldStyle {
        OTPFieldStyle(
            fillColor: Color(hex: 0x1F1F26),
            borderColor: Color(hex: 0x34343E),
            accentColor: accent,
            ringColor: .white.opacity(0.2),
            textColor: .white
        )
    }

    public static func light(accent: Color = OTPFieldStyle.defaultAccent) -> OTPFieldStyle {
        OTPFieldStyle(
            fillColor: Color(hex: 0xF4F4F7),
            borderColor: Color(hex: 0xDADAE2),
            accentColor: accent,
            ringColor: .black.opacity(0.14),
            textColor: Color(hex: 0x16161A)
        )
    }
}

/// Colors set at the call site with `.otpFieldColors(...)`. Nil keeps the
/// color of the underlying style (the light/dark preset by default).
struct OTPFieldColors: Equatable {
    var accent: Color?
    var fill: Color?
    var border: Color?
    var text: Color?
    var ring: Color?
    var cursor: Color?
    var error: Color?
    var success: Color?
}

extension OTPFieldStyle {
    func applying(_ colors: OTPFieldColors) -> OTPFieldStyle {
        var style = self
        style.accentColor = colors.accent ?? accentColor
        style.fillColor = colors.fill ?? fillColor
        style.borderColor = colors.border ?? borderColor
        style.textColor = colors.text ?? textColor
        style.ringColor = colors.ring ?? ringColor
        style.cursorColor = colors.cursor ?? cursorColor
        style.errorColor = colors.error ?? errorColor
        style.successColor = colors.success ?? successColor
        return style
    }
}

extension EnvironmentValues {
    @Entry var otpFieldColors = OTPFieldColors()
}

extension View {
    /// Colors every `OTPAnimatedField` in this view. Pass only what you want to
    /// change; the rest keep the preset. Asset-catalog colors adapt to
    /// light/dark automatically. Nested calls combine, the inner one winning.
    ///
    /// ```swift
    /// OTPAnimatedField(onVerify: verify)
    ///     .otpFieldColors(accent: .blue, success: .mint)
    /// ```
    public func otpFieldColors(
        accent: Color? = nil,
        fill: Color? = nil,
        border: Color? = nil,
        text: Color? = nil,
        ring: Color? = nil,
        cursor: Color? = nil,
        error: Color? = nil,
        success: Color? = nil
    ) -> some View {
        transformEnvironment(\.otpFieldColors) { colors in
            colors.accent = accent ?? colors.accent
            colors.fill = fill ?? colors.fill
            colors.border = border ?? colors.border
            colors.text = text ?? colors.text
            colors.ring = ring ?? colors.ring
            colors.cursor = cursor ?? colors.cursor
            colors.error = error ?? colors.error
            colors.success = success ?? colors.success
        }
    }
}

/// VoiceOver label and announcements. An empty string silences one.
public struct OTPFieldLabels {
    public var field: String
    public var verifying: String
    public var success: String
    public var error: String

    public init(
        field: String = "One-time code",
        verifying: String = "Verifying code",
        success: String = "Code verified",
        error: String = "Incorrect code"
    ) {
        self.field = field
        self.verifying = verifying
        self.success = success
        self.error = error
    }
}

// MARK: - Field

public struct OTPAnimatedField: View {
    public typealias Verify = (String) async throws -> Bool

    private let length: Int
    private let externalController: OTPFieldController?
    private let customStyle: OTPFieldStyle?
    private let autofocus: Bool
    private let autoVerify: Bool
    private let clearsOnError: Bool
    private let reservesOrbitSpace: Bool
    private let obscuringCharacter: Character?
    private let hapticFeedback: Bool
    private let minimumVerifyingDuration: TimeInterval
    private let keyboardType: UIKeyboardType
    private let labels: OTPFieldLabels
    private let onChanged: ((String) -> Void)?
    private let onCompleted: ((String) -> Void)?
    private let onVerify: Verify?
    private let onStatusChanged: ((OTPStatus) -> Void)?
    private let onVerified: ((String) -> Void)?
    private let onFailed: ((String) -> Void)?

    /// - Parameters:
    ///   - onVerify: Verifies the code while the boxes orbit. `true` plays the
    ///     success animation; `false` or a thrown error plays the error one.
    ///     When nil, resolve with `controller.succeed()` / `controller.fail()`.
    ///   - onVerified: Called after the success animation, safe for navigation.
    ///   - onFailed: Called with the rejected code after the error animation.
    public init(
        length: Int = 4,
        controller: OTPFieldController? = nil,
        style: OTPFieldStyle? = nil,
        autofocus: Bool = false,
        autoVerify: Bool = true,
        clearsOnError: Bool = true,
        reservesOrbitSpace: Bool = true,
        obscuringCharacter: Character? = nil,
        hapticFeedback: Bool = true,
        minimumVerifyingDuration: TimeInterval = 1.5,
        keyboardType: UIKeyboardType = .numberPad,
        labels: OTPFieldLabels = OTPFieldLabels(),
        onChanged: ((String) -> Void)? = nil,
        onCompleted: ((String) -> Void)? = nil,
        onVerify: Verify? = nil,
        onStatusChanged: ((OTPStatus) -> Void)? = nil,
        onVerified: ((String) -> Void)? = nil,
        onFailed: ((String) -> Void)? = nil
    ) {
        precondition(length > 0, "length must be positive")
        self.length = length
        self.externalController = controller
        self.customStyle = style
        self.autofocus = autofocus
        self.autoVerify = autoVerify
        self.clearsOnError = clearsOnError
        self.reservesOrbitSpace = reservesOrbitSpace
        self.obscuringCharacter = obscuringCharacter
        self.hapticFeedback = hapticFeedback
        self.minimumVerifyingDuration = minimumVerifyingDuration
        self.keyboardType = keyboardType
        self.labels = labels
        self.onChanged = onChanged
        self.onCompleted = onCompleted
        self.onVerify = onVerify
        self.onStatusChanged = onStatusChanged
        self.onVerified = onVerified
        self.onFailed = onFailed
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    @State private var internalController = OTPFieldController()
    @State private var input = ""
    @FocusState private var isFocused: Bool
    @State private var availableWidth: CGFloat = 0

    @State private var motion = OTPMotion()
    /// What the boxes show. Lags behind `controller.status` so the result stays
    /// hidden until `minimumVerifyingDuration` has passed.
    @State private var visual: OTPStatus = .idle
    @State private var isAnimating = false
    @State private var sequence: Task<Void, Never>?
    @State private var generation = 0
    @State private var verifyStartedAt: Date?
    @State private var rejectedIncomplete = false

    private var controller: OTPFieldController { externalController ?? internalController }

    @Environment(\.otpFieldColors) private var colors

    private var style: OTPFieldStyle {
        (customStyle ?? (colorScheme == .dark ? .dark() : .light())).applying(colors)
    }

    public var body: some View {
        let style = style
        let layout = OTPLayout(length: length, style: style, maxWidth: availableWidth)
        let isLive = isAnimating || motion.isOrbiting

        TimelineView(.animation(paused: !isLive)) { timeline in
            // A paused timeline keeps its last date, which can be a hair before
            // the final value; `.now` guarantees the settled state.
            let frame = motion.frame(at: isLive ? timeline.date : .now, period: style.orbitPeriod)
            fieldContent(layout: layout, style: style, frame: frame)
                .frame(height: reservesOrbitSpace ? layout.size.height : growingHeight(layout, frame))
        }
        // `minWidth: 0` makes the frame take the offered width rather than the
        // content's, so a long code measures the screen and shrinks to fit.
        .frame(minWidth: 0, maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { availableWidth = $0 }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .environment(\.layoutDirection, .leftToRight) // a code reads LTR everywhere
        .sensoryFeedback(trigger: visual) { _, new in
            guard hapticFeedback else { return nil }
            switch new {
            case .success: return .success
            case .error: return .error
            default: return nil
            }
        }
        .onAppear {
            input = sanitized(controller.code)
            if autofocus { isFocused = true }
        }
        .onDisappear { sequence?.cancel() }
        .onChange(of: input) { _, new in handleInput(new) }
        .onChange(of: controller.code) { _, new in handleCode(new) }
        .onChange(of: controller.status) { _, new in handleStatus(new) }
    }

    // MARK: Rendering

    private func fieldContent(layout: OTPLayout, style: OTPFieldStyle, frame: OTPMotion.Frame) -> some View {
        let code = Array(controller.code)
        let shakeAmplitude = reduceMotion ? 0 : layout.boxSize * 0.16

        return ZStack {
            hiddenTextField
                .frame(width: layout.rowWidth, height: layout.boxSize)

            OTPOrbitCanvas(layout: layout, style: style, frame: frame)

            ForEach(0..<length, id: \.self) { index in
                let placement = frame.placement(of: index, layout: layout, shakeAmplitude: shakeAmplitude)
                OTPBox(
                    character: index < code.count ? String(obscuringCharacter ?? code[index]) : "",
                    visual: boxVisual(at: index, filled: code.count),
                    side: layout.boxSize,
                    fit: layout.fit,
                    style: style
                )
                .equatable()
                .scaleEffect(placement.scale)
                .offset(x: placement.center.x - layout.size.width / 2,
                        y: placement.center.y - layout.size.height / 2)
                .opacity(placement.opacity)
            }
            .accessibilityHidden(true)
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    /// The invisible text field that owns the keyboard, SMS autofill and paste.
    /// It ignores touches so the caret always stays at the end of the code.
    private var hiddenTextField: some View {
        TextField("", text: $input)
            .keyboardType(keyboardType)
            .textContentType(.oneTimeCode)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($isFocused)
            .foregroundStyle(.clear)
            .tint(.clear)
            .allowsHitTesting(false)
            .accessibilityLabel(labels.field)
            .accessibilityValue(controller.code)
    }

    private func growingHeight(_ layout: OTPLayout, _ frame: OTPMotion.Frame) -> CGFloat {
        layout.boxSize + (layout.size.height - layout.boxSize) * Ease.inOutCubic(frame.morph)
    }

    private func boxVisual(at index: Int, filled: Int) -> OTPBox.Visual {
        guard isEnabled else { return .disabled }
        switch visual {
        case .verifying: return .orbiting
        case .success: return .success
        case .error: return .error
        case .idle:
            if isFocused && index == min(filled, length - 1) {
                return index < filled ? .activeFilled : .active
            }
            return index < filled ? .filled : .empty
        }
    }

    // MARK: Input

    /// Keeps digits only (Arabic-Indic and other script digits become ASCII)
    /// and caps the code at `length`.
    private func sanitized(_ text: String) -> String {
        guard keyboardType == .numberPad || keyboardType == .asciiCapableNumberPad else {
            return String(text.prefix(length))
        }
        let digits = text.compactMap { $0.wholeNumberValue }.filter { (0...9).contains($0) }
        return String(digits.prefix(length).map { Character(String($0)) })
    }

    private func handleInput(_ new: String) {
        guard controller.status == .idle, isEnabled else {
            if input != controller.code { input = controller.code } // locked while busy
            return
        }
        let clean = sanitized(new)
        if clean != new { input = clean }
        if controller.code != clean { controller.code = clean }
    }

    private func handleCode(_ new: String) {
        let clean = sanitized(new)
        guard clean == new else { controller.code = clean; return }
        if input != clean { input = clean }
        onChanged?(clean)
        if clean.count == length, controller.status == .idle {
            onCompleted?(clean)
            if autoVerify, controller.status == .idle { controller.verify() }
        }
    }

    // MARK: Status sequences

    private func handleStatus(_ status: OTPStatus) {
        if status == .verifying, controller.code.count < length {
            // Nothing to verify yet: shake and keep what was typed.
            rejectedIncomplete = true
            controller.fail()
            return
        }
        onStatusChanged?(status)
        guard status == controller.status else { return } // callback changed it again

        sequence?.cancel()
        generation += 1
        let current = generation
        isAnimating = true
        sequence = Task { @MainActor in
            switch status {
            case .idle: await playIdle()
            case .verifying: await playVerifying()
            case .success: await playSuccess()
            case .error: await playError()
            }
            if generation == current { isAnimating = false }
        }
    }

    private func playVerifying() async {
        let code = controller.code
        visual = .verifying
        announce(labels.verifying)
        verifyStartedAt = .now
        motion.startOrbit()
        _ = motion.morph.animate(to: 1, duration: morphDuration)

        guard let onVerify else { return } // resolved later through the controller
        let verified = (try? await onVerify(code)) ?? false
        guard !Task.isCancelled else { return }
        verified ? controller.succeed() : controller.fail()
    }

    private func playSuccess() async {
        guard await waitForMinimumVerifying() else { return }
        if motion.morph.value() < 1 {
            // Resolved without a verifying phase: get onto the orbit first.
            visual = .verifying
            motion.startOrbit()
            guard await animate(\.morph, to: 1, duration: morphDuration) else { return }
        }
        visual = .success
        announce(labels.success)
        guard await animate(\.success, to: 1, duration: style.successDuration) else { return }
        motion.stopOrbit()
        isFocused = false
        onVerified?(controller.code)
    }

    private func playError() async {
        guard await waitForMinimumVerifying() else { return }
        visual = .error
        let incomplete = rejectedIncomplete
        rejectedIncomplete = false
        if !incomplete { announce(labels.error) }

        guard await animate(\.morph, to: 0, duration: morphDuration) else { return }
        motion.stopOrbit()
        motion.shake.jump(to: 0)
        guard await animate(\.shake, to: 1, duration: style.errorDuration) else { return }

        let code = controller.code
        controller.reset(clearCode: clearsOnError && !incomplete)
        if !incomplete { onFailed?(code) }
    }

    private func playIdle() async {
        visual = .idle
        verifyStartedAt = nil
        let settle = max(
            motion.success.animate(to: 0, duration: style.successDuration),
            motion.morph.animate(to: 0, duration: morphDuration)
        )
        guard await sleep(settle) else { return }
        motion.stopOrbit()
        motion.shake.jump(to: 0)
    }

    private var morphDuration: TimeInterval {
        reduceMotion ? 0 : style.morphDuration
    }

    private func waitForMinimumVerifying() async -> Bool {
        guard let start = verifyStartedAt else { return !Task.isCancelled }
        return await sleep(minimumVerifyingDuration - Date.now.timeIntervalSince(start))
    }

    private func animate(
        _ tween: WritableKeyPath<OTPMotion, OTPMotion.Tween>,
        to target: Double,
        duration: TimeInterval
    ) async -> Bool {
        await sleep(motion[keyPath: tween].animate(to: target, duration: duration))
    }

    /// Sleeps and reports whether this sequence is still the current one.
    private func sleep(_ seconds: TimeInterval) async -> Bool {
        if seconds > 0 { try? await Task.sleep(for: .seconds(seconds)) }
        return !Task.isCancelled
    }

    private func announce(_ message: String) {
        guard !message.isEmpty else { return }
        AccessibilityNotification.Announcement(message).post()
    }
}

// MARK: - Motion (time-based animation state)

/// All field animations as tweens of time, like Flutter's `AnimationController`s.
/// Values are linear 0...1; curves are applied when a frame is resolved.
struct OTPMotion {
    struct Tween {
        private var from: Double = 0
        private var to: Double = 0
        private var start: Date = .distantPast
        private var duration: TimeInterval = 0

        func value(at date: Date = .now) -> Double {
            guard duration > 0 else { return to }
            let progress = min(max(date.timeIntervalSince(start) / duration, 0), 1)
            return from + (to - from) * progress
        }

        /// Retargets from the current value. A full 0 -> 1 run takes `duration`;
        /// shorter distances take proportionally less. Returns the time needed.
        @discardableResult
        mutating func animate(to target: Double, duration full: TimeInterval) -> TimeInterval {
            let now = Date.now
            from = value(at: now)
            to = target
            start = now
            duration = full * abs(target - from)
            return duration
        }

        mutating func jump(to target: Double) {
            from = target
            to = target
            duration = 0
        }
    }

    /// One resolved animation frame.
    struct Frame {
        var morph: Double
        var turns: Double
        var shake: Double
        var success: Double

        /// How far the boxes have collapsed into the success badge.
        var convergence: Double { Ease.inCubic(Ease.interval(success, 0, 0.45)) }

        /// Horizontal error shake as a fraction of its amplitude, decaying to 0.
        /// The shake uses the first 60% of the error animation; the rest is a
        /// pause that keeps the error color readable.
        var shakeOffset: Double {
            let t = Ease.interval(shake, 0, 0.6)
            return sin(t * 3 * 2 * .pi) * (1 - t)
        }

        /// Progress of box `index` from row to orbit; boxes leave one by one.
        func travel(_ index: Int, of length: Int) -> Double {
            let delay = length > 1 ? min(0.08, 0.3 / Double(length - 1)) : 0
            let window = 1 - delay * Double(length - 1)
            return Ease.inOutCubic((morph - delay * Double(index)) / window)
        }

        func placement(of index: Int, layout: OTPLayout, shakeAmplitude: CGFloat) -> OTPBoxPlacement {
            let convergence = convergence
            let t = travel(index, of: layout.length)
            let onOrbit = layout.orbitCenter(index, turns: turns, radiusFactor: 1 - convergence)
            var inRow = layout.rowCenter(index)
            inRow.x += shakeOffset * shakeAmplitude
            return OTPBoxPlacement(
                center: CGPoint(x: inRow.x + (onOrbit.x - inRow.x) * t,
                                y: inRow.y + (onOrbit.y - inRow.y) * t),
                scale: (1 + (layout.orbitBoxScale - 1) * t) * (1 - 0.7 * convergence),
                opacity: 1 - convergence
            )
        }
    }

    var morph = Tween()
    var shake = Tween()
    var success = Tween()
    private var orbitStart: Date?

    var isOrbiting: Bool { orbitStart != nil }

    mutating func startOrbit() {
        if orbitStart == nil { orbitStart = .now }
    }

    mutating func stopOrbit() {
        orbitStart = nil
    }

    func frame(at date: Date, period: TimeInterval) -> Frame {
        let turns = orbitStart.map { date.timeIntervalSince($0) / period } ?? 0
        return Frame(
            morph: morph.value(at: date),
            turns: turns.truncatingRemainder(dividingBy: 1),
            shake: shake.value(at: date),
            success: success.value(at: date)
        )
    }
}

struct OTPBoxPlacement {
    var center: CGPoint
    var scale: CGFloat
    var opacity: Double
}

// MARK: - Layout

/// Sizes and positions for one width. Row and orbit share the same center.
struct OTPLayout {
    let length: Int
    /// Scale applied to themed sizes so the row fits; 1 means no shrinking.
    let fit: CGFloat
    let boxSize: CGFloat
    let gap: CGFloat
    let orbitBoxScale: CGFloat
    let orbitRadius: CGFloat
    let size: CGSize

    /// How far past the orbit radius drawing reaches, in orbit box sizes:
    /// half a box diagonal plus room for the glow.
    private static let extentFactor: CGFloat = 0.75

    init(length: Int, style: OTPFieldStyle, maxWidth: CGFloat) {
        let n = CGFloat(length)
        let naturalRowWidth = n * style.boxSize + (n - 1) * style.gap
        let bounded = maxWidth.isFinite && maxWidth > 0
        let fit = bounded && maxWidth < naturalRowWidth ? maxWidth / naturalRowWidth : 1
        let boxSize = style.boxSize * fit
        let orbitBoxSize = boxSize * style.orbitBoxScale

        // Neighbours on the orbit stay 1.5 boxes apart, so longer codes get a
        // wider circle instead of colliding.
        let spacingRadius = length >= 3 ? orbitBoxSize * 1.5 / (2 * sin(.pi / n)) : 0
        var radius = style.orbitRadius ?? max(boxSize * 0.83, spacingRadius)
        if bounded {
            radius = max(0, min(radius, maxWidth / 2 - orbitBoxSize * Self.extentFactor))
        }

        let orbitExtent = 2 * (radius + orbitBoxSize * Self.extentFactor)
        let rowWidth = n * boxSize + (n - 1) * style.gap * fit

        self.length = length
        self.fit = fit
        self.boxSize = boxSize
        self.gap = style.gap * fit
        self.orbitBoxScale = style.orbitBoxScale
        self.orbitRadius = radius
        self.size = CGSize(width: max(rowWidth, orbitExtent), height: max(boxSize, orbitExtent))
    }

    var rowWidth: CGFloat { CGFloat(length) * boxSize + CGFloat(length - 1) * gap }
    var orbitBoxSize: CGFloat { boxSize * orbitBoxScale }
    var innerRingRadius: CGFloat { orbitRadius + orbitBoxSize * 0.19 }
    var outerRingRadius: CGFloat { orbitRadius + orbitBoxSize * 0.62 }
    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

    func rowCenter(_ index: Int) -> CGPoint {
        let left = (size.width - rowWidth) / 2
        return CGPoint(x: left + CGFloat(index) * (boxSize + gap) + boxSize / 2, y: size.height / 2)
    }

    /// The row wraps over the top of the circle, so digits read clockwise and
    /// the first and last boxes travel symmetric paths.
    func orbitCenter(_ index: Int, turns: Double, radiusFactor: Double) -> CGPoint {
        let step = 2 * Double.pi / Double(length)
        let angle = -Double.pi / 2 + (Double(index) - Double(length - 1) / 2) * step + turns * 2 * .pi
        let r = orbitRadius * radiusFactor
        return CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
    }
}

// MARK: - Box

private struct OTPBox: View, Equatable {
    enum Visual: Equatable {
        case empty, active, activeFilled, filled, orbiting, error, success, disabled
    }

    let character: String
    let visual: Visual
    let side: CGFloat
    let fit: CGFloat
    let style: OTPFieldStyle

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius * fit, style: .continuous)
        let look = look

        shape.fill(style.fillColor)
            // The orbit's lit corner.
            .overlay {
                shape.fill(RadialGradient(
                    colors: [style.accentColor.opacity(0.8), style.accentColor.opacity(0)],
                    center: .topTrailing, startRadius: 0, endRadius: side * 0.77
                ))
                .opacity(visual == .orbiting ? 1 : 0)
            }
            .overlay { shape.strokeBorder(look.border, lineWidth: style.borderWidth) }
            .shadow(color: look.glow, radius: look.glowRadius / 2)
            .overlay { content }
            .frame(width: side, height: side)
            .animation(.easeOut(duration: style.styleDuration), value: visual)
    }

    private var content: some View {
        ZStack {
            if !character.isEmpty {
                Text(character)
                    .font(.system(size: style.fontSize * fit, weight: style.fontWeight, design: style.fontDesign))
                    .foregroundStyle(visual == .disabled ? style.textColor.opacity(0.4) : style.textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .padding(side * 0.14)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else if visual == .active {
                Capsule()
                    .fill(style.cursorColor ?? style.textColor)
                    .frame(width: 2, height: side * 0.4)
                    .phaseAnimator([1.0, 0.0]) { cursor, opacity in
                        cursor.opacity(opacity)
                    } animation: { _ in .easeInOut(duration: 0.5) }
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.2, bounce: 0.35), value: character)
    }

    private var look: (border: Color, glow: Color, glowRadius: CGFloat) {
        let blur = style.glowRadius
        switch visual {
        case .empty, .filled:
            return (style.borderColor, style.accentColor.opacity(0), 0)
        case .active, .activeFilled:
            return (style.accentColor, style.accentColor.opacity(0.45), blur)
        case .orbiting:
            return (style.accentColor, style.accentColor.opacity(0.25), blur * 0.7)
        case .error:
            return (style.errorColor, style.errorColor.opacity(0.4), blur)
        case .success:
            return (style.successColor, style.successColor.opacity(0.35), blur)
        case .disabled:
            return (style.borderColor.opacity(0.5), style.accentColor.opacity(0), 0)
        }
    }
}

// MARK: - Orbit rings & success badge

private struct OTPOrbitCanvas: View {
    let layout: OTPLayout
    let style: OTPFieldStyle
    let frame: OTPMotion.Frame

    /// Arc length between two dots of the outer ring, in points.
    private static let dotSpacing: CGFloat = 7

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let appear = Ease.outCubic(Ease.interval(frame.morph, 0.35, 1))
            let ringsOut = Ease.inCubic(Ease.interval(frame.success, 0, 0.45))
            let ringsOpacity = appear * (1 - ringsOut)

            if ringsOpacity > 0 {
                // Grows from 60% as it appears, shrinks to 55% as success takes over.
                let scale = (0.6 + 0.4 * appear) * (1 - 0.45 * ringsOut)
                drawRings(in: &context, center: center, scale: scale, opacity: ringsOpacity)
            }
            if frame.success > 0 {
                drawBadge(in: &context, center: center)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawRings(in context: inout GraphicsContext, center: CGPoint, scale: CGFloat, opacity: Double) {
        let inner = layout.innerRingRadius * scale
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2)),
            with: .color(style.ringColor.opacity(opacity)),
            lineWidth: 1
        )

        let outer = layout.outerRingRadius * scale
        let count = max(12, Int((2 * .pi * outer / Self.dotSpacing).rounded()))
        var dots = Path()
        for i in 0..<count {
            let angle = Double(i) * 2 * .pi / Double(count)
            let x = center.x + cos(angle) * outer
            let y = center.y + sin(angle) * outer
            dots.addEllipse(in: CGRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8))
        }
        // The sweep turns against the boxes; its bright seam reads as a comet head.
        context.fill(dots, with: .conicGradient(
            Gradient(colors: [style.accentColor.opacity(0.1 * opacity), style.accentColor.opacity(opacity)]),
            center: center,
            angle: .radians(-frame.turns * 2 * .pi)
        ))
    }

    private func drawBadge(in context: inout GraphicsContext, center: CGPoint) {
        let radius = layout.innerRingRadius * 0.7 * Ease.outBack(Ease.interval(frame.success, 0.3, 0.75))
        guard radius > 0 else { return }

        let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                            width: radius * 2, height: radius * 2))
        context.fill(circle, with: .color(style.successColor.opacity(0.16)))
        context.stroke(circle, with: .color(style.successColor), lineWidth: 2)

        let drawn = Ease.outCubic(Ease.interval(frame.success, 0.55, 1))
        guard drawn > 0 else { return }
        var check = Path()
        check.move(to: CGPoint(x: center.x - radius * 0.42, y: center.y + radius * 0.02))
        check.addLine(to: CGPoint(x: center.x - radius * 0.12, y: center.y + radius * 0.32))
        check.addLine(to: CGPoint(x: center.x + radius * 0.45, y: center.y - radius * 0.3))
        context.stroke(
            check.trimmedPath(from: 0, to: drawn),
            with: .color(style.successColor),
            style: StrokeStyle(lineWidth: max(2, radius * 0.13), lineCap: .round, lineJoin: .round)
        )
    }
}

// MARK: - Helpers

private enum Ease {
    /// Maps `t` from `begin...end` to 0...1, clamped.
    static func interval(_ t: Double, _ begin: Double, _ end: Double) -> Double {
        min(max((t - begin) / (end - begin), 0), 1)
    }

    static func inCubic(_ t: Double) -> Double { t * t * t }

    static func outCubic(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

    static func inOutCubic(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    static func outBack(_ t: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Preview

#Preview("Verify with a future") {
    struct Demo: View {
        @State private var otp = OTPFieldController()
        @State private var isVerified = false

        var body: some View {
            VStack(spacing: 32) {
                Text(isVerified ? "Verified" : "Enter 1234")
                    .font(.title2.bold())

                OTPAnimatedField(
                    length: 4,
                    controller: otp,
                    autofocus: true,
                    onVerify: { code in
                        try await Task.sleep(for: .seconds(2.5)) // simulated backend
                        return code == "1234"
                    },
                    onVerified: { _ in isVerified = true }
                )
                .otpFieldColors(accent: .blue, success: .mint)

                Button("Reset") {
                    otp.reset()
                    isVerified = false
                }
            }
            .padding(20)
        }
    }
    return Demo()
}
