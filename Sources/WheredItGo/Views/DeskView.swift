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
                .frame(height: model.expandedInPanel ? Layout.fanHeight : Layout.pileSize.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.corner.alignment)
    }
}

struct PrintStation: View {
    let model: DeskModel
    let namespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .top) {
            if let shot = model.printing {
                TimelineView(.animation) { context in
                    PolaroidView(shot: shot, develop: model.developProgress(at: context.date))
                }
                .matchedGeometryEffect(id: shot.id, in: namespace)
                .rotationEffect(.degrees(model.wiggle), anchor: .top)
                .offset(y: (model.eject - 1) * Layout.cardHeight)
                .frame(width: Layout.cardWidth, height: Layout.cardHeight, alignment: .top)
                .mask(alignment: .top) {
                    // Hides the part of the print still inside the camera; lifts once it is fully out.
                    Rectangle()
                        .frame(width: Layout.cardWidth * 2, height: Layout.cardHeight * (model.eject < 1 ? 1 : 3))
                        .offset(y: model.eject < 1 ? 0 : -Layout.cardHeight)
                }
                .padding(.top, Layout.slotY)
                .onDrag { model.dragProvider(for: shot) }
                .help(Text("Wiggle the pointer to develop faster, or drag it out right away."))
            }

            CameraView(flash: model.flash)
                .scaleEffect(model.cameraShown ? 1 : 0.82, anchor: .bottom)
                .rotationEffect(.degrees(model.flash * -2.5), anchor: .bottom)
                .offset(y: (model.cameraShown ? 0 : 50) - model.flash * 3)
                .opacity(model.cameraShown ? 1 : 0)
                .padding(.top, 8)

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
            ForEach(Array(items.enumerated()), id: \.element.id) { index, shot in
                PileCard(shot: shot, model: model, namespace: namespace, index: index,
                         expanded: model.pileExpanded, trailing: trailing)
                    .zIndex(model.hoveredShot == shot.id && model.pileExpanded ? 100 : Double(items.count - index))
            }
        }
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
        if model.sweptCount > 0 {
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
        PolaroidView(shot: shot, lifted: hovering && expanded)
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
                Button("Show in Finder") { model.reveal(shot) }
                Divider()
                Button("Remove from Pile") { model.remove(shot) }
                Button("Move to Trash", role: .destructive) { model.trash(shot) }
            }
            .help(Text("Drag into any app. Double-click to open."))
            .accessibilityAction(named: Text("Open")) { model.open(shot) }
            .accessibilityAction(named: Text("Copy")) { model.copy(shot) }
            .accessibilityAction(named: Text("Show in Finder")) { model.reveal(shot) }
    }
}
