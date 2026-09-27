# 诗韵 · 全唐宋诗 · 平水韵查询

[![Godot](https://img.shields.io/badge/Godot-4.7-478cbf?logo=godotengine&logoColor=white)](https://godotengine.org)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

一款用 **Godot 4** 编写的桌面小工具：**输入一个汉字，考其《平水韵》韵部，并徵引《全唐诗》《全宋诗》中所有用到该字的诗句。**

界面取意古刻——宣纸为底，楷宋为字，朱印为饰。

```
輸入一字　考其韻部　徵唐宋之句
```

## 功能

- **韵部考订**：查字所属的平水韵韵部（上平／下平／上声／去声／入声），并列出同韵部的全部韵字，韵字可点击继续追查。
- **诗句徵引**：列出唐宋诗中所有含该字的诗句，标注出处《诗题》· 作者，点击可弹出全诗并高亮命中的那一句。
- **范围收窄**：可按朝代（全唐宋诗／全唐诗／全宋诗）与诗人名进一步筛选。
- **增量渲染**：命中过多时分页呈现，每次 600 句，随点随出，界面不卡顿。
- **本机运行**：全部数据离线，无网络请求。

数据规模：**诗 311,855 首 · 句 1,365,284 条 · 平水韵字 8,996 个尾字索引**。

## 运行

需要 [Godot 4.7](https://godotengine.org/download)（标准版，非 .NET 版）。

```bash
# 用编辑器打开
godot --path .

# 直接运行主场景
godot --path . res://Main.tscn
```

也可以导出为单文件可执行程序（导出预设名 `shiyun`，Windows Desktop）。

> **首次启动较慢？** 若 `data/index.bin` 不存在，程序会自动回退到逐份解析 `data/shi/*.json`（界面会显示进度）。建议先构建二进制索引，见下节。

## 构建索引（推荐）

```bash
godot --headless --path . --script res://tools/build_index.gd
```

该脚本把 `data/shi/poet.*.json` 预编译为 `data/index.bin`，加载时间由「逐份解析 JSON」降为「一次反序列化」，启动速度与内存占用都显著改善。

`data/index.bin` 属于构建产物（约 93 MB），已在 `.gitignore` 中忽略。

## 自测

```bash
godot --headless --path . --script res://tools/selftest.gd
```

覆盖数据加载、查询、朝代／诗人筛选、正文重建、BBCode 转义、字体层级、韵字跳转、全诗弹层开阖与高亮等 29 项断言，全部通过时输出 `ALL PASS`。

## 目录结构

```
DataStore.gd            纯数据层：索引加载（二进制优先，JSON 兜底）、序列化、查询
Main.gd                 界面层：主题、布局、查询状态与渲染
Main.tscn               主场景
paper.gdshader          宣纸质感着色器（渐变 + 云纹 + 颗粒 + 纸纤维 + 晕影）
data/shi/               全唐诗（58 份）、全宋诗（255 份）JSON
data/yun/pingshuiyun.json   平水韵表
data/index.bin          预编译二进制索引（构建产物，不入库）
tools/build_index.gd    索引构建脚本
tools/selftest.gd       自测脚本
```

### 数据层设计

采用**平行 PackedArray**（而非 `Array[Dictionary]`）存放诗题、作者、朝代、句区间，并以「句 → 诗」反向指针重建正文，避免重复存储诗文本身；末字建 `字 → 句 id 列表` 倒排索引，因此按字检索是 O(命中数) 而非全表扫描。

## 数据来源

- 唐宋诗文本：**中华诗词（chinese-poetry）** 数据集中的《全唐诗》《全宋诗》—— <https://github.com/chinese-poetry/chinese-poetry>
- 韵表：`data/yun/pingshuiyun.json`，《平水韵》韵部字表。

诗词原文均为公有领域的古代文献；数据集的整理与结构化工作归功于上述项目。若用于商业用途，请自行核实数据集的授权条款。

## 许可

本项目代码以 [MIT License](LICENSE) 开源，Copyright (c) 2026 YuRos2。
