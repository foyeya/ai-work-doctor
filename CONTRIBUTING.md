# 贡献指南（ai工作医生 / ai-work-doctor）

这个项目的价值来自**克制**：规则越少越硬，越有人真的执行。所以贡献的第一原则是"能不加就不加"。

## 加一条规则前的硬门槛（反膨胀 5 条）

1. **三要素缺一不可**：`触发条件` + `具体动作` + `数字上限`。写不出数字上限的，是口号，不收。
2. **常驻卡里每条只能一行，且不许出现代码块**（示例放 SKILL.md 正文或 `references/`）。
3. **删掉它 agent 行为不变的，不收**（纯解释、纯理由、纯提醒都算）。
4. **同一场景只留一条规则**：新的和旧的能合并就合并，不允许两条讲同一件事。
5. **零和**：常驻卡硬顶 30 行。要加一行，必须删掉一行。

## 改动的落点

| 你想改什么 | 改哪里 |
|---|---|
| 常驻卡（每轮对话都在上下文里的那 14 条） | `SKILL.md` 的 `<!-- AIW_CORE:START -->…<!-- AIW_CORE:END -->` 之间 |
| 规则的详细触发/动作/反例 | `SKILL.md` 正文 R1–R14 |
| 某个平台/命令的具体坑（GBK、路径、端口、镜像源…） | `references/desktop-cn.md` |
| 安装行为（注入哪些宿主、怎么写、怎么卸载） | `install.ps1` + `install.sh`（两边要同步改） |

常驻卡是**单一来源**：安装脚本从 `SKILL.md` 抽取，不要在脚本里再抄一份规则文本。

## 提交前自测

```bash
# 1) PowerShell 语法 + BOM（Windows PowerShell 5.1 解析中文 .ps1 必须有 BOM）
pwsh -NoProfile -Command "& { \$e=\$null; [void][System.Management.Automation.Language.Parser]::ParseFile('install.ps1',[ref]\$null,[ref]\$e); if(\$e.Count){\$e; exit 1}; 'parse ok' }"
# 2) bash 语法
bash -n install.sh
# 3) 沙箱试跑（不要拿真实用户目录试）
pwsh -File ./install.ps1 -Root /tmp/aiw-test -DryRun
./install.sh --root /tmp/aiw-test -n
```

沙箱试跑必须验证这 6 件事：

- [ ] 注入一次后再跑一遍，文件**字节不变**（幂等）
- [ ] `-Uninstall` 后用户原有内容**逐字不变**
- [ ] 含中文的 UTF-8 文件写入后**不带 BOM**
- [ ] GBK 老文件读写后**仍是 GBK**，中文不乱码
- [ ] 未检测到的宿主**不创建目录**
- [ ] `-Root` 指定时，`Documents` 等特殊路径**不跑出沙箱**

## 新增宿主支持

必须有**官方文档或源码**作为证据（在 PR 描述里贴链接）。查不到证据就不要写 — 宁可写进
`INSTALL.md` 的"手动兜底"，也不要猜一个路径：错的路径会静默失效，比不支持更糟。

## 发布流程（维护者）

1. 改 `SKILL.md` 的 `metadata.version` 与 `CHANGELOG.md`。
2. 跑 `.github/workflows/validate.yml` 的全部检查。
3. `INSTALL.md` 里的 `foyeya` 占位符全部替换。
4. 打 tag `vX.Y.Z`，Release 附件上传 `ai-work-doctor-vX.Y.Z.zip`（zip 内目录名保持 ASCII）+ `SHA256SUMS.txt`。
5. 老版本 zip 从工作区清掉。
