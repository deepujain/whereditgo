import SceneKit
import SwiftUI

/// The part of a print that has left the camera slot, as a real sheet of paper: it leaves the slot
/// tilted toward the viewer, sags under its own weight, its leading edge lifts with the curl the
/// film keeps from the cartridge, its sides bow, and it sways as the rollers push it. Light glides
/// across every bend and its shadow falls on the screen behind. Released, it springs flat.
struct CurlingPrint: View, Animatable {
    /// The undeveloped print, `Layout.cardWidth` × `Layout.cardHeight`.
    let sheet: NSImage
    /// 0 while the print is inside the camera, 1 once it is fully out.
    var progress: Double
    /// 0 while the rollers hold the print, 1 once it lies flat. Springs may overshoot.
    var relax: Double

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, relax) }
        set { progress = newValue.first; relax = newValue.second }
    }

    var body: some View {
        Group {
            if let image = PaperScene.render(sheet, progress: progress, relax: relax) {
                Image(nsImage: image)
                    .frame(width: PaperScene.canvas.width, height: PaperScene.canvas.height)
            }
        }
        .frame(width: Layout.cardWidth, height: Layout.cardHeight, alignment: .top)
    }
}

/// Renders the sheet offscreen with SceneKit. The scene's z = 0 plane maps one point to one point,
/// with the slot's centre at the top centre of `canvas`, so a flat sheet lands exactly where the
/// print's flat view takes over.
@MainActor
enum PaperScene {
    static let margin: CGFloat = 30
    static let canvas = CGSize(width: Layout.cardWidth + margin * 2, height: Layout.cardHeight + margin)

    /// Angle toward the viewer, in radians, at which paper leaves the slot.
    private static let exitAngle: Double = 0.95
    /// The extra turn at the leading edge from the film's curl.
    private static let edgeCurl: Double = 0.85
    private static let edgeCurlLength: Double = 46
    private static let viewerDistance: Double = 520
    private static let rowStep: Double = 2
    private static let columns = 14

    private static let scene = makeScene()
    private static let paper = SCNNode()
    private static let material: SCNMaterial = {
        let material = SCNMaterial()
        material.lightingModel = .blinn
        material.specular.contents = NSColor(white: 0.32, alpha: 1)
        material.shininess = 0.35
        material.isDoubleSided = true
        material.multiply.contents = slotShade
        material.multiply.wrapT = .clamp
        return material
    }()
    /// Darkens paper just out of the slot, in the slot's frame: shifted per frame to follow it.
    private static let slotShade: NSImage = {
        let rows = 256
        let image = NSImage(size: NSSize(width: 4, height: rows))
        image.lockFocus()
        for row in 0..<rows {
            let s = Double(row) / Double(rows) * Double(Layout.cardHeight)
            NSColor(white: 1 - 0.3 * exp(-s / 7), alpha: 1).setFill()
            NSRect(x: 0, y: rows - row - 1, width: 4, height: 1).fill()
        }
        image.unlockFocus()
        return image
    }()
    private static let renderer: SCNRenderer = {
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = scene.rootNode.childNode(withName: "eye", recursively: false)
        renderer.autoenablesDefaultLighting = false
        return renderer
    }()
    private static weak var texturedSheet: NSImage?

    static func render(_ sheet: NSImage, progress: Double, relax: Double) -> NSImage? {
        let progress = min(1, max(0, progress))
        let length = Double(Layout.cardHeight) * progress
        guard length > 0.5 else { return nil }
        if texturedSheet !== sheet {
            material.diffuse.contents = sheet
            texturedSheet = sheet
        }
        let held = max(-0.15, 1 - relax)
        paper.geometry = geometry(length: length, progress: progress, held: held)
        paper.geometry?.firstMaterial = material
        material.multiply.contentsTransform = SCNMatrix4MakeTranslation(0, -(1 - progress), 0)
        material.multiply.intensity = max(0, min(1, held))

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        // The eye looks straight at the slot, so render twice the height and keep the lower half.
        let full = CGSize(width: canvas.width * scale, height: canvas.height * 2 * scale)
        let snapshot = renderer.snapshot(atTime: 0, with: full, antialiasingMode: .multisampling4X)
        guard let cgImage = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let lower = cgImage.cropping(to: CGRect(x: 0, y: CGFloat(cgImage.height) / 2,
                                                      width: CGFloat(cgImage.width), height: CGFloat(cgImage.height) / 2))
        else { return nil }
        return NSImage(cgImage: lower, size: canvas)
    }

    // MARK: Scene

    private static func makeScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear

        let eye = SCNNode()
        eye.name = "eye"
        let camera = SCNCamera()
        camera.projectionDirection = .vertical
        camera.fieldOfView = 2 * atan(Double(canvas.height) / viewerDistance) * 180 / .pi
        camera.zNear = 10
        camera.zFar = 2000
        eye.camera = camera
        eye.position = SCNVector3(0, 0, viewerDistance)
        scene.rootNode.addChildNode(eye)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 350
        scene.rootNode.addChildNode(ambient)

        // Nearly along the line of sight, a little above: flat paper is fully lit, every bend away
        // from it falls into soft shade, and the shadow lands just below wherever the sheet lifts.
        // Directional lights and deferred shadows draw nothing on a shadow-only surface offscreen.
        let key = SCNNode()
        let light = SCNLight()
        light.type = .spot
        light.spotInnerAngle = 50
        light.spotOuterAngle = 80
        light.intensity = 680
        light.castsShadow = true
        light.shadowMode = .forward
        light.shadowColor = NSColor(red: 0.2, green: 0.1, blue: 0, alpha: 0.3)
        light.shadowRadius = 9
        light.shadowSampleCount = 16
        light.shadowBias = 4
        light.zNear = 50
        light.zFar = 1500
        key.light = light
        key.position = SCNVector3(-30, 50, 520)
        key.look(at: SCNVector3(0, -60, 0))
        scene.rootNode.addChildNode(key)

        let screen = SCNNode(geometry: SCNPlane(width: canvas.width * 2, height: canvas.height * 2))
        screen.geometry?.firstMaterial?.lightingModel = .shadowOnly
        screen.position = SCNVector3(0, -canvas.height, -6)
        scene.rootNode.addChildNode(screen)

        paper.castsShadow = true
        scene.rootNode.addChildNode(paper)
        return scene
    }

    // MARK: Sheet

    private static func geometry(length: Double, progress: Double, held: Double) -> SCNGeometry {
        let width = Double(Layout.cardWidth), height = Double(Layout.cardHeight)
        let rows = max(1, Int((length / rowStep).rounded(.up)))
        let step = length / Double(rows)

        // The centre line of the sheet, from the slot down, in a y-down profile.
        var spine: [(y: Double, z: Double)] = [(0, 0)]
        spine.reserveCapacity(rows + 1)
        for row in 0..<rows {
            let theta = angle(at: (Double(row) + 0.5) * step, length: length, progress: progress) * held
            let last = spine[row]
            spine.append((last.y + cos(theta) * step, last.z + sin(theta) * step))
        }

        let sway = 0.05 * sin(progress * 11 + 0.6) * (1 - progress * 0.5) * held
        let bow = 10 * held
        var positions: [SCNVector3] = []
        var coordinates: [CGPoint] = []
        positions.reserveCapacity((rows + 1) * (columns + 1))
        for row in 0...rows {
            let s = Double(row) * step
            let along = s / height
            for column in 0...columns {
                let u = Double(column) / Double(columns)
                let across = 2 * u - 1
                let z = spine[row].z + bow * along * across * across + sway * s * across
                positions.append(SCNVector3((u - 0.5) * width, -spine[row].y, z))
                coordinates.append(CGPoint(x: u, y: (height - length + s) / height))
            }
        }

        let stride = columns + 1
        var normals: [SCNVector3] = []
        normals.reserveCapacity(positions.count)
        for row in 0...rows {
            for column in 0...columns {
                let left = positions[row * stride + max(0, column - 1)]
                let right = positions[row * stride + min(columns, column + 1)]
                let up = positions[max(0, row - 1) * stride + column]
                let down = positions[min(rows, row + 1) * stride + column]
                let across = SCNVector3(right.x - left.x, right.y - left.y, right.z - left.z)
                let along = SCNVector3(up.x - down.x, up.y - down.y, up.z - down.z)
                var normal = SCNVector3(across.y * along.z - across.z * along.y,
                                        across.z * along.x - across.x * along.z,
                                        across.x * along.y - across.y * along.x)
                let size = max(0.0001, sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z))
                normal = SCNVector3(normal.x / size, normal.y / size, normal.z / size)
                normals.append(normal)
            }
        }

        var indices: [Int32] = []
        indices.reserveCapacity(rows * columns * 6)
        for row in 0..<rows {
            for column in 0..<columns {
                let a = Int32(row * stride + column), b = a + 1
                let c = Int32((row + 1) * stride + column), d = c + 1
                indices += [a, c, b, b, c, d]
            }
        }

        return SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals),
                                     SCNGeometrySource(textureCoordinates: coordinates)],
                           elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }

    /// Stiff paper held at the slot sags like a cantilever: the bend at each point grows with the
    /// cube of how much paper hangs beyond it. The leading edge turns back up with the film's curl,
    /// more as more paper comes out to carry it, and the sheet flexes as each roller turn pushes it.
    private static func angle(at s: Double, length: Double, progress: Double) -> Double {
        let full = Double(Layout.cardHeight)
        let sag = 3 * (exitAngle + 0.15) / (full * full * full)
        let hang = exitAngle - sag * (pow(length, 3) - pow(length - s, 3)) / 3
        let edge = max(0, 1 - (length - s) / edgeCurlLength)
        let curl = edgeCurl * edge * edge * min(1, length / 70)
        let flex = 0.07 * sin(progress * 19) * (s / max(1, length)) * (1 - progress * 0.6)
        return hang + curl + flex
    }
}

@MainActor
enum PrintSheet {
    /// A still image of the print before it develops, for drawing it as it curls out of the slot.
    static func render(_ shot: Shot) -> NSImage? {
        let renderer = ImageRenderer(content: PolaroidView(shot: shot, develop: 0, shadowed: false))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }
}
