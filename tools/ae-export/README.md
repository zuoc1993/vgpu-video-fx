# AE Fixture Export（AE 工具面板）

把 After Effects 里的一个特效导出成**可移植的实验包**：元数据 JSON + 配对的输入/输出帧。
给 coding agent 照着写 WGSL，并用数值 diff 验证（mean / max / pct>2）。

它解决的问题：AE 内置特效和第三方插件的算法是黑盒，agent 光看参数名写不出像素。
有了「同一输入帧 + 同一组参数，AE 吐出什么」这组对照，循环才闭合。

## 它是什么

一个 **ExtendScript ScriptUI 面板**（ae-fixture-export.jsx），不是 C++ AEGP 插件。
面板要做的每件事——枚举特效参数、改值、驱动渲染队列、写文件——ExtendScript 全都有，
而 AEGP 得写一整套 C++ + PiPL + 参数系统。装法上它一样是插件：放进 ScriptUI Panels
目录，出现在 Window 菜单底部，可以像原生面板一样停靠。

## 安装

macOS：把文件拷进 AE 的 ScriptUI Panels 目录（版本目录在 AE 首次启动后才存在）

    D="$HOME/Library/Preferences/Adobe/After Effects"
    V=$(ls "$D" | tail -1)
    mkdir -p "$D/$V/Scripts/ScriptUI Panels"
    cp tools/ae-export/ae-fixture-export.jsx "$D/$V/Scripts/ScriptUI Panels/"

Windows：拷到

    %APPDATA%\Adobe\After Effects\<版本>\Scripts\ScriptUI Panels\

然后重启 AE，在 **窗口（Window）菜单底部**打开它。

临时用一次也可以直接走「文件 > 脚本 > 运行脚本文件」，脚本同时兼容两种入口
（浮动窗口 / 停靠面板）。

## 前置条件

1. **偏好设置 > 常规 >「允许脚本写入文件和访问网络」必须勾上。**
   不勾的话写文件会**静默失败**：文件不生成，也不报错。这是最典型的坑。
2. 项目位深建议 **8 bpc**。面板会读出来并提示；16/32 bpc 和 vgpu 的 RGBA8 管线对不上。
3. 输出 raw 需要 ffmpeg。面板里填**绝对路径**（默认 /opt/homebrew/bin/ffmpeg）——
   GUI 应用不继承你 shell 的 PATH，光写 ffmpeg 会找不到。

## 用法

1. 在时间轴里**激活**一个合成（选中它）。
2. Window > AE Fixture Export，点「刷新」，面板列出这个合成里所有图层的所有特效。
3. 选一个特效，填输出目录、取样帧（0 或 0,12,30）。
4. 点「导出元数据 + 帧」。
5. 跑完看 <OUT>/export.log。**面板停靠时 UI 在长循环里不会刷新**，这是 ScriptUI 的
   已知行为，不是卡死；日志文件是准的。

「仅导出元数据」只写 effect.json，不渲染，几秒钟。

## 输出结构

    <OUT>/
      effect.json            元数据 + 用例清单（完整）
      export.log             运行日志
      case00/
        params.json          这一组的参数值 + 实际渲出的帧号
        in_0000.png          特效【关闭】时的画面 = 特效真正的输入
        out_0000.png         特效【打开】时的画面 = 期望输出
        in_0000.raw          紧凑 RGBA8，engine.render() 可直接吃
        out_0000.raw
      case01/ ...

取样策略（写死在 buildCases() 里）：

- case00 全部默认值
- 每个**可扫描参数**各一组 min、一组 max
- 勾了「含全 min / 全 max」再加两组
- 上限 40 组（MAX_CASES）

只有同时满足这些的参数才进网格：**一维（OneD）+ 值可读 + min/max 有限 + 无关键帧 + 无表达式**。
其余参数照常记进 effect.json，但被跳过并在日志里列出原因——因为它们 setValue 会被 AE 忽略
（有关键帧时）或直接覆盖（有表达式时），静默扫出一堆一模一样的图比不扫更糟。

## 数据从哪来（关键实现细节）

- **输入帧 = 把特效 enabled 设为 false 再渲一遍**，不是拿素材原图凑。
  多特效串联时，禁用它得到的正是它的输入。
- **单帧渲染**靠 RenderQueueItem.timeSpanStart / timeSpanDuration，不是改 comp.time。
- **输出模块**先用 om.templates 里的精确名字匹配，匹配不上就挑第一个名字含 png 的
  （AE 是本地化的，中文版里模板叫「PNG 序列」），都失败才用面板里手填的字符串。
  如果一组 PNG 都没生成，日志会明确告诉你模板不对。
- **不碰你已有的渲染队列**：导出前把你已排队的条目全部置为未排队，结束后按原样恢复。
  但我们自己加的那些条目**删不掉**——AE 脚本 API 里 RQItemCollection 只有 add()。
  它们在渲染时被置为未排队，不影响你后续渲染；介意的话在渲染队列面板手动删。
- **失败会还原**：整个过程包在 app.beginUndoGroup() 里，参数值和 fx.enabled 结束时还原。

## 它做不到什么

- **读不了像素**。ExtendScript 拿不到渲出来的图像数据，所以 PNG 转 raw 是调 ffmpeg 外部进程做的。
- **不扫描二维/三维/颜色参数**。Point / Color 要逐分量扫，v1 只记录当前值。
- **时域特效导不出**。目标管线只有一张 texture_2d、一帧，没有帧历史。
  如果你的效果依赖上一帧，这工具帮不了你，应该让它出现在「跳过」列表里然后放弃移植。
- **不判断好不好看**。那三个数值指标只能证明「像 AE」。

## 可能踩到的坑（未经真机验证）

**这个脚本没在真机上跑过**——写它的机器上没装 After Effects。首次运行风险为零
（全程在 undo group 内，参数会还原），但请按顺序确认：

1. 面板没出现在 Window 菜单？目录放错了，或者 AE 没重启。
2. 点导出后日志一片空白？十有八九是没勾「允许脚本写入文件和访问网络」。
3. case00 目录里没有 PNG？输出模块模板名不对，日志里会列出可选模板。
4. ffmpeg 报错？面板里的路径必须是绝对路径。
5. in_*.png 和 out_*.png 一模一样？检查特效是不是在效果链最末端、参数是不是其实没扫到
   （看日志里的「跳过」列表）。
6. 参数名是中文？params.json 里的 key 用的是 matchName（稳定、不随语言变），
   name 只是给人看的。

## 下一步（还没写）

scripts/check-ae-parity.mjs：读这批 fixture，用 engine.render() 跑新写的 WGSL，
打印 mean / max / pct>2 三个数，超预算就退出非零。有了它，agent 的内循环才闭合。
