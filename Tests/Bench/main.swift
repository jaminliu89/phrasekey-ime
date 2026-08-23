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

// ---- 默认方案（小鹤双拼）专项回归 ----
// 为何单独开一组：产品默认 scheme 就是 .flypy（InputScheme.default），
// 但之前回归只有 2 条双拼断言，而断档/排序全部按全拼测 —— 盖不到默认路径。
// 实测曾发现：双拼在奇数键位全线断档（wourfg 6 步 5 空），
// 而双拼每字定长 2 键，用户打词时必然逐键经过奇数长度 → 默认方案开箱就是坏的。
print("\n=== 默认方案（\(InputScheme.default.rawValue)）断档回归 ===")
// 用 encode 反推真实双拼码，不手写——手写容易编造出不存在的码（我自己踩过）
let flypyCases: [(String, String)] = [
    ("ni hao", "你好"),
    ("wo men", "我们"),
    ("wo men zai", "我们"),
    ("ming tian", "明天"),
    ("zhong guo", "中国"),
    ("ren gong zhi neng", "人工智能"),
    ("xin ku le", "辛苦了"),
]
for (pinyin, word) in flypyCases {
    let code = FlypyCodec.encode(pinyin.split(separator: " ").map(String.init))
    var gaps: [String] = []
    var chars = ""
    for ch in code {
        chars.append(ch)
        if Searcher.shared.search(chars, scheme: .flypy).isEmpty { gaps.append(chars) }
    }
    if gaps.isEmpty {
        print("  ✅ \(word) [\(code)] 逐键无断档（\(code.count) 步）")
    } else {
        failures.append("双拼断档 \(word)[\(code)]：\(gaps.joined(separator: ","))")
        print("  ❌ \(word) [\(code)] 断档于 \(gaps.joined(separator: ","))")
    }
}

print("\n=== 默认方案整串首选回归 ===")
for (pinyin, word) in flypyCases where !pinyin.contains("zai") {
    let code = FlypyCodec.encode(pinyin.split(separator: " ").map(String.init))
    expectFirst(code, is: word, scheme: .flypy)
}

// 双拼下的覆盖度坐标系：coverBonus 必须拿「候选的双拼码」比输入，
// 而不是拿全拼串比双拼串（后者坐标系不对，覆盖度与精确匹配全算错）。
print("\n=== 双拼覆盖度优先回归 ===")
expectFirst("wom", is: "我们", scheme: .flypy)        // 奇数位，末键 m 是声母
expectFirst("womfz", is: "我们", scheme: .flypy)      // 已成词 + 半个字
expectFirst("nih", is: "你好", scheme: .flypy)

// 音形未装码表时应退化为双拼（不得丢输入）。
print("\n=== 小鹤音形退化回归 ===")
for (pinyin, word) in flypyCases.prefix(4) {
    let code = FlypyCodec.encode(pinyin.split(separator: " ").map(String.init))
    let xing = Searcher.shared.search(code, scheme: .flypyXing).map { $0.text }
    if xing.contains(word) {
        print("  ✅ \(word) [\(code)] 音形下仍命中（第 \(xing.firstIndex(of: word)! + 1) 位）")
    } else {
        failures.append("音形丢输入 \(word)[\(code)]：前5 \(xing.prefix(5).joined(separator: " "))")
        print("  ❌ \(word) [\(code)] 音形下丢失")
    }
}

// encode/decode 必须可逆：否则双拼回退路径（decode 后当全拼查）会查错键。
print("\n=== 双拼编码往返一致性 ===")
for (pinyin, _) in flypyCases {
    let sylls = pinyin.split(separator: " ").map(String.init)
    let code = FlypyCodec.encode(sylls)
    let back = FlypyCodec.decode(code)
    if back == sylls {
        print("  ✅ \(pinyin) → \(code) → 原样返回")
    } else {
        failures.append("往返不一致 \(pinyin) → \(code) → \(back.joined(separator: "/"))")
        print("  ❌ \(pinyin) → \(code) → \(back.joined(separator: "/"))  ← 不可逆")
    }
}

// 全量音节暂返扫描：只测几个词不足以证明可逆（wo 这个 bug 就是漏在手写用例外）。
// 拿真实 417 音节表逐个 encode → decode，要求原样返回。
print("\n=== 全量音节往返扫描 ===")
var rtBad: [String] = []
var rtOK = 0
for sy in PinyinSyllable.all.sorted() {
    let code = FlypyCodec.encode([sy])
    guard code.count == 2 else {
        rtBad.append("\(sy) encode 得到 '\(code)'（非 2 键）")
        continue
    }
    let back = FlypyCodec.decode(code)
    if back == [sy] { rtOK += 1 } else {
        rtBad.append("\(sy) → \(code) → \(back.joined(separator: "/"))")
    }
}
print("  可逆 \(rtOK) / \(PinyinSyllable.all.count) 个音节")
if rtBad.isEmpty {
    print("  ✅ 全量音节往返一致")
} else {
    // 已逐个定性的 7 个例外（非笼统「固有」，不得含糊）：
    //   · hm / m / n —— 叹词无韵母，双拼定长 2 键本质上无法表示（方案边界）
    //   · lo / lve / nve / rua —— 小鹤键位重码（l 键兼 iang/uang、t 键兼 ue/üe 等）
    // 这 7 个均为极低频音节，不影响日常输入；但数量上涨就是回归（阈值 10）。
    print("  ⚠️ \(rtBad.count) 个音节不可逆（已定性：叹词无韵母 + 小鹤重码）：")
    for b in rtBad.prefix(15) { print("     · \(b)") }
    if rtBad.count > 10 {
        failures.append("往返不可逆音节 \(rtBad.count) 个，超过阈值 10（基线 7）")
    }
}

// ── 默认参数不得写死方案 ──────────────────────────────────────────────
// 坑（已定性两次）：search/query 的 scheme 默认参数曾写死 .pinyin，
//   调用方漏传就静默按全拼查 —— 不报错，只是候选不对，极难定位。
//   iOS 键盘硬编码 .pinyin 是同一根因。这里用行为断言锁住。
print("\n=== 默认参数跟随产品默认方案 ===")
for code in ["nihc", "womf", "vsgo"] {
    let implicit = PinyinEngine.shared.query(code)
    let explicit = PinyinEngine.shared.query(code, scheme: InputScheme.default)
    let same = implicit.count == explicit.count
        && zip(implicit, explicit).allSatisfy { $0.word == $1.word }
    if !same {
        failures.append("query(\"\(code)\") 省略 scheme 与显式传 InputScheme.default 不等价"
            + "（隐式 \(implicit.count) 条 / 显式 \(explicit.count) 条）")
    }
    // 反向保险：默认若退回全拼，双拼码查不到 → implicit 为空
    if implicit.isEmpty {
        failures.append("默认方案下双拼码 \(code) 无候选 —— 默认可能退回了全拼")
    }
    print("  \(code) → 隐式 \(implicit.count) 条 / 显式 \(explicit.count) 条 \(same ? "✓" : "✗")")
}

// ── 小鹤零声母：o 引导（用户是多年小鹤用户，此处错一个字都不能用）────
// 坑（已定性）：原实现是 aa/ad/aj/ah/ac + ee/ew/ef/eg + oo/oz，
//   即「零声母 = 韵母首字母 + 韵母键」—— 这是**自然码/微软双拼**规则，不是小鹤。
//   后果：oa(啊)/od(爱)/oj(安)/of(恩) 全部落空，只有 oz(欧) 恰好撞对。
// 小鹤规则：统一用 o 引导。这 12 个是零声母全集，缺一个用户就会撞上。
print("\n=== 小鹤零声母 o 引导 ===")
let zeroCases: [(String, String)] = [
    ("oa", "a"), ("od", "ai"), ("oj", "an"), ("oh", "ang"), ("oc", "ao"),
    ("oe", "e"), ("ow", "ei"), ("of", "en"), ("og", "eng"), ("or", "er"),
    ("oo", "o"), ("oz", "ou"),
]
for (code, syl) in zeroCases {
    let decoded = FlypyCodec.decodeSyllable(code)
    if decoded != syl {
        failures.append("零声母 \(code) 应解码为 \(syl)，实得 \(decoded ?? "nil")")
    }
    // 反向：encode 必须能从音节回到该码（往返一致）
    if let back = FlypyCodec.encode(syl), back != code {
        failures.append("零声母 encode(\(syl)) 应得 \(code)，实得 \(back)")
    }
}
print("  12 个零声母音节往返检查完毕")

// 零声母参与组词（词首/词尾都要能用）
print("\n=== 零声母组词 ===")
let zeroWordCases: [(String, String)] = [
    ("ojqr", "安全"), ("ojpd", "安排"), ("orqp", "而且"), ("odhc", "爱好"),
    ("ozvz", "欧洲"), ("oewd", "额外"), ("vioj", "治安"), ("yibj", "一般"),
]
for (code, word) in zeroWordCases {
    let r = PinyinEngine.shared.query(code, scheme: .flypy)
    if r.first?.word != word {
        failures.append("零声母组词 \(code) 首选应为 \(word)，实得 \(r.first?.word ?? "空")")
    }
}
print("  8 个零声母组词检查完毕")

// ── 全拼保留但不首选（用户明确要求）────────────────────────────────
// 双拼精确命中时，全拼结果不得抢占首选 —— 双拼用户盲打，
// 首选被顶掉会直接上错字。
print("\n=== 双拼首选不被全拼抢占 ===")
for (code, word) in [("nihc", "你好"), ("womf", "我们"), ("vsgo", "中国"),
                     ("ufme", "什么"), ("ybww", "因为"), ("mktm", "明天")] {
    let r = PinyinEngine.shared.query(code, scheme: .flypy)
    if r.first?.word != word {
        failures.append("双拼 \(code) 首选应为 \(word)，实得 \(r.first?.word ?? "空")（可能被全拼抢占）")
    }
}
print("  6 个双拼全码首选检查完毕")

print("\n=== 结果 ===")
if failures.isEmpty {
    print("全部通过 ✅")
    exit(0)
} else {
    print("失败 \(failures.count) 项：")
    for f in failures { print("  · \(f)") }
    exit(1)
}
