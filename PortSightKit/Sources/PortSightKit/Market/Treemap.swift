import CoreGraphics

/// Squarified treemap (Bruls, Huizing & van Wijk): splits a rectangle into one rectangle per weight,
/// each with an area proportional to its weight and an aspect ratio kept close to 1.
/// Pure geometry: no views, no state, safe to call from any layout pass.
public enum Treemap {
    /// Returns one rectangle per weight, in the same order as `weights`.
    /// Positive weights tile `rect` exactly; zero, negative or non-finite weights get `.zero`.
    public nonisolated static func squarify(_ weights: [Double], in rect: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: weights.count)
        let rect = rect.standardized
        guard rect.width > 0, rect.height > 0 else { return result }
        let order = weights.indices
            .filter { weights[$0].isFinite && weights[$0] > 0 }
            .sorted { weights[$0] == weights[$1] ? $0 < $1 : weights[$0] > weights[$1] }
        let total = order.reduce(0) { $0 + weights[$1] }
        guard total > 0 else { return result }

        let scale = Double(rect.width * rect.height) / total
        let areas = order.map { weights[$0] * scale }
        var remaining = rect
        var start = 0
        while start < order.count {
            // Grow the row while adding the next item does not worsen the row's worst aspect ratio.
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            var rowArea = areas[start]
            var best = worst(areas[start..<end], sum: rowArea, side: side)
            while end < order.count {
                let nextArea = rowArea + areas[end]
                let next = worst(areas[start...end], sum: nextArea, side: side)
                guard next <= best else { break }
                best = next
                rowArea = nextArea
                end += 1
            }
            let isLast = end == order.count
            remaining = place(Array(order[start..<end]), areas: Array(areas[start..<end]), rowArea: rowArea,
                              in: remaining, fillsRemaining: isLast, into: &result)
            start = end
        }
        return result
    }

    /// Worst (largest) aspect ratio of a row of `areas` laid along a side of length `side`.
    private nonisolated static func worst(_ areas: ArraySlice<Double>, sum: Double, side: Double) -> Double {
        guard let largest = areas.max(), let smallest = areas.min(), sum > 0, side > 0, smallest > 0 else {
            return .infinity
        }
        let side2 = side * side, sum2 = sum * sum
        return max(side2 * largest / sum2, sum2 / (side2 * smallest))
    }

    /// Lays one row along the shorter side of `rect` and returns the rectangle still left to fill.
    private nonisolated static func place(_ indices: [Int], areas: [Double], rowArea: Double, in rect: CGRect,
                              fillsRemaining: Bool, into result: inout [CGRect]) -> CGRect {
        if rect.width >= rect.height {
            // A column on the left, items stacked top to bottom.
            let width = fillsRemaining ? rect.width : min(rect.width, CGFloat(rowArea / Double(rect.height)))
            var y = rect.minY
            for (offset, index) in indices.enumerated() {
                let isEnd = offset == indices.count - 1
                let height = isEnd ? rect.maxY - y : CGFloat(areas[offset] / rowArea) * rect.height
                result[index] = CGRect(x: rect.minX, y: y, width: width, height: height)
                y += height
            }
            return CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height)
        } else {
            // A row along the top, items left to right.
            let height = fillsRemaining ? rect.height : min(rect.height, CGFloat(rowArea / Double(rect.width)))
            var x = rect.minX
            for (offset, index) in indices.enumerated() {
                let isEnd = offset == indices.count - 1
                let width = isEnd ? rect.maxX - x : CGFloat(areas[offset] / rowArea) * rect.width
                result[index] = CGRect(x: x, y: rect.minY, width: width, height: height)
                x += width
            }
            return CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height)
        }
    }
}
