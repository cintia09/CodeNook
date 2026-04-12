## Multi-Agent 协作系统 (MANDATORY)

本环境启用了 Multi-Agent 协作框架，由 `agent-pre-tool-use` hook 强制执行。

**角色切换触发 (最高优先级)**:
检测到 `/agent <name>`、`切换到<角色>`、`switch to <role>` 等触发词时，**必须立即**调用 `agent-switch` skill。
角色: acceptor(验收者) | designer(设计者) | implementer(实现者) | reviewer(审查者) | tester(测试者)

**切换时必读**: 执行切换前，读取目标项目的 `.agents/docs/agent-guide.md`（如存在），获取项目特定的角色约束和工作流。

**硬约束 (hook 强制执行，无法绕过)**:
1. 角色权限边界 — 非实现者不能编辑源代码，非测试者不能修改测试文件
2. HITL 门禁 — FSM 状态转移需人工审批 (`.agents/config.json` 的 `hitl.enabled`)
3. 切出守卫 — 有未审批任务时不能切换角色
4. 记忆隔离 — Agent 不能写其他 Agent 的记忆文件

**任务流转**: `created → designing → implementing → reviewing → testing → accepting → accepted`

**提交前安全**: git commit 前扫描 API Key、密码、内网 IP、连接串等敏感信息，发现则先移除。
