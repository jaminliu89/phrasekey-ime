import Foundation

// PhraseKey 引擎基准 + 回归测试（离线 CLI，不依赖 AppKit / IMK）
// 用法：bash Scripts/bench_engine.sh

func ms(_ block: () -> Void) -> Double {
    let t0 = DispatchTime.now().uptimeNanoseconds
    block()
    return Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
}

func residentMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return -1 }
    return Double(info.resident_size) / 1024 / 1024
}

print("=== PhraseKey 引擎基准 ===")
let memBefore = residentMB()

// 引擎为 lazy 单例，首次访问触发词库加载 + 索引构建
var loadedCount = 0
let loadMs = ms {
    loadedCount = PinyinEngine.shared.entryCount
}
let memAfter = residentMB()

print(String(format: "词库加载 + 索引构建：%.1f ms（%d 条）", loadMs, loadedCount))
print(String(format: "内存增量：%.1f MB（%.1f → %.1f）", memAfter - memBefore, memBefore, memAfter))

// ---- 查询性能 ----
let queries = ["nihao", "mingtian", "xinkule", "rengongzhineng", "xiangmu", "shurufa", "hunli", "kaihui"]
var totalQueryMs = 0.0
for q in queries {
    totalQueryMs += ms { _ = Searcher.shared.search(q, scheme: .pinyin) }
}
print(String(format: "查询平均耗时（全拼 %d 次）：%.3f ms", queries.count, totalQueryMs / Double(queries.count)))

// ---- 回归断言 ----
var failures: [String] = []

func expect(_ input: String, contains word: String, scheme: InputScheme = .pinyin, file: String = #function) {
    let results = Searcher.shared.search(input, scheme: scheme).map { $0.text }
    if results.contains(word) {
        let rank = results.firstIndex(of: word)! + 1
        print("  ✅ \(input) → \(word)（第 \(rank) 位，共 \(results.count) 候选）")
    } else {
        let head = results.prefix(5).joined(separator: " ")
        failures.append("\(input) 未命中 \(word)（前 5：\(head)）")
        print("  ❌ \(input) → 期望 \(word)，实际前 5：\(head)")
    }
}

func expectFirst(_ input: String, is word: String, scheme: InputScheme = .pinyin) {
    let results = Searcher.shared.search(input, scheme: scheme).map { $0.text }
    if results.first == word {
        print("  ✅ \(input) 首选 = \(word)")
    } else {
        failures.append("\(input) 首选应为 \(word)，实际 \(results.first ?? "空")")
        print("  ❌ \(input) 首选应为 \(word)，实际 \(results.first ?? "空")")
    }
}

print("\n=== 全拼查询回归 ===")
expectFirst("nihao", is: "你好")
expect("mingtian", contains: "明天")
expect("kaihui", contains: "开会")
expect("xinkule", contains: "辛苦了")
expect("rengongzhineng", contains: "人工智能")
expect("shurufa", contains: "输入法")
expect("hunli", contains: "婚礼")
expect("xiangmu", contains: "项目")
expect("huiyijiyao", contains: "会议纪要")
expect("shengrikuaile", contains: "生日快乐")

print("\n=== 简拼查询回归 ===")
expect("nh", contains: "你好")
expect("mt", contains: "明天")

print("\n=== 小鹤双拼回归 ===")
// 你好 = nihc（ni=ni, hao=hc）
expect("nihc", contains: "你好", scheme: .flypy)
// 明天 = mkti（ming=mk, tian=tm? 实际 tian → t+m）
expect("mktm", contains: "明天", scheme: .flypy)

print("\n=== 拼音切分回归 ===")
let segCases: [(String, [String])] = [
    ("nihao", ["ni", "hao"]),
    ("xianzai", ["xian", "zai"]),
    ("zhongguoren", ["zhong", "guo", "ren"]),
    ("shurufa", ["shu", "ru", "fa"]),
    ("kaihui", ["kai", "hui"]),
    ("women", ["wo", "men"]),
    ("jintian", ["jin", "tian"]),
    ("xiangmu", ["xiang", "mu"]),
]
for (input, expected) in segCases {
    let got = PinyinSyllable.segment(input)
    if got == expected {
        print("  ✅ \(input) → \(got.joined(separator: "/"))")
    } else {
        failures.append("切分 \(input) 期望 \(expected.joined(separator: "/")) 实际 \(got.joined(separator: "/"))")
        print("  ❌ \(input) → \(got.joined(separator: "/"))，期望 \(expected.joined(separator: "/"))")
    }
}

print("\n=== 非法音节检查 ===")
let illegal = ["fai", "ruang", "yve", "wong", "biang", "fiu", "zhuang"]
for s in illegal {
    // zhuang 是合法音节，其余应为非法
    let valid = PinyinSyllable.isSyllable(s)
    let shouldBeValid = (s == "zhuang")
    if valid == shouldBeValid {
        print("  ✅ \(s) 合法性判定正确（\(valid)）")
    } else {
        failures.append("音节 \(s) 合法性判定错误：得到 \(valid)，应为 \(shouldBeValid)")
        print("  ❌ \(s) 判定为 \(valid)，应为 \(shouldBeValid)")
    }
}

// ---- 断档回归（能用/不能用的分界线，必须永久断言）----
// 症状史：query() 曾是纯字典精确匹配，输入到「不完整音节组合」（niha / womenz）
// 时字典无此键 → 候选为空 → 键盘只剩字母键 → 无法连续输入。
// 这里逐字母模拟真实敲击，任一中间状态候选为空即视为回归。
print("\n=== 连续输入断档回归 ===")
let typingCases = [
    "nihao",
    "xianzai",
    "zhongguoren",
    "womenzai",
    "nihaoshijie",          // 长串：11 字母 4 音节
    "jintianwanshangkaihui", // 超长串：21 字母 7 音节
    "rengongzhineng",
    "shengrikuaile",
]
for phrase in typingCases {
    var gaps: [String] = []
    var trace: [String] = []
    var chars = ""
    for ch in phrase {
        chars.append(ch)
        let n = Searcher.shared.search(chars, scheme: .pinyin).count
        trace.append("\(chars):\(n)")
        if n == 0 { gaps.append(chars) }
    }
    if gaps.isEmpty {
        print("  ✅ \(phrase) 逐字母无断档（\(phrase.count) 步）")
    } else {
        failures.append("断档 \(phrase)：\(gaps.joined(separator: ",")) 处候选为空")
        print("  ❌ \(phrase) 断档于 \(gaps.joined(separator: ","))")
        print("     轨迹：\(trace.joined(separator: " "))")
    }
}

// ---- 常用语持久化回归 ----
// 症状史：App Group 容器下 PhraseKey/ 子目录不会自动创建，缺目录时 write 失败
// 而 try? 静默吞错 → 表现为「常用语加不进去」。这里断言写入后能读回。
print("\n=== 常用语持久化回归 ===")
do {
    let store = HotwordsStore.shared
    let probeKey = "zzprobe\(Int(Date().timeIntervalSince1970))"
    let before = store.items.count
    store.add(text: "断档回归探针文本", key: probeKey)
    store.load()   // 强制从磁盘重读，验证真的落盘了
    let hit = store.items.first { $0.key == probeKey }
    if let hit {
        print("  ✅ 写入并从磁盘读回成功（\(before) → \(store.items.count) 条）")
        store.remove(id: hit.hw_id)   // 清理探针，不污染真实数据
    } else {
        failures.append("常用语写入后无法读回（key=\(probeKey)）")
        print("  ❌ 写入后从磁盘读不回来 —— 落盘失败")
    }
}

// ---- 排序质量回归 ----
// 症状史（两个 bug 叠加，均已实测定性）：
//   ① freq 加成用 min(freq,999) 硬截断 → 7987 条高频词全部并列同分
//   ② best.values.sorted 只比 score，Dictionary 遍历顺序 + 不稳定排序
//      → 同一输入跑三次候选位置不同（womenz 的「我们」落在 6/1/3 位）
print("\n=== 排序确定性回归 ===")
for input in ["womenz", "niha", "zhongguor", "nihao", "wo"] {
    var seen = Set<String>()
    for _ in 0..<5 {
        let top = Searcher.shared.search(input, scheme: .pinyin)
            .prefix(10).map { $0.text }.joined(separator: "/")
        seen.insert(top)
    }
    if seen.count == 1 {
        print("  ✅ \(input) 跑 5 次顺序一致")
    } else {
        failures.append("排序不确定 \(input)：5 次出现 \(seen.count) 种顺序")
        print("  ❌ \(input) 跑 5 次出现 \(seen.count) 种顺序")
        for s in seen { print("     \(s)") }
    }
}

// 意图匹配：多敲的字母代表意图收窄，覆盖度高的候选必须靠前。
// 旧行为：womenz 首选是「我」（只覆盖 2/6 字母），用户已经敲了 menz 却拿不到「我们」。
print("\n=== 覆盖度优先回归 ===")
expectFirst("womenz", is: "我们")
expectFirst("niha", is: "你好")
expectFirst("womenzai", is: "我们")
expectFirst("nihaosh", is: "你好")

print("\n=== 结果 ===")
if failures.isEmpty {
    print("全部通过 ✅")
    exit(0)
} else {
    print("失败 \(failures.count) 项：")
    for f in failures { print("  · \(f)") }
    exit(1)
}
