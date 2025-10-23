//
//  HandTrackingViewModel.swift
//  VisionStack
//
//  Created by Yanis Zeghiche on 10.22.2025
//

import RealityKit
import SwiftUI
import ARKit
import RealityKitContent

// Tag component used to identify cubes in the scene
struct CubeMarkerComponent: Component {}

@MainActor class HandTrackingViewModel: ObservableObject {
    private let session = ARKitSession()
    private let handTracking = HandTrackingProvider()
    private let sceneReconstruction = SceneReconstructionProvider()

    private var contentEntity = Entity()
    private var meshEntities = [UUID : ModelEntity]()

    // MARK: - Data model Main -> Finger -> Points
    enum Finger: CaseIterable {
        case thumb, index, middle, ring, little
    }

    enum JointRole: CaseIterable {
        case metacarpal
        case knuckle
        case intermediateBase
        case intermediateTip
        case tip
    }

    struct FingerData {
        var points: [JointRole: ModelEntity] = [:]
    }

    struct Hand {
        let chirality: HandAnchor.Chirality
        var wrist: ModelEntity
        var forearmWrist: ModelEntity
        var forearmArm: ModelEntity
        var fingers: [Finger: FingerData]
    }

    // Accès direct aux deux mains
    private(set) var leftHand: Hand!
    private(set) var rightHand: Hand!

    // Liste des 26 joints (ordre selon ton image/doc)
    private let allJointNames: [HandSkeleton.JointName] = [
        // 0
        .wrist,
        // Thumb 1-4
        .thumbKnuckle, .thumbIntermediateBase, .thumbIntermediateTip, .thumbTip,
        // Index 5-9
        .indexFingerMetacarpal, .indexFingerKnuckle, .indexFingerIntermediateBase, .indexFingerIntermediateTip, .indexFingerTip,
        // Middle 10-14
        .middleFingerMetacarpal, .middleFingerKnuckle, .middleFingerIntermediateBase, .middleFingerIntermediateTip, .middleFingerTip,
        // Ring 15-19
        .ringFingerMetacarpal, .ringFingerKnuckle, .ringFingerIntermediateBase, .ringFingerIntermediateTip, .ringFingerTip,
        // Little 20-24
        .littleFingerMetacarpal, .littleFingerKnuckle, .littleFingerIntermediateBase, .littleFingerIntermediateTip, .littleFingerTip,
        // 25-26
        .forearmWrist, .forearmArm
    ]

    // Mapping JointName -> emplacement dans notre struct Hand
    private func map(_ joint: HandSkeleton.JointName) -> (finger: Finger?, role: JointRole?) {
        switch joint {
        case .wrist: return (nil, nil)
        case .forearmWrist: return (nil, nil)
        case .forearmArm: return (nil, nil)

        case .thumbKnuckle: return (.thumb, .knuckle)
        case .thumbIntermediateBase: return (.thumb, .intermediateBase)
        case .thumbIntermediateTip: return (.thumb, .intermediateTip)
        case .thumbTip: return (.thumb, .tip)

        case .indexFingerMetacarpal: return (.index, .metacarpal)
        case .indexFingerKnuckle: return (.index, .knuckle)
        case .indexFingerIntermediateBase: return (.index, .intermediateBase)
        case .indexFingerIntermediateTip: return (.index, .intermediateTip)
        case .indexFingerTip: return (.index, .tip)

        case .middleFingerMetacarpal: return (.middle, .metacarpal)
        case .middleFingerKnuckle: return (.middle, .knuckle)
        case .middleFingerIntermediateBase: return (.middle, .intermediateBase)
        case .middleFingerIntermediateTip: return (.middle, .intermediateTip)
        case .middleFingerTip: return (.middle, .tip)

        case .ringFingerMetacarpal: return (.ring, .metacarpal)
        case .ringFingerKnuckle: return (.ring, .knuckle)
        case .ringFingerIntermediateBase: return (.ring, .intermediateBase)
        case .ringFingerIntermediateTip: return (.ring, .intermediateTip)
        case .ringFingerTip: return (.ring, .tip)

        case .littleFingerMetacarpal: return (.little, .metacarpal)
        case .littleFingerKnuckle: return (.little, .knuckle)
        case .littleFingerIntermediateBase: return (.little, .intermediateBase)
        case .littleFingerIntermediateTip: return (.little, .intermediateTip)
        case .littleFingerTip: return (.little, .tip)

        default:
            return (nil, nil)
        }
    }

    // MARK: - Setup

    func setupContentEntity() -> Entity {
        // Helper pour créer une sphère d’articulation colorée
        func createJointSphere(color: UIColor, radius: Float = 0.01) -> ModelEntity {
            let entity = ModelEntity(
                mesh: .generateSphere(radius: radius),
                materials: [UnlitMaterial(color: color)],
                collisionShape: .generateSphere(radius: radius * 0.5),
                mass: 0.0
            )
            entity.components.set(PhysicsBodyComponent(mode: .kinematic))
            entity.components.set(OpacityComponent(opacity: 1.0))
            return entity
        }

        // Crée une main (26 points) avec une couleur
        func makeHand(chirality: HandAnchor.Chirality, color: UIColor) -> Hand {
            // Poignet/avant-bras
            let wrist = createJointSphere(color: color, radius: 0.012)
            let forearmWrist = createJointSphere(color: color, radius: 0.012)
            let forearmArm = createJointSphere(color: color, radius: 0.012)

            // Doigts
            var fingers: [Finger: FingerData] = [:]
            for f in Finger.allCases {
                var fd = FingerData()
                // Le pouce n’a pas metacarpal dans l’API fournie (on ne crée pas ce point)
                for role in JointRole.allCases {
                    // Skip metacarpal for thumb
                    if f == .thumb && role == .metacarpal { continue }
                    fd.points[role] = createJointSphere(color: color, radius: 0.01)
                }
                fingers[f] = fd
            }

            // Ajouter tous les enfants au graphe
            contentEntity.addChild(wrist)
            contentEntity.addChild(forearmWrist)
            contentEntity.addChild(forearmArm)
            for (_, fd) in fingers {
                for (_, e) in fd.points {
                    contentEntity.addChild(e)
                }
            }

            return Hand(chirality: chirality,
                        wrist: wrist,
                        forearmWrist: forearmWrist,
                        forearmArm: forearmArm,
                        fingers: fingers)
        }

        // Créer les deux mains: gauche rouge, droite bleu
        leftHand = makeHand(chirality: .left, color: UIColor(red: 1, green: 0.2745098174, blue: 0.4941176471, alpha: 1))
        rightHand = makeHand(chirality: .right, color: UIColor(red: 0.2352941176, green: 0.6745098062, blue: 1, alpha: 1))

        return contentEntity
    }

    // MARK: - Session

    func runSession () async {
        do {
            try await session.run([sceneReconstruction, handTracking])
        } catch {
            print ("failed to start session: \(error)")
        }
    }

    // MARK: - Hand updates

    func processHandUpdates() async {
        for await update in handTracking.anchorUpdates {
            let handAnchor = update.anchor
            guard handAnchor.isTracked else { continue }

            let originFromAnchor = handAnchor.originFromAnchorTransform

            // Sélectionne la main cible
            let hand = (handAnchor.chirality == .left) ? leftHand! : rightHand!

            for joint in allJointNames {
                guard
                    let jointInfo = handAnchor.handSkeleton?.joint(joint),
                    jointInfo.isTracked,
                    let anchorFromJoint = jointInfo.anchorFromJointTransform as? simd_float4x4
                else { continue }

                let originFromJoint = originFromAnchor * anchorFromJoint

                switch joint {
                case .wrist:
                    hand.wrist.setTransformMatrix(originFromJoint, relativeTo: nil)
                case .forearmWrist:
                    hand.forearmWrist.setTransformMatrix(originFromJoint, relativeTo: nil)
                case .forearmArm:
                    hand.forearmArm.setTransformMatrix(originFromJoint, relativeTo: nil)

                case .thumbKnuckle, .thumbIntermediateBase, .thumbIntermediateTip, .thumbTip,
                     .indexFingerMetacarpal, .indexFingerKnuckle, .indexFingerIntermediateBase, .indexFingerIntermediateTip, .indexFingerTip,
                     .middleFingerMetacarpal, .middleFingerKnuckle, .middleFingerIntermediateBase, .middleFingerIntermediateTip, .middleFingerTip,
                     .ringFingerMetacarpal, .ringFingerKnuckle, .ringFingerIntermediateBase, .ringFingerIntermediateTip, .ringFingerTip,
                     .littleFingerMetacarpal, .littleFingerKnuckle, .littleFingerIntermediateBase, .littleFingerIntermediateTip, .littleFingerTip:
                    let (finger, role) = map(joint)
                    guard let finger, let role else { continue }
                    if let entity = hand.fingers[finger]?.points[role] {
                        entity.setTransformMatrix(originFromJoint, relativeTo: nil)
                    }

                default:
                    break
                }
            }
            // Une fois les mains mises à jour, vérifier l'interaction doigt→cube
            self.detectTouchAndChangeColor()
        }
    }

    // MARK: - Scene reconstruction (inchangé)

    func processReconstructionUpdates() async {
        for await update in sceneReconstruction.anchorUpdates {
            guard let shape = try? await ShapeResource.generateStaticMesh(from: update.anchor) else {continue}

            switch update.event {
            case .added:
                let entity = ModelEntity()
                entity.transform = Transform(matrix: update.anchor.originFromAnchorTransform)
                entity.collision = CollisionComponent(shapes: [shape], isStatic: true)
                entity.physicsBody = PhysicsBodyComponent()
                entity.components.set(InputTargetComponent())

                meshEntities[update.anchor.id] = entity

                contentEntity.addChild(entity)
            case .updated:
                guard let entiy = meshEntities[update.anchor.id] else { fatalError("...")}
                entiy.transform = Transform(matrix: update.anchor.originFromAnchorTransform)
                entiy.collision?.shapes = [shape]
            case .removed:
                meshEntities[update.anchor.id]?.removeFromParent()
                meshEntities.removeValue(forKey: update.anchor.id)
            }
        }
    }

    // MARK: - Cube placement (inchangé)

    func placeCube() async {
        // Exemple: utiliser la position du tip de l’index gauche si disponible
        if let leftIndexTip = leftHand?.fingers[.index]?.points[.tip]?.transform.translation {
            let placementLocation = leftIndexTip + SIMD3<Float>(0, -0.05, 0)

            let entity = ModelEntity(
                mesh: .generateBox(size: 0.1),
                materials: [SimpleMaterial(color: .systemBlue, isMetallic: false)],
                collisionShape: .generateBox(size: SIMD3<Float>(repeating: 0.1)),
                mass: 1.0
            )

            entity.setPosition(placementLocation, relativeTo: nil)
            entity.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            entity.components.set(GroundingShadowComponent(castsShadow: true))

            let material = PhysicsMaterialResource.generate(friction: 0.8, restitution: 0.0)
            entity.components.set(PhysicsBodyComponent(shapes: entity.collision!.shapes, mass: 1.0, material: material, mode: .dynamic))

            // Tag as cube so interaction code only targets cubes
            entity.components.set(CubeMarkerComponent())
            entity.name = "cube"

            contentEntity.addChild(entity)
        }
    }
    
    func detectTouchAndChangeColor() {
        // Position du bout de l’index droit
        guard let rightIndexPosition = rightHand?.fingers[.index]?.points[.tip]?.transform.translation
        else { return }

        // Parcourt uniquement les entités marquées comme cubes
        for child in contentEntity.children {
            guard let cube = child as? ModelEntity, cube.components.has(CubeMarkerComponent.self) else { continue }

            // Récupère la boîte englobante du cube
            let bounds = cube.visualBounds(relativeTo: nil)
            let min = bounds.min
            let max = bounds.max

            // Vérifie si la position du doigt est à l’intérieur du cube
            if (rightIndexPosition.x >= min.x && rightIndexPosition.x <= max.x) &&
               (rightIndexPosition.y >= min.y && rightIndexPosition.y <= max.y) &&
               (rightIndexPosition.z >= min.z && rightIndexPosition.z <= max.z) {

                // Couleur aléatoire
                let randomColor = UIColor(
                    red: CGFloat.random(in: 0...1),
                    green: CGFloat.random(in: 0...1),
                    blue: CGFloat.random(in: 0...1),
                    alpha: 1.0
                )

                cube.model?.materials = [SimpleMaterial(color: randomColor, isMetallic: false)]
            }
        }
    }
}
