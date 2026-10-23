"""生成键盘用的拼音词库 ios/PinyinKit/Sources/PinyinKit/Resources/pinyin_dict.tsv。

数据来源（均为 MIT 许可）：
- jieba 0.42.1 的 dict.txt：词语与词频
- pypinyin 0.55.0 的 pinyin_dict.json / phrases_dict.json：单字与词语读音
- opencc-python-reimplemented 0.1.7 的 TSCharacters.txt（Apache-2.0）：只在生成时用来认出繁体字，不打进 App

用法：
    pip download --no-deps jieba==0.42.1 pypinyin==0.55.0 opencc-python-reimplemented==0.1.7 -d dl
    解压后运行：
    python3 tools/build_pinyin_dict.py <jieba/dict.txt> <pypinyin 包目录> <输出路径> <opencc/dictionary/TSCharacters.txt>

收字范围：基本区和扩展 A 区的全部汉字（约 2.6 万个，含生僻字）。GB2312 常用字按 jieba 词频排，
其余简体生僻字排在同音常用字后面，繁体字再往后。词语只收全是简体字的。

tools/chat_words.txt 里的聊天常用词会把词频提到至少 CHAT_MIN_FREQ（jieba 来自新闻语料，
“你好”“喜欢”这类词偏低，简拼时会被“南海”“先后”压下去）。

输出每行：以空格分隔的无声调拼音<TAB>词<TAB>词频。ü 写作 v。
"""

import json
from pathlib import Path
import sys
import unicodedata

MAX_WORD_LEN = 4
MAX_WORDS = 120_000
CHAT_MIN_FREQ = 20_000
CHAT_WORDS = Path(__file__).with_name("chat_words.txt")
# 非 GB2312 的简体生僻字统一用这个词频（繁体为 1），保证排在同音常用字后面
RARE_FREQ = 2


def plain(syllable: str) -> str:
    syllable = syllable.replace("ü", "v").replace("ǖ", "v").replace("ǘ", "v").replace("ǚ", "v").replace("ǜ", "v")
    decomposed = unicodedata.normalize("NFD", syllable)
    return "".join(c for c in decomposed if not unicodedata.combining(c)).lower()


def is_cjk(ch: str) -> bool:
    """基本区和扩展 A 区。扩展 B 以后的字很多手机字体显示不出来，不收。"""
    code = ord(ch)
    return 0x4E00 <= code <= 0x9FFF or 0x3400 <= code <= 0x4DBF


def load_traditional(ts_characters: str) -> set[str]:
    """TSCharacters 每行：繁体字<TAB>对应的简体字（可能有多个）。首选简体和自己不同的才算繁体。"""
    traditional = set()
    with open(ts_characters, encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 2 and parts[1] != parts[0]:
                traditional.add(parts[0])
    return traditional


TRADITIONAL: set[str] = set()


def is_common(text: str) -> bool:
    """GB2312 汉字区的常用字。"""
    try:
        text.encode("gb2312")
    except UnicodeEncodeError:
        return False
    return all(is_cjk(c) for c in text)


def is_hanzi(text: str) -> bool:
    """全是简体汉字（基本区或扩展 A 区，且不是繁体字）。"""
    return bool(text) and all(is_cjk(c) and c not in TRADITIONAL for c in text)


def main(jieba_dict: str, pypinyin_dir: str, out_path: str, ts_characters: str) -> None:
    TRADITIONAL.update(load_traditional(ts_characters))
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

    for line in CHAT_WORDS.read_text(encoding="utf-8").splitlines():
        if line.startswith("#"):
            continue
        for word in line.split():
            if is_hanzi(word) and len(word) <= MAX_WORD_LEN:
                freqs[word] = max(freqs.get(word, 0), CHAT_MIN_FREQ)

    rows: list[tuple[str, str, int]] = []

    # 单字：所有读音都收录，保证多音字可打
    for ch, readings in char_readings.items():
        if not is_cjk(ch):
            continue
        # 常用字（GB2312）按词频排；其余简体生僻字一律排在常用字后面，繁体再往后
        if is_common(ch):
            freq = freqs.get(ch, 1)
        else:
            freq = RARE_FREQ if is_hanzi(ch) else 1
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
    main(*sys.argv[1:5])
