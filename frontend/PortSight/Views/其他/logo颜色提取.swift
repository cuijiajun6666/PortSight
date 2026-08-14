//
//  logo颜色提取.swift
//  PortSight
//
//  Created by Chris Cui on 17/5/2026.
//

import SwiftUI
import UIKit

struct LogoFeatureColor {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

func extractLogoFeatureColor(from data: Data) -> LogoFeatureColor? {
    guard let image = UIImage(data: data),
          let cgImage = image.cgImage else {
        return nil
    }

    let size = 40
    let bytesPerPixel = 4
    let bytesPerRow = size * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: size * size * bytesPerPixel)

    guard let context = CGContext(
        data: &pixels,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    context.interpolationQuality = .medium
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

    var redSum = 0.0
    var greenSum = 0.0
    var blueSum = 0.0
    var weightSum = 0.0

    var fallbackRedSum = 0.0
    var fallbackGreenSum = 0.0
    var fallbackBlueSum = 0.0
    var fallbackWeightSum = 0.0

    for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
        let alpha = Double(pixels[index + 3]) / 255.0
        guard alpha > 0.18 else { continue }

        let red = Double(pixels[index]) / 255.0
        let green = Double(pixels[index + 1]) / 255.0
        let blue = Double(pixels[index + 2]) / 255.0

        let maxChannel = max(red, green, blue)
        let minChannel = min(red, green, blue)
        let saturation = maxChannel == 0 ? 0 : (maxChannel - minChannel) / maxChannel
        let brightness = maxChannel

        let fallbackWeight = alpha
        fallbackRedSum += red * fallbackWeight
        fallbackGreenSum += green * fallbackWeight
        fallbackBlueSum += blue * fallbackWeight
        fallbackWeightSum += fallbackWeight

        guard brightness < 0.96, brightness > 0.08 else { continue }

        let colorWeight = alpha * (0.35 + saturation * 1.4)
        redSum += red * colorWeight
        greenSum += green * colorWeight
        blueSum += blue * colorWeight
        weightSum += colorWeight
    }

    if weightSum > 0 {
        return LogoFeatureColor(
            red: redSum / weightSum,
            green: greenSum / weightSum,
            blue: blueSum / weightSum
        )
    }

    guard fallbackWeightSum > 0 else { return nil }

    return LogoFeatureColor(
        red: fallbackRedSum / fallbackWeightSum,
        green: fallbackGreenSum / fallbackWeightSum,
        blue: fallbackBlueSum / fallbackWeightSum
    )
}
