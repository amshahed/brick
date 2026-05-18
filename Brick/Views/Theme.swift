import SwiftUI
import UIKit

/// Centralised design tokens. Anything aesthetic — color, type, radius,
/// spacing — should resolve through here so the look stays coherent.
///
/// Direction: refined industrial. Warm-grounded neutrals + a single brick-
/// clay accent. SF Pro Rounded for display, SF Mono for stats. No
/// purple/cyan gradients, no glass, minimal shadow. Whitespace and
/// type hierarchy do the heavy lifting.
enum Theme {
    // MARK: Color

    /// Single brand accent — referencing brick clay without being literal.
    static let accent = Color(red: 0.722, green: 0.361, blue: 0.220)

    /// A muted version of the accent for low-emphasis tints (icon strokes,
    /// faint backdrops behind active states).
    static let accentMuted = Color(red: 0.722, green: 0.361, blue: 0.220).opacity(0.12)

    /// Card surface — picks up a faint warmth so cards don't read as cold
    /// flat secondary fill.
    static let cardSurface = Color(.secondarySystemGroupedBackground)

    /// Hairline used on cards. Keeps the edge readable on both light and
    /// dark modes without resorting to a heavy shadow.
    static let hairline = Color.primary.opacity(0.06)

    /// Page background when we want a tint warmer than systemBackground.
    /// Uses a custom asset-equivalent built on the fly.
    static var canvas: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    // MARK: Radius

    enum Radius {
        static let card: CGFloat = 22
        static let chip: CGFloat = 12
        static let button: CGFloat = 14
    }

    // MARK: Spacing — vertical rhythm

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 36
    }

    // MARK: Type

    /// Display: warm, rounded, used for hero numbers and big screen titles.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Stat readout: monospaced digits for any time / count value so the
    /// number stops jittering as digits change width.
    static func statNumber(_ size: CGFloat = 32, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Small caps label that sits over a stat or section. Tracks slightly
    /// wider for readability at small sizes.
    static let label: Font = .system(size: 11, weight: .medium, design: .rounded)
}

// MARK: - Card surface modifier

private struct CardSurface: ViewModifier {
    var padding: CGFloat = Theme.Space.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.cardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    /// Wraps the view in a Theme-styled card surface. Use this instead of
    /// re-rolling rounded-rect backgrounds inline.
    func cardSurface(padding: CGFloat = Theme.Space.lg) -> some View {
        modifier(CardSurface(padding: padding))
    }
}

// MARK: - Stat block

/// Standardised stat block: a big monospaced number stacked over a small
/// caps label. Used in StatsCard and anywhere we need a quick numeric callout.
struct StatBlock: View {
    let value: String
    let label: String
    var alignment: HorizontalAlignment = .leading
    var numberSize: CGFloat = 28

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(value)
                .font(Theme.statNumber(numberSize))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(Theme.label)
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }
}

// MARK: - Section header

/// Small caps section header, used in place of a default Section title when
/// we want it to sit outside a Form (e.g. above a card stack).
struct SectionEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.label)
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }
}

// MARK: - Primary button style

/// Brick's signature primary CTA — clay-fill, rounded, with a quiet
/// press-down spring. Use for the most important action on a screen
/// (Block Now, Take a break, etc.). At most one per surface.
struct BrickPrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.display(17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 14)
            .padding(.horizontal, 22)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.accent)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BrickPrimaryButtonStyle {
    static var brickPrimary: BrickPrimaryButtonStyle { .init() }
}

/// Quieter sibling — outline only. Use for the secondary action on a
/// screen, never alone.
struct BrickSecondaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.display(17, weight: .medium))
            .foregroundStyle(.primary)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 13)
            .padding(.horizontal, 22)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BrickSecondaryButtonStyle {
    static var brickSecondary: BrickSecondaryButtonStyle { .init() }
}

// MARK: - Empty state

/// House-style empty state. Replaces the generic ContentUnavailableView so
/// the same eyebrow → big rounded headline → muted body → CTA pattern shows
/// up everywhere a list is empty. Editorial layout, left-aligned.
struct BrickEmptyState: View {
    let eyebrow: String
    let title: String
    let copy: String
    var primaryActionLabel: String? = nil
    var primaryAction: (() -> Void)? = nil
    var secondaryActionLabel: String? = nil
    var secondaryAction: (() -> Void)? = nil

    init(
        eyebrow: String,
        title: String,
        body: String,
        primaryActionLabel: String? = nil,
        primaryAction: (() -> Void)? = nil,
        secondaryActionLabel: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.copy = body
        self.primaryActionLabel = primaryActionLabel
        self.primaryAction = primaryAction
        self.secondaryActionLabel = secondaryActionLabel
        self.secondaryAction = secondaryAction
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionEyebrow(text: eyebrow)
                    Text(title)
                        .font(Theme.display(30, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineSpacing(-2)
                    Text(copy)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, Theme.Space.xs)
                }
                if primaryActionLabel != nil || secondaryActionLabel != nil {
                    VStack(spacing: Theme.Space.sm) {
                        if let primaryActionLabel, let primaryAction {
                            Button(primaryActionLabel, action: primaryAction)
                                .buttonStyle(.brickPrimary)
                        }
                        if let secondaryActionLabel, let secondaryAction {
                            Button(secondaryActionLabel, action: secondaryAction)
                                .buttonStyle(.brickSecondary)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Screen header

/// Branded screen header — replaces the system `navigationTitle` at the
/// top of each tab so the four tab roots feel coherent and tie back to
/// the brick mark + clay palette.
///
/// Composition: leading 44pt slot (an `IconPlate` SF Symbol on most tabs,
/// `AppIconMark` clipped to a rounded square on Home), title in the
/// rounded display face, optional small-caps subtitle, optional trailing
/// accessory (the `+` button on Blocklists / Schedules).
struct BrickHeader<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.md) {
            leading()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.display(28, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle.uppercased())
                        .font(Theme.label)
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Space.sm)
            trailing()
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.top, Theme.Space.md)
        .padding(.bottom, Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Stat tile

/// Single cell of the home stats grid. Icon-plate top-left, monospaced
/// value, small-caps label. Wrapped in `cardSurface()` so a 2×2 grid of
/// tiles reads as a single coherent band.
struct StatTile: View {
    let symbol: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            IconPlate(symbol: symbol, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(Theme.statNumber(24, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label.uppercased())
                    .font(Theme.label)
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .cardSurface(padding: Theme.Space.md)
    }
}

// MARK: - Icon plate

/// Clay-tinted rounded square holding an SF Symbol. Replaces the ad-hoc
/// `ZStack { RoundedRectangle + Image }` pattern that was duplicated across
/// onboarding, blocklist rows, travel banner, and the focus nudge card.
struct IconPlate: View {
    let symbol: String
    var size: CGFloat = 56
    var symbolSize: CGFloat? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(Theme.accentMuted)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: symbolSize ?? size * 0.42, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            )
    }
}

// MARK: - Countdown ring

/// Circular progress ring that drains from full to empty over [start, end].
/// Driven by `TimelineView(.periodic)` so it ticks reliably across SwiftUI
/// rebuilds (same rationale as #25). Respects `reduceMotion` by skipping the
/// implicit fraction animation.
struct CountdownRing<Inner: View>: View {
    let start: Date
    let end: Date
    var lineWidth: CGFloat = 8
    var trackOpacity: Double = 0.08
    @ViewBuilder var inner: () -> Inner

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            let remaining = max(0, end.timeIntervalSince(context.date))
            let total = max(1, end.timeIntervalSince(start))
            let fraction = min(1, max(0, remaining / total))
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(trackOpacity), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        Theme.accent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 0.9), value: fraction)
                inner()
            }
        }
    }
}

// MARK: - Onboarding step

/// Shared layout for the multi-step onboarding flow. Editorial top-aligned
/// typography (eyebrow → big display title → body → optional inline accent
/// icon), then `content` for any step-specific controls, then a CTA stack
/// pinned to the bottom. Keeps the visual rhythm consistent across steps
/// without forcing each step to re-implement the same VStack shape.
///
/// Two new knobs unlock the hero variant used on the first-launch flow:
/// - `heroIconSize` (default 56, hero screens pass 96)
/// - `alignment` — `.leading` for list / form steps, `.center` for title-card
///   screens (welcome, permission, slideshow, done)
/// On first appear the icon plate / hero view scales-and-fades in, gated on
/// `accessibilityReduceMotion`. The headline gets the same entrance with a
/// 120 ms delay so the eye reads icon→title in sequence.
struct OnboardingStep<Content: View>: View {
    let eyebrow: String
    let title: String
    let copy: String?
    var icon: String? = nil
    var customHero: AnyView? = nil
    var heroIconSize: CGFloat = 56
    var alignment: HorizontalAlignment = .leading
    var titleSize: CGFloat = 30
    var errorText: String? = nil
    var primaryLabel: String? = nil
    var primaryAction: (() -> Void)? = nil
    var primaryDisabled: Bool = false
    var secondaryLabel: String? = nil
    var secondaryAction: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var heroAppeared = false
    @State private var titleAppeared = false

    init(
        eyebrow: String,
        title: String,
        body: String? = nil,
        icon: String? = nil,
        customHero: AnyView? = nil,
        heroIconSize: CGFloat = 56,
        alignment: HorizontalAlignment = .leading,
        titleSize: CGFloat = 30,
        errorText: String? = nil,
        primaryLabel: String? = nil,
        primaryAction: (() -> Void)? = nil,
        primaryDisabled: Bool = false,
        secondaryLabel: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content = { EmptyView() }
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.copy = body
        self.icon = icon
        self.customHero = customHero
        self.heroIconSize = heroIconSize
        self.alignment = alignment
        self.titleSize = titleSize
        self.errorText = errorText
        self.primaryLabel = primaryLabel
        self.primaryAction = primaryAction
        self.primaryDisabled = primaryDisabled
        self.secondaryLabel = secondaryLabel
        self.secondaryAction = secondaryAction
        self.content = content
    }

    private var textAlignment: TextAlignment {
        alignment == .center ? .center : .leading
    }

    private var frameAlignment: Alignment {
        alignment == .center ? .center : .leading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: alignment, spacing: Theme.Space.xl) {
                    if let customHero {
                        customHero
                            .scaleEffect(heroAppeared ? 1 : 0.88)
                            .opacity(heroAppeared ? 1 : 0)
                    } else if let icon {
                        IconPlate(symbol: icon, size: heroIconSize)
                            .scaleEffect(heroAppeared ? 1 : 0.85)
                            .opacity(heroAppeared ? 1 : 0)
                    }
                    VStack(alignment: alignment, spacing: Theme.Space.sm) {
                        SectionEyebrow(text: eyebrow)
                        Text(title)
                            .font(Theme.display(titleSize, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineSpacing(-2)
                            .multilineTextAlignment(textAlignment)
                        if let copy {
                            Text(copy)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.top, Theme.Space.xs)
                                .multilineTextAlignment(textAlignment)
                        }
                    }
                    .opacity(titleAppeared ? 1 : 0)
                    .offset(y: titleAppeared ? 0 : 8)
                    content()
                    if let errorText {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(textAlignment)
                    }
                }
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.lg)
            }
            if primaryLabel != nil || secondaryLabel != nil {
                VStack(spacing: Theme.Space.sm) {
                    if let primaryLabel, let primaryAction {
                        Button(primaryLabel, action: primaryAction)
                            .buttonStyle(.brickPrimary)
                            .opacity(primaryDisabled ? 0.4 : 1)
                            .disabled(primaryDisabled)
                    }
                    if let secondaryLabel, let secondaryAction {
                        Button(secondaryLabel, action: secondaryAction)
                            .buttonStyle(.brickSecondary)
                    }
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.md)
                .padding(.bottom, Theme.Space.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas.ignoresSafeArea())
        .onAppear(perform: playEntrance)
    }

    private func playEntrance() {
        guard !reduceMotion else {
            heroAppeared = true
            titleAppeared = true
            return
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            heroAppeared = true
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82).delay(0.12)) {
            titleAppeared = true
        }
    }
}

// MARK: - Brick hero logo

/// `AppIconMark` clipped to a continuous-radius square with a soft drop
/// shadow, sized large for the welcome / done screens. Same primitive as
/// the launcher icon, so the brand is literally the same mark wherever
/// it appears.
struct BrickHeroLogo: View {
    var size: CGFloat = 144

    var body: some View {
        AppIconMark(size: size)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Passcode dots field

/// Six-dot passcode field. A real `TextField` sits behind the dots (zero
/// opacity, custom keyboard, takes focus on tap). Dots fill in clay as
/// the user types. When the parent flips `errorTrigger`, the row shakes
/// laterally for ~250 ms — same UX cue the system passcode field uses
/// for a bad entry.
struct PasscodeDotsField: View {
    @Binding var value: String
    var errorTrigger: Int
    var maxLength: Int = 6

    @FocusState private var focused: Bool
    @State private var shake: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Hidden real input. `.opacity(0)` keeps it accessible and
            // hit-testable; `.frame(height: 1)` collapses its visual
            // footprint without removing it from the responder chain.
            TextField("", text: $value)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .opacity(0.001)
                .frame(height: 1)
                .onChange(of: value) { _, new in
                    let sanitized = String(new.filter { $0.isNumber }.prefix(maxLength))
                    if sanitized != new { value = sanitized }
                }
            HStack(spacing: Theme.Space.md) {
                ForEach(0..<maxLength, id: \.self) { i in
                    Circle()
                        .fill(i < value.count ? Theme.accent : Color.primary.opacity(0.08))
                        .frame(width: 16, height: 16)
                        .animation(.easeOut(duration: 0.18), value: value.count)
                }
            }
            .allowsHitTesting(false)
        }
        .padding(.vertical, Theme.Space.lg)
        .padding(.horizontal, Theme.Space.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .modifier(ShakeEffect(animatableData: shake))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { focused = true }
        .onChange(of: errorTrigger) { _, _ in
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.32)) { shake += 1 }
        }
    }
}

/// Lateral wobble used by `PasscodeDotsField` for incorrect-entry feedback.
/// 3 cycles of a sine wave, ~8pt amplitude. `animatableData` is the cycle
/// count — increment to play, SwiftUI tweens the rest.
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(
                translationX: amount * sin(animatableData * .pi * shakesPerUnit),
                y: 0
            )
        )
    }
}
