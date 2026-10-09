import SwiftUI

/// Everything that lives in the corner of the screen: the camera while printing, and the pile.
struct DeskView: View {
    let model: DeskModel
    @Namespace private var namespace

    var body: some View {
        VStack(alignment: model.corner.horizontal, spacing: 0) {
            Spacer(minLength: 0)
            if model.cameraInPanel {
                PrintStation(model: model, namespace: namespace)
                    .frame(width: Layout.stationSize.width, height: Layout.stationSize.height)
                    .padding(model.corner.edge, Layout.edgeInset + (Layout.cardWidth - Layout.stationSize.width) / 2)
            }
            PileView(model: model, namespace: namespace)
                .frame(height: model.expandedInPanel ? Layout.fanHeight
                    : model.panelLayout.tucked ? Layout.tuckedSize.height : Layout.pileSize.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.corner.alignment)
    }
}

struct PrintStation: View {
    let model: DeskModel
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !model.cameraShown || reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                CameraView(flash: model.flash, gaze: reduceMotion ? .zero : model.lensGaze())
                    .offset(x: model.motorRunning ? sin(t * 251) * 0.25 : 0, y: model.motorRunning ? cos(t * 317) * 0.2 : 0)
            }
                .scaleEffect(x: model.cameraHop ? 1.03 : 1, y: model.cameraHop ? 0.96 : 1, anchor: .bottom)
                .offset(y: model.cameraHop ? -6 : 0)
                .scaleEffect(model.cameraShown ? 1 : 0.82, anchor: .bottom)
                .rotationEffect(.degrees(model.flash * -2.5), anchor: .bottom)
                .offset(y: (model.cameraShown ? 0 : 50) - model.flash * 3)
                .opacity(model.cameraShown ? 1 : 0)
                .padding(.top, Layout.cameraTop)

            // Drawn over the camera so the print slides out in front of the slot's lower lip.
            if model.printing != nil, let sheet = model.feedSheet {
                CurlingPrint(sheet: sheet, progress: model.eject, relax: model.relax)
                    .padding(.top, Layout.slotY)
                    .allowsHitTesting(false)
            } else if let shot = model.printing {
                TimelineView(.animation) { context in
                    PolaroidView(shot: shot, develop: model.developProgress(at: context.date))
                }
                .matchedGeometryEffect(id: shot.id, in: namespace)
                .rotationEffect(.degrees(model.wiggle), anchor: .top)
                .frame(width: Layout.cardWidth, height: Layout.cardHeight, alignment: .top)
                .padding(.top, Layout.slotY)
                .onDrag { model.dragProvider(for: shot) }
                .help(Text("Wiggle the pointer to develop faster, or drag it out right away."))
            }

            if model.hintVisible {
                Label("Wiggle to develop", systemImage: "hand.wave.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    .padding(.top, Layout.slotY + Layout.photoHeight - 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .allowsHitTesting(false)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct PileView: View {
    let model: DeskModel
    let namespace: Namespace.ID

    var body: some View {
        let items = model.visibleShots
        let trailing = model.corner.isTrailing
        ZStack(alignment: model.corner.alignment) {
            // Once the panel has shrunk to the count pill, the hidden cards must not take up room.
            if !model.panelLayout.tucked {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, shot in
                    PileCard(shot: shot, model: model, namespace: namespace, index: index,
                             expanded: model.pileExpanded, trailing: trailing)
                        .zIndex(model.hoveredShot == shot.id && model.pileExpanded ? 100 : Double(items.count - index))
                }
            }
        }
        .scaleEffect(model.tucked ? 0.35 : 1, anchor: model.corner.isTrailing ? .bottomTrailing : .bottomLeading)
        .offset(y: model.tucked ? 30 : 0)
        .opacity(model.tucked ? 0 : 1)
        .allowsHitTesting(!model.tucked)
        .padding(model.corner.edge, Layout.edgeInset)
        .padding(.bottom, Layout.pileBottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.corner.alignment)
        .overlay(alignment: model.corner.alignment) {
            footer(hasItems: !items.isEmpty)
                .fixedSize()
                .frame(width: Layout.cardWidth)
                .padding(model.corner.edge, Layout.edgeInset)
                .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private func footer(hasItems: Bool) -> some View {
        if let toast = model.toast {
            Label(toast.title, systemImage: toast.symbol)
                .symbolEffect(.bounce, value: toast)
                .foregroundStyle(.primary)
                .pill()
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white, .green)
                        .offset(x: 5, y: -5)
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
        } else if model.sweptCount > 0 {
            Button(action: model.undoClear) {
                HStack(spacing: 6) {
                    Image(systemName: "wind")
                    Text("Swept \(model.sweptCount)")
                        .foregroundStyle(.secondary)
                    Text("Undo")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .buttonStyle(PillButtonStyle())
            .help(Text("Put the prints back on the pile."))
            .transition(.scale(scale: 0.7).combined(with: .opacity))
        } else if hasItems, !model.sweeping {
            HStack(spacing: 6) {
                Label {
                    Text("\(model.todayCount) today")
                } icon: {
                    Image(systemName: "photo.stack")
                }
                .foregroundStyle(.secondary)
                .pill()
                .accessibilityLabel(Text("\(model.todayCount) screenshots today"))
                .accessibilityAction(named: Text("Show Pile")) { model.showPile() }

                if model.pointerInside, model.canSweep {
                    Button(action: model.clearPile) {
                        Label("Sweep", systemImage: "wind")
                            .symbolEffect(.bounce, value: model.pointerInside)
                    }
                    .buttonStyle(PillButtonStyle())
                    .help(Text("Sweep the pile away. Your screenshots stay in their folder."))
                    .accessibilityLabel(Text("Sweep the pile"))
                    .transition(.scale(scale: 0.6, anchor: model.corner.isTrailing ? .leading : .trailing)
                        .combined(with: .opacity))
                }
            }
            .transition(.opacity)
        }
    }
}

/// Quick actions that float over the lifted print, so nothing needs a right-click.
private struct CardActions: View {
    let shot: Shot
    let model: DeskModel

    var body: some View {
        HStack(spacing: 0) {
            action("doc.on.doc", "Copy Picture") { model.copy(shot) }
            action("text.viewfinder", "Copy Text") { model.copyText(shot) }
                .disabled(shot.text?.isEmpty ?? true)
            action("arrow.up.forward.app", "Open") { model.open(shot) }
            action("folder", "Show in Finder") { model.reveal(shot) }
        }
        .padding(2)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
        .environment(\.colorScheme, .dark)
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }

    private func action(_ symbol: String, _ title: LocalizedStringKey, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(CardActionStyle())
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }
}

private struct CardActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(isEnabled ? 0.95 : 0.35))
            .background(.white.opacity(configuration.isPressed ? 0.22 : 0), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.5), value: configuration.isPressed)
    }
}

private struct Pill: ViewModifier {
    var pressed = false

    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(height: Layout.badgeHeight)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(pressed ? 0.06 : 0.12), radius: pressed ? 3 : 6, y: pressed ? 1 : 2)
            .scaleEffect(pressed ? 0.92 : 1)
    }
}

private extension View {
    func pill(pressed: Bool = false) -> some View { modifier(Pill(pressed: pressed)) }
}

private struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pill(pressed: configuration.isPressed)
            .contentShape(Capsule())
            .animation(.spring(duration: 0.2, bounce: 0.4), value: configuration.isPressed)
    }
}

struct PileCard: View {
    let shot: Shot
    let model: DeskModel
    let namespace: Namespace.ID
    let index: Int
    let expanded: Bool
    let trailing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var hovering: Bool { model.hoveredShot == shot.id }

    var body: some View {
        let sign: CGFloat = trailing ? -1 : 1
        let fanAngle = Layout.fanAngle(index: index, trailing: trailing)
        let toss = model.tossed.contains(shot.id) && !reduceMotion
        let featured = hovering && expanded
        PolaroidView(shot: shot, lifted: featured, sheen: featured ? model.sheen : nil)
            .overlay(alignment: .top) {
                if featured, !model.sweeping {
                    CardActions(shot: shot, model: model)
                        .padding(.top, Layout.cardInset + Layout.photoHeight - 32)
                        .transition(.scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
                }
            }
            .rotation3DEffect(.degrees(featured && !reduceMotion ? (model.sheen - 0.5) * 16 : 0),
                              axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .matchedGeometryEffect(id: shot.id, in: namespace)
            .scaleEffect(hovering && expanded ? Layout.fanHoverScale : 1, anchor: .bottom)
            .rotationEffect(.degrees(expanded ? fanAngle : shot.tilt), anchor: .bottom)
            .offset(x: expanded ? sign * CGFloat(index) * Layout.fanStep : shot.nudge.width,
                    y: expanded ? (hovering ? -Layout.fanLift : 0) - CGFloat(index) * 4 : shot.nudge.height - CGFloat(index) * 2)
            .opacity(expanded || index < 4 ? 1 : 0)
            // Flicked off the pile toward the screen edge, each card at its own angle.
            .rotationEffect(.degrees(toss ? Double(-sign) * (34 + Double(index % 3) * 10) : 0), anchor: .bottom)
            .offset(x: toss ? -sign * (Layout.cardWidth + 110 + CGFloat(index) * 16) : 0,
                    y: toss ? 60 + CGFloat(index % 2) * 34 : 0)
            .opacity(model.tossed.contains(shot.id) ? 0 : 1)
            .allowsHitTesting(!model.sweeping)
            .onDrag {
                model.dragProvider(for: shot)
            } preview: {
                PolaroidView(shot: shot, lifted: true).rotationEffect(.degrees(-3))
            }
            .onTapGesture(count: 2) { model.open(shot) }
            .contextMenu {
                Button("Open") { model.open(shot) }
                Button("Copy") { model.copy(shot) }
                Button("Copy Text") { model.copyText(shot) }
                    .disabled(shot.text?.isEmpty ?? true)
                Button("Show in Finder") { model.reveal(shot) }
                Divider()
                Button("Remove from Pile") { model.remove(shot) }
                Button("Move to Trash", role: .destructive) { model.trash(shot) }
            }
            .help(Text("Drag into any app. Double-click to open."))
            .accessibilityAction(named: Text("Open")) { model.open(shot) }
            .accessibilityAction(named: Text("Copy")) { model.copy(shot) }
            .accessibilityAction(named: Text("Copy Text")) { model.copyText(shot) }
            .accessibilityAction(named: Text("Show in Finder")) { model.reveal(shot) }
    }
}
