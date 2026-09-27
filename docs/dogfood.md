# Dogfood 两周观测协议（自用版）

> 目的：回答「这个 App 我到底用没用起来」——入库摩擦多大、提醒来了动不动。
> 原则：端侧 JSONL、不上云、日志失败静默（可观测性永远不能影响产品功能）。

## 真机日用安装（2026-09-27，决策见 docs/adr/0006-debug-profile-for-daily-install.md）

- **设备**：HUAWEI Mate 80 Pro Max（API 26，无线 HDC `192.168.6.131:45507`）
- **签名**：debug Profile，有效期至 **2027-08-19**；材料在 `~/.ohos/config/default_keepfresh_*.p7b/.cer/.p12`
- **安装/更新命令**（覆盖安装不清数据，前提设备已开 USB/无线调试）：

```bash
devecocli run --module entry --device 192.168.6.131:45507 --product default --build-mode debug
```

- **验收记录**：安装后 `materials` 表 8 行保留、usage_log 连续、UI 树显示 `6项 · 1过期 · 0临期`。
- **约束**：调试包只能装到 Profile 登记的 2 台设备；换机先「设置 → 数据备份 → 导出备份」再迁。

## 观测什么（事件协议）

| 事件 | 字段 | 回答的问题 |
|---|---|---|
| `app_open` | — | 每天打开几次？活跃规律？ |
| `item_added` | name, via(barcode/suggestion/manual), is_edit, duration_ms, shelf_life_days, months_mode | **入库摩擦**：每件多久录完？预填功能用没用？手动占比多高？ |
| `suggestion_shown` / `suggestion_applied` | name | 同名预填（P0）出现率 vs 采纳率 |
| `notification_clicked` | level(expired/expiring) | 提醒来了点不点（P0.5 有效性） |
| `reminder_published` | expired, near | 提醒实际发出的频率 |
| `status_changed` | name, status(opened/empty/discarded/active) | 提醒→行动转化；`discarded` 即浪费信号（月报数据源） |
| `item_deleted` | name | 删除行为 |

## 两周后怎么拉日志（给执行 AI 的指令）

日志文件在应用沙箱：`<filesDir>/usage_log.jsonl`。模拟器/真机插着 USB 时：

```bash
export MSYS_NO_PATHCONV=1
HDC="C:\Program Files\Huawei\DevEco Studio\sdk/default/openharmony/toolchains/hdc.exe"

# 1. 确认设备在线
"$HDC" list targets

# 2. 直查已知沙箱路径（filesDir = /data/app/el2/100/base/<bundle>/haps/entry/files）
LOG=/data/app/el2/100/base/com.jaredshuai.keepfresh/haps/entry/files/usage_log.jsonl
"$HDC" shell "cat $LOG"

# 3. 或整文件拉回本地
"$HDC" file recv $LOG .wf-tmp/usage_log.jsonl

# 4. 快速摘要（入库数/途径分布/建议采纳率/提醒点击/丢弃数）
python - <<'EOF'
import json
from collections import Counter
events = [json.loads(l) for l in open('.wf-tmp/usage_log.jsonl', encoding='utf-8')]
c = Counter(e['event'] for e in events)
print('事件分布:', dict(c))
adds = [e for e in events if e['event'] == 'item_added' and not e.get('is_edit')]
if adds:
    print('新增 %d 件，途径 %s，中位时长 %dms' % (
        len(adds),
        dict(Counter(a['via'] for a in adds)),
        sorted(a['duration_ms'] for a in adds)[len(adds)//2]))
shown = sum(1 for e in events if e['event'] == 'suggestion_shown')
applied = sum(1 for e in events if e['event'] == 'suggestion_applied')
print(f'同名建议: 出现 {shown} 次，采纳 {applied} 次')
print('通知点击:', c.get('notification_clicked', 0), '丢弃(浪费):',
      sum(1 for e in events if e.get('status') == 'discarded'))
EOF
```

若第 2 步 `find` 无输出（沙箱权限受限的真机场景），备用路径：设置页手工导出
（`导出使用日志` 入口，走 DocumentViewPicker 存到可访问目录）。

## 分析时的注意事项

- `duration_ms` 含页面打开到点保存的全部时间（含被切走的时间），长尾不可信，看中位数；
- `suggestion_shown` 在每次建议出现时记录，同一次输入会话只记一次；
- 日期跨天会让 expires 数字变化，分析时以事件 `ts` 为准，不要拿截图对比；
- 日志只增不改，轮转阈值 5000 行 / 512KB，两周自用量级远低于此。

## 何时算验证通过

两周后按上面脚本出数，如果：
- 每周新增 ≥ 10 件（说明录入摩擦可接受）；
- suggestion 采纳率 ≥ 50%（P0 成立）；
- `notification_clicked` / `reminder_published` ≥ 30%（P0.5 成立）；
- `discarded` 数量在下降通道。

四条满足三条即认为产品-行为闭环成立，继续迭代；否则优先砍录入步骤而不是加功能。
