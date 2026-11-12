import SwiftUI
import Charts
import PortSightKit

func demoMoney(_ value: Double) -> String { value.formatted(.currency(code: "USD")) }
func demoPercent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(2))) }

