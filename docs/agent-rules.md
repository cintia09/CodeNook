## Multi-Agent 协作规则

### ⚡ 强制角色切换 (MANDATORY — 最高优先级)

当用户的消息包含以下任何模式时，**必须**立即调用 `agent-switch` skill 执行角色切换：

- `/agent <name>` — 斜杠命令
- `切换到<角色>` / `switch to <role>` — 切换指令
- `当<角色>` / `做<角色>` / `我是<角色>` — 身份声明
- `act as <role>` / `以<角色>身份` — 英文/中文身份

**这是非协商的操作**——检测到触发词后不询问确认，直接执行切换流程（读取 agent profile → 写入 active-agent → 加载 inbox → 显示任务）。

角色名支持中英文: 验收者=acceptor, 设计者=designer, 实现者=implementer, 审查者=reviewer, 测试者=tester

### Agent 角色系统
本环境支持 5 个 Agent 角色, 通过 skill 切换:
- `agent-acceptor` — 🎯 验收者 (需求方/甲方)
- `agent-designer` — 🏗️ 设计者 (架构师)
- `agent-implementer` — 💻 实现者 (程序员)
- `agent-reviewer` — 🔍 代码审查者
- `agent-tester` — 🧪 测试者 (QA)

### 角色切换
当用户调用某个 agent-* skill、说 "/agent <name>"、或使用自然语言触发（如"切换到验收者"、"switch to tester"）时:
1. 读取对应的 agent profile (agents/<name>.agent.md)
2. 写入 active-agent 文件
3. 按照该 profile 定义的启动流程执行
4. 在该角色范围内行动, 不越权

### 状态管理
- 所有状态变更必须通过 `agent-task-board` 和 `agent-fsm` skill
- 不允许直接编辑 task-board.json (必须通过 skill 操作)
- 每次状态变更必须记录 history

### 项目初始化
- 使用 `agent-init` skill 在项目中初始化 Agent 系统
- 初始化后生成 `<project>/.agents/` 目录结构

### 任务流转规则

#### Simple 模式（默认）
任务必须按照状态机定义的路径流转:
```
created → designing → implementing → reviewing → testing → accepting → accepted
```
不允许跳跃 (如 created 直接到 testing)。
回路: reviewing → implementing (审查退回), testing → fixing → testing (修复循环), accepting → accept_fail → designing (验收失败)。

#### 3-Phase 模式（复杂功能）
三阶段工程闭环，18 个状态:
- **Phase 1 设计**: requirements → architecture → tdd_design → dfmea → design_review
- **Phase 2 实现**: implementing + test_scripting + code_reviewing (并行) → ci_monitoring → ci_fixing → device_baseline
- **Phase 3 测试**: deploying → regression_testing → feature_testing → log_analysis → documentation → accepted

规则:
- 并行轨道 (Phase 2) 必须全部完成才能进入 device_baseline（汇聚门）
- 反馈环: Phase 3 → Phase 2 (测试失败), Phase 2 → Phase 1 (设计缺陷)
- 每个任务最多 10 次反馈环，超限自动阻塞
- 由 `agent-orchestrator` 编排器自动驱动

### 关键约束
1. **角色隔离**: 每个 Agent 只做自己职责范围内的事; `.agent.md` 中的 `skills:` 清单定义允许调用的 skills
2. **状态强制**: 不合法的状态转移必须被拒绝
3. **完整记录**: 每次操作都要更新 task-board.json、inbox.json
4. **人工介入**: 需求确认、设计审批、验收决定、安全敏感操作需要人确认
5. **🔒 提交前安全检查**: 在 `git add` / `git commit` 之前, 必须扫描待提交文件中是否包含敏感信息:
   - API Key (如 `AIza...`, `sk-...`, `ghp_...`, `AKIA...`)
   - 密码、密钥、token 的明文值
   - 内网 IP 地址 (192.168.x.x, 10.x.x.x)
   - 数据库连接串 (含用户名密码)
   - `.env` 文件或其内容
   - SSH 私钥
   
   如果发现敏感内容, **必须先移除或替换为占位符**, 再提交。绝不将秘密值推送到 GitHub。
