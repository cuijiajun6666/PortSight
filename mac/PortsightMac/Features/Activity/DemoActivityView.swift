import SwiftUI
import Charts
import PortSightKit
struct DemoActivityView: View {
    @EnvironmentObject private var demo: PortfolioDemo
    @State private var filter = "全部"
    @State private var search = ""
    private var rows: [DemoActivity] { demo.activities.filter {
        (filter == "全部" || $0.category == filter) && (search.isEmpty || ($0.title + $0.detail).localizedCaseInsensitiveContains(search))
    } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack { Text(demo.scope.rawValue + "动态").font(.title2.bold()) }
                    DesktopCapsulePicker(title: "类型", options: ["全部", "成交", "资金", "分红", "系统"], selection: $filter) { $0 }
                }.listRowBackground(Color.clear)
                Section {
                    if rows.isEmpty { ContentUnavailableView.search(text: search) }
                    ForEach(rows) { item in NavigationLink { DemoActivityDetail(item: item) } label: { DemoActivityRow(item: item) } }
                } footer: { Text("入金和内部划转不计入投资收益。") }
            }.listStyle(.inset).toolbar { DemoToolbar() }
                .searchable(text: $search, prompt: "搜索交易、资金或系统事件")
        }
    }
}
