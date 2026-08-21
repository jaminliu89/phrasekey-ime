#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 PhraseKey 内置基础词库 dict.tsv（格式：全拼\t词\t词频）。
内置常用单字 + 常用双字词/短语，够演示；完整词库用户可放
~/Library/Application Support/PhraseKey/user_dict.tsv 扩展。
"""
import os, unicodedata

BASE = os.path.join(os.path.dirname(__file__), "..", "Sources", "PhraseKeyIME", "Resources")
os.makedirs(BASE, exist_ok=True)

# ---- 常用单字（字: 拼音, 词频）----
single_chars = {
    "我": ("wo", 900000), "你": ("ni", 850000), "他": ("ta", 800000), "她": ("ta", 700000),
    "的": ("de", 990000), "了": ("le", 880000), "是": ("shi", 870000), "在": ("zai", 800000),
    "有": ("you", 760000), "和": ("he", 750000), "就": ("jiu", 720000), "不": ("bu", 710000),
    "人": ("ren", 700000), "都": ("dou", 680000), "一": ("yi", 670000), "一个": ("yi ge", 500000),
    "们": ("men", 640000), "说": ("shuo", 620000), "到": ("dao", 610000), "来": ("lai", 600000),
    "去": ("qu", 590000), "能": ("neng", 580000), "会": ("hui", 570000), "要": ("yao", 560000),
    "好": ("hao", 550000), "很": ("hen", 540000), "没": ("mei", 530000), "让": ("rang", 520000),
    "看": ("kan", 510000), "想": ("xiang", 500000), "请": ("qing", 490000), "帮": ("bang", 400000),
    "做": ("zuo", 480000), "用": ("yong", 470000), "给": ("gei", 460000), "从": ("cong", 450000),
    "这": ("zhe", 440000), "那": ("na", 430000), "下": ("xia", 420000), "上": ("shang", 410000),
    "今天": ("jin tian", 300000), "明天": ("ming tian", 260000), "现在": ("xian zai", 250000),
    "谢谢": ("xie xie", 240000), "可以": ("ke yi", 230000), "需要": ("xu yao", 220000),
    "工作": ("gong zuo", 210000), "时间": ("shi jian", 200000), "问题": ("wen ti", 190000),
    "我们": ("wo men", 380000), "你们": ("ni men", 250000), "他们": ("ta men", 240000),
    "因为": ("yin wei", 230000), "所以": ("suo yi", 220000), "但是": ("dan shi", 210000),
    "如果": ("ru guo", 200000), "然后": ("ran hou", 190000), "知道": ("zhi dao", 180000),
    "觉得": ("jue de", 170000), "开始": ("kai shi", 160000), "结束": ("jie shu", 150000),
    "朋友": ("peng you", 140000), "老师": ("lao shi", 130000), "学习": ("xue xi", 120000),
    "项目": ("xiang mu", 110000), "产品": ("chan pin", 100000), "数据": ("shu ju", 90000),
    "系统": ("xi tong", 80000), "测试": ("ce shi", 70000), "发布": ("fa bu", 60000),
}

# ---- 常用双字词/短语（词: (拼音, 词频)）----
phrases = {
    "你好": ("ni hao", 500000), "早上好": ("zao shang hao", 200000), "晚上好": ("wan shang hao", 200000),
    "中午好": ("zhong wu hao", 150000), "辛苦了": ("xin ku le", 150000), "没关系": ("mei guan xi", 140000),
    "没问题": ("mei wen ti", 130000), "收到": ("shou dao", 120000), "好的": ("hao de", 110000),
    "好的谢谢": ("hao de xie xie", 100000), "明白了": ("ming bai le", 90000), "等一下": ("deng yi xia", 80000),
    "不好意思": ("bu hao yi si", 70000), "麻烦你": ("ma fan ni", 65000), "非常感谢": ("fei chang gan xie", 60000),
    "稍后联系": ("shao hou lian xi", 50000), "合作愉快": ("he zuo yu kuai", 45000),
    "新年快乐": ("xin nian kuai le", 40000), "生日快乐": ("sheng ri kuai le", 40000),
    "恭喜发财": ("gong xi fa cai", 30000), "周末愉快": ("zhou mo yu kuai", 30000),
    "人工智能": ("ren gong zhi neng", 80000), "大语言模型": ("da yu yan mo xing", 50000),
    "机器学习": ("ji qi xue xi", 40000), "开源社区": ("kai yuan she qu", 30000),
    "开源协议": ("kai yuan xie yi", 25000), "输入法": ("shu ru fa", 20000),
    "常用语": ("chang yong yu", 15000), "剪贴板": ("jian tie ban", 12000),
    "快捷键": ("kuai jie jian", 15000), "浏览器": ("liu lan qi", 18000),
    "微信": ("wei xin", 100000), "支付宝": ("zhi fu bao", 30000), "手机号码": ("shou ji hao ma", 20000),
    "电子邮件": ("dian zi you jian", 20000), "通讯录": ("tong xun lu", 15000),
    "负责人": ("fu ze ren", 12000), "会议纪要": ("hui yi ji yao", 10000),
}

def main():
    lines = []
    for ch, (py, freq) in single_chars.items():
        lines.append(f"{py}\t{ch}\t{freq}")
    for word, (py, freq) in phrases.items():
        lines.append(f"{py}\t{word}\t{freq}")
    out = os.path.join(BASE, "dict.tsv")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"✅ 已生成基础词库：{out}（{len(lines)} 条）")

if __name__ == "__main__":
    main()
