# MyTerm 3.4

## 简体中文

- 诊断 ZIP 新增中文与英文摘要，说明故障阶段、影响、下一步与仍不确定的根因；原始元数据保留在 diagnostic.json。
- 接口检查页面显示可读解释，数字错误码放入默认收起的技术详情。
- 主动检查与运行时事件分开解释，避免一次成功掩盖另一次失败；正常 EOF、缺失记录及 Gatekeeper 评估不会被误当作确定的故障根因。
- 摘要由本地固定规则生成，不读取终端正文、不调用 AI 模型；中英文文档与回归检查同步更新。

## English

- Diagnostic ZIPs include Chinese and English summaries of the observed stage, impact, next steps and remaining uncertainty; diagnostic.json retains raw metadata.
- Interface checks show readable explanations with numeric details collapsed by default.
- Explicit checks and runtime events are described separately, so a successful probe does not hide another failure. Normal EOF, missing events and Gatekeeper assessments are not treated as definitive root causes.
- Summaries use local deterministic rules, do not read terminal contents or call AI models, and ship with matching bilingual documentation and regression checks.
