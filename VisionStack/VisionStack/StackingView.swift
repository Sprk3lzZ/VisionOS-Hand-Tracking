//
//  StackingView.swift
//  VisionStack
//
//  Created by Yanis Zeghiche on 10.22.2025
//

import SwiftUI
import RealityKit
import RealityKitContent

struct StackingView: View {
    @StateObject var model = HandTrackingViewModel()
    
    var body: some View {
        RealityView { content in
            content.add(model.setupContentEntity())
        }.task {
            await model.runSession()
        }.task {
            await model.processHandUpdates()
        }.task {
            await model.processReconstructionUpdates()
        }.gesture(SpatialTapGesture().targetedToAnyEntity().onEnded({ value in
            
            Task {
                await model.placeCube()
            }
            
            Task {
                model.detectTouchAndChangeColor()
            }
            
            
        }))
    }
}

#Preview {
    StackingView()
}
