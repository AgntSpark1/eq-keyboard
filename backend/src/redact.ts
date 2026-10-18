// 发给模型之前抹掉明显的个人信息。客户端也会做一遍，这里是兜底。
const PATTERNS: Array<[RegExp, string]> = [
  [/[\w.+-]+@[\w-]+\.[\w.-]+/g, "[邮箱]"],
  [/\b\d{17}[\dXx]\b/g, "[证件号]"],
  [/(?<!\d)1[3-9]\d{9}(?!\d)/g, "[手机号]"],
  [/\+?\d[\d\s-]{8,}\d/g, "[电话]"],
];

export function redact(text: string): string {
  return PATTERNS.reduce((out, [re, label]) => out.replace(re, label), text);
}
