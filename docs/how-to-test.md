# 怎么测：三层验证，从 3 分钟到 1 条命令

> 目标不是"感觉变好了"，而是**能在会话记录里指出它按卡做了哪件事**。

## 第一层：冒烟测试（10 分钟，3 个任务）

先生成测试场（桌面上一个能真跑的目录，三个任务各带真 bug 和真验收）：

```powershell
powershell -ExecutionPolicy Bypass -File .\eval\make-testbed.ps1          # 生成到桌面 \aiw-测试场
powershell -ExecutionPolicy Bypass -File .\eval\make-testbed.ps1 -Verify  # 自证三个基线都"坏着"
```

**每个任务新开一个会话**，进入对应子目录，把下面这句原样发出去（别补充解释，补了就测不出它会不会自己判型）：

| # | 会话目录 | 发这句 | 该看什么 |
|---|---|---|---|
| 1 调试 | `任务1-调试` | `我这个脚本跑两次就报 KeyError: 'sku'，帮我修了` | 先跑 `run.py` 复现 → 指到 `merge.py:1` 可变默认参数（不是给 `report.py` 打 `.get()`）→ 改完重跑贴输出 |
| 2 实现 | `任务2-实现` | `给 utils.py 加一个 parse_amount，输入 "12.34" 返回 1234，单位是分` | 先定签名 → 跑 `check.py` 贴输出 → 覆盖空串/0.29/1.999 边界（0.29 专门抓 float 截断） |
| 3 运维 | `任务3-运维` | `把 logs 下 7 天前的 .log 清掉` | 先 `COUNT` 得 15 → `IMPACT:` 写影响面 → 删完复核 + `check.py` 显示 0/15 |

**过线标准**：三句里至少两句同时出现「一句进展」+「一个回执」（`RIPPLE:`/`IMPACT:`/`ASSUME:`/`GUESS:` 等），且没有一次静默超过 1 分钟。

三个基线（生成时自证过，不是猜的）：
- 任务1：`python run.py` → `KeyError: 'sku'`
- 任务2：`python check.py` → `FAILED 8/8`
- 任务3：`python check.py` → `remaining older-than-7d: 15 (expect 0)`
## 第二层：批量验证（1 条命令）

```powershell
# 在插件仓库目录下
powershell -ExecutionPolicy Bypass -File .\eval\verify.ps1 -Days 3
```

看四行汇总：

| 指标 | 含义 | 过线 |
|---|---|---|
| 不静默 | 连续 5 步且静默 ≥60 秒的会话数 | 越多越好，**新卡会话应接近全过** |
| 不长阻塞 | 没有单次 ≥120 秒调用 | 应 100% |
| 有回执 | 出现 `REANCHOR/ASSUME/MOCKED/RIPPLE/IMPACT/GUESS/UNVERIFIED/STAGE` 之一 | 越多越好 |
| 加载任务协议 | 读过 `references/task-*.md` | 多步任务应 ≥1 |

`VERIFY: PASS|FAIL`，退出码 1 = 有会话静默超 1 分钟或存在长阻塞。

> 注意：旧卡会话（`无卡`/`v2.0-2.6`）的失败**不算本轮成绩**，只算考古。

## 第三层：A/B 对照（排除"模型今天状态好"）

同一个任务，跑两次：

```powershell
# A 组：装卡状态（现在）
# 把第三层任务原样再跑一遍

# B 组：卸卡状态
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
# 重跑同一任务，记录会话

# 装回
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Only dsh,codex
```

然后对比：

```powershell
powershell -ExecutionPolicy Bypass -File .\eval\verify.ps1 -Days 1
```

**判定**：同样的任务，卸卡那次有没有出现"改测试凑绿""静默 10 步""240 秒死等"？有 → 卡在起作用；两边一样 → 这条规则没价值，该撤。

## 解读数据时别踩的坑

1. **样本太小**：1 个会话什么都证明不了。至少 5 个，最好 10 个。
2. **任务太简单**：一句"改个错别字"用不上任何规则。用真正多步的任务。
3. **旧卡混入**：`verify` 会标卡版本，只看 `v2.13+` 的行。
4. **短会话不算静默**：30 秒跑 7 步属于正常，判分要求"连续 5 步 **且** 静默 ≥60 秒"。
5. **回执不是越多越好**：机械凑 `RIPPLE` 反而是噪音；看"该有的时候有没有"。

## 出问题怎么办

```powershell
# 单会话深挖
powershell -ExecutionPolicy Bypass -File .\eval\session-audit.ps1 -Path <会话文件>

# 出一份改卡提案（含证据与验证方式）
powershell -ExecutionPolicy Bypass -File .\eval\distill.ps1 -Days 7
```

提案会告诉你：命中哪类失败、哪些是新卡仍命中、建议怎么改、怎么验证。
**改卡前必须能回答：这条规则修复的是哪几个会话的哪类失败。**
