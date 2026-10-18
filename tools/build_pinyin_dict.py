"""生成键盘用的拼音词库 ios/PinyinKit/Sources/PinyinKit/Resources/pinyin_dict.tsv。

数据来源（均为 MIT 许可）：
- jieba 0.42.1 的 dict.txt：词语与词频
- pypinyin 0.55.0 的 pinyin_dict.json / phrases_dict.json：单字与词语读音

用法：
    pip download --no-deps jieba==0.42.1 pypinyin==0.55.0 -d dl
    解压后运行：
    python3 tools/build_pinyin_dict.py <jieba/dict.txt> <pypinyin 包目录> <输出路径>

输出每行：以空格分隔的无声调拼音<TAB>词<TAB>词频。ü 写作 v。
"""

import json
import sys
import unicodedata

MAX_WORD_LEN = 4
MAX_WORDS = 120_000


def plain(syllable: str) -> str:
    syllable = syllable.replace("ü", "v").replace("ǖ", "v").replace("ǘ", "v").replace("ǚ", "v").replace("ǜ", "v")
    decomposed = unicodedata.normalize("NFD", syllable)
    return "".join(c for c in decomposed if not unicodedata.combining(c)).lower()


def is_hanzi(text: str) -> bool:
    """只收简体常用字（GB2312 汉字区），排除繁体和生僻字。"""
    if not all("一" <= c <= "鿿" for c in text):
        return False
    try:
        text.encode("gb2312")
    except UnicodeEncodeError:
        return False
    return True


def main(jieba_dict: str, pypinyin_dir: str, out_path: str) -> None:
    with open(f"{pypinyin_dir}/pinyin_dict.json", encoding="utf-8") as f:
        char_readings = {chr(int(k)): [plain(p) for p in v.split(",")] for k, v in json.load(f).items()}
    with open(f"{pypinyin_dir}/phrases_dict.json", encoding="utf-8") as f:
        phrase_readings = {k: [plain(p[0]) for p in v] for k, v in json.load(f).items()}

    freqs: dict[str, int] = {}
    with open(jieba_dict, encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 2 and is_hanzi(parts[0]) and len(parts[0]) <= MAX_WORD_LEN:
                freqs[parts[0]] = max(freqs.get(parts[0], 0), int(parts[1]))

    rows: list[tuple[str, str, int]] = []

    # 单字：所有读音都收录，保证多音字可打
    for ch, readings in char_readings.items():
        if not is_hanzi(ch):
            continue
        freq = freqs.get(ch, 1)
        for i, reading in enumerate(dict.fromkeys(readings)):
            # 非首选读音降权
            rows.append((reading, ch, freq if i == 0 else max(1, freq // 10)))

    words = sorted((w for w in freqs if len(w) > 1), key=lambda w: -freqs[w])[:MAX_WORDS]
    for word in words:
        if word in phrase_readings and len(phrase_readings[word]) == len(word):
            syllables = phrase_readings[word]
        elif all(c in char_readings for c in word):
            syllables = [char_readings[c][0] for c in word]
        else:
            continue
        rows.append((" ".join(syllables), word, freqs[word]))

    rows.sort(key=lambda r: (r[0], -r[2]))
    with open(out_path, "w", encoding="utf-8") as f:
        for py, word, freq in rows:
            f.write(f"{py}\t{word}\t{freq}\n")
    print(f"wrote {len(rows)} entries to {out_path}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
