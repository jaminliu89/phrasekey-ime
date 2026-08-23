import Foundation

/// 小鹤双拼（flypy）编解码。
///
/// 键位规则（官方小鹤双拼）：
///   - 声母：zh→v, ch→i, sh→u，其余字母=自身（b p m f d t n l g k h j q x z c s r y w）
///   - 韵母键位：
///     q=iu  w=ei  e=e  r=uan/er  t=ue  y=un  u=u  i=i  o=uo/o  p=ie
///     a=a  s=ong/iong  d=ai  f=en  g=eng  h=ang  j=an  k=ing/uai
///     l=iang/uang  z=ou  x=ia/ua  c=ao  v=ui/ü  b=in  n=iao  m=ian
///   - 零声母（a/o/e 开头）：首字母 + 韵母键，如 安=aj、爱=ad、恩=ef
enum FlypyCodec {

    // MARK: - Key Table

    /// Initial key → initial
    static let initialMap: [Character: String] = [
        "v": "zh", "i": "ch", "u": "sh",
        "b": "b", "p": "p", "m": "m", "f": "f", "d": "d", "t": "t", "n": "n",
        "l": "l", "g": "g", "k": "k", "h": "h", "j": "j", "q": "q", "x": "x",
        "z": "z", "c": "c", "s": "s", "r": "r", "y": "y", "w": "w"
    ]

    /// Final key → final (primary reading; special handling for ü/üe see decode)
    static let finalMap: [Character: String] = [
        "a": "a", "b": "in", "c": "ao", "d": "ai", "e": "e", "f": "en",
        "g": "eng", "h": "ang", "i": "i", "j": "an", "k": "ing", "l": "iang",
        "m": "ian", "n": "iao", "o": "uo", "p": "ie", "q": "iu", "r": "uan",
        "s": "ong", "t": "ue", "u": "u", "v": "ui", "w": "ei", "x": "ia",
        "y": "un", "z": "ou"
    ]

    /// Zero-initial syllable shuangpin code table (first letter + final key)
    /// 零声母音节表 —— **小鹤双拼规则：统一用 `o` 作为零声母引导键**。
    ///
    /// 坑（已定性，用户是多年小鹤用户，第一分钟即撞上）：
    ///   原实现是 `aa/ad/aj/ah/ac` + `ee/ew/ef/eg` + `oo/oz`，
    ///   即「零声母 = 该韵母首字母 + 韵母键」—— **这是自然码/微软双拼的规则，不是小鹤**。
    ///   后果：小鹤用户打 oa(啊)/od(爱)/oj(安)/of(恩) 全部落空，只有 oz(欧) 恰好撞对。
    ///
    /// 小鹤零声母规则（官方 flypy 键位）：`o` + 韵母键
    ///   a→oa  ai→od  an→oj  ang→oh  ao→oc
    ///   e→oe  ei→ow  en→of  eng→og  er→or
    ///   o→oo  ou→oz
    /// 注意 er=or 与「声母 r」无冲突：r 的韵母键位下 o+r 只可能是 er。
    static let zeroSyllables: [String: String] = [
        "oa": "a",  "od": "ai", "oj": "an", "oh": "ang", "oc": "ao",
        "oe": "e",  "ow": "ei", "of": "en", "og": "eng", "or": "er",
        "oo": "o",  "oz": "ou"
    ]

    /// 韵母（全拼）→ 键（编码方向，含多音代表）
    /// 注 "v"：音节表里 ü 写作 v（lü → lv），不补这个键会导致 lv/nv/lve/nve
    /// encode 得到空串（经全量音节往返扫描抓到）。
    static let finalToKey: [String: String] = [
        "a": "a", "in": "b", "ao": "c", "ai": "d", "e": "e", "en": "f",
        "eng": "g", "ang": "h", "i": "i", "an": "j", "ing": "k",
        "iang": "l", "uang": "l", "ian": "m", "iao": "n", "uo": "o", "o": "o",
        "ie": "p", "iu": "q", "uan": "r", "er": "r", "ong": "s", "iong": "s",
        "ue": "t", "ve": "t", "\u{00fc}e": "t", "u": "u", "ui": "v",
        "\u{00fc}": "v", "v": "v", "ei": "w",
        "ia": "x", "ua": "x", "un": "y", "ou": "z", "uai": "k"
    ]

    static let initialKeys = Set(initialMap.keys)

    /// v 键在 j/q/x/y/n/l 后读 ü，否则读 ui（小鹤规则）
    static let uiBecomesU: Set<Character> = ["j", "q", "x", "y", "n", "l"]

    /// 双韵母键的上下文选择：uang/ua/uai 只出现在 g/k/h/zh/sh/ch 后，iong 只出现在 j/q/x 后
    private static let uangUaUaiInitials: Set<String> = ["g", "k", "h", "zh", "sh", "ch"]
    private static let iongInitials: Set<String> = ["j", "q", "x"]

    /// 按声母上下文决定韵母（处理 k=ing/uai, l=iang/uang, s=ong/iong, x=ia/ua, o=uo）
    static func finalFor(initial: String, key k2: Character) -> String? {
        switch k2 {
        case "k": return uangUaUaiInitials.contains(initial) ? "uai" : "ing"
        case "l": return uangUaUaiInitials.contains(initial) ? "uang" : "iang"
        case "s": return iongInitials.contains(initial) ? "iong" : "ong"
        case "x": return uangUaUaiInitials.contains(initial) ? "ua" : "ia"
        case "o": return "uo"
        default: return finalMap[k2]
        }
    }

    // MARK: - Decode (Shuangpin → Pinyin)

    /// 解码单个双拼音节（恰好 2 键），失败返回 nil。
    ///
    /// 坑（经回归断言抓到）：encode/decode 曾不可逆。
    ///   wo → encode 得 "wo" → decode 回来却是 "wuo"。
    ///   因为 w 是合法声母键，走声母分支拼出 w + finalFor(o)=uo → "wuo"，
    ///   而汉语拼音里 wo 本身就是完整音节，wuo 根本不存在。
    ///   后果：双拼回退路径（decode 后当全拼查）会拿不存在的键去查字典 → 查不到。
    /// 修：拼出的结果必须过真实 417 音节表校验；不合法时依次回退到
    /// 「去掩音介音」形式（wuo→wo、yi_→...）与零声母表。
    static func decodeSyllable(_ two: String) -> String? {
        let s = two.lowercased()
        let chars = Array(s)
        guard chars.count == 2 else { return nil }
        let k1 = chars[0], k2 = chars[1]

        if initialKeys.contains(k1) {
            if let ini = initialMap[k1] {
                var cand: String?
                // v 键韵母特殊：ü / ui
                if k2 == "v" {
                    cand = uiBecomesU.contains(k1) ? ini + "ü" : ini + "ui"
                } else if let fin = finalFor(initial: ini, key: k2) {
                    cand = ini + fin
                }
                if let c = cand {
                    if PinyinSyllable.isSyllable(c) { return c }
                    // w/y 开头的零声母音节：u/i 作为掩音不单独出现（wuo→wo、yie→ye）
                    if ini == "w", c.hasPrefix("wu"), c.count > 2 {
                        let alt = "w" + c.dropFirst(2)
                        if PinyinSyllable.isSyllable(alt) { return alt }
                    }
                    if ini == "y", c.hasPrefix("yi"), c.count > 2 {
                        let alt = "y" + c.dropFirst(2)
                        if PinyinSyllable.isSyllable(alt) { return alt }
                    }
                }
            }
            // 声母分支未能产出合法音节 → 继续试零声母表（如 er）
        }
        // 零声母音节
        return zeroSyllables[s]
    }

    /// 解码双拼串 → 音节数组（每 2 键一音节）。无法解码的片段原样返回。
    static func decode(_ input: String) -> [String] {
        let s = input.lowercased()
        var out: [String] = []
        var i = s.startIndex
        while i < s.endIndex {
            let next = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
            let two = String(s[i..<next])
            if two.count == 2, let sy = decodeSyllable(two) {
                out.append(sy)
            } else {
                out.append(two)
            }
            i = next
        }
        return out
    }

    // MARK: - Encode (Pinyin → Shuangpin)

    /// 全拼音节 → 双拼两键。零声母按小鹤规则。失败返回 nil。
    static func encode(_ syllable: String) -> String? {
        let s = syllable.lowercased()
        // 零声母：直接查表
        if let zero = zeroSyllables.first(where: { $0.value == s })?.key {
            return zero
        }
        // 找声母（1 或 2 字母）
        let chars = Array(s)
        var initial = ""
        var rest = s
        for len in [2, 1] {
            guard chars.count > len else { continue }
            let cand = String(chars[0..<len])
            let mapped = initialMap.first { $0.value == cand }?.key
            if let key = mapped {
                initial = String(key)
                rest = String(chars[len...])
                break
            }
        }
        guard !initial.isEmpty else { return nil }
        guard let finalKey = finalToKey[rest] else { return nil }
        return initial + finalKey
    }

    /// 一串全拼音节 → 双拼串（用于词库/常用语建双拼索引）
    static func encode(_ syllables: [String]) -> String {
        syllables.compactMap { encode($0) }.joined()
    }
}
