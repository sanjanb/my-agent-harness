import type { Plugin } from "@opencode-ai/plugin";

const API = process.env.AGENTMEMORY_URL || "http://localhost:3111";
const FILE_TOOLS = new Set(["Read", "Write", "Edit", "Glob", "Grep"]);
const FILE_KEYS = ["filePath", "file_path", "path", "file", "pattern"];
const MAX_STASHED_FILES = 20;

const DEBUG = process.env.OPENCODE_AGENTMEMORY_DEBUG === "1";
const SECRET = ("[REDACTED]" as unknown as string) || "";

function authHeaders(): Record<string, string> {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (SECRET) headers["Authorization"] = `Bearer ${SECRET}`;
  return headers;
}

async function post(path: string, body: Record<string, unknown>, timeoutMs = 5000): Promise<void> {
  try {
    await fetch(`${API}/agentmemory${path}`, {
      method: "POST",
      headers: authHeaders(),
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (e) {
    if (DEBUG) console.error(`[agentmemory] POST ${path} failed:`, (e as Error).message);
  }
}

async function postJson(path: string, body: Record<string, unknown>): Promise<unknown | null> {
  try {
    const res = await fetch(`${API}/agentmemory${path}`, {
      method: "POST",
      headers: authHeaders(),
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(5000),
    });
    return res.ok ? await res.json() : null;
  } catch (e) {
    if (DEBUG) console.error(`[agentmemory] POST ${path} failed:`, (e as Error).message);
    return null;
  }
}

async function observe(
  sessionId: string,
  hookType: string,
  data: Record<string, unknown>,
): Promise<void> {
  await post("/observe", {
    hookType,
    sessionId,
    project: projectPath,
    cwd: projectPath,
    timestamp: new Date().toISOString(),
    data,
  });
}

const activeSessions = new Map<string, null>();
function getActiveSessionId(): string | null {
  return Array.from(activeSessions.keys()).pop() || null;
}
let pendingConfig: Record<string, unknown> | null = null;
let projectPath: string | null = null;
const stashedFiles = new Map<string, Set<string>>();
const seenSubtaskIds = new Map<string, Set<string>>();
const seenToolCallIds = new Map<string, Set<string>>();
const contextInjectedSessions = new Set<string>();
// cache the context returned by POST /session/start so the chat
// system-transform hook can inject it without a second /context fetch.
// Auto-injection now happens at session.created (immediately) AND at
// the first prompt_submit (fallback for older OpenCode builds that
// don't implement experimental.chat.system.transform).
const startContextCache = new Map<string, string>();

function stashFor(sid: string): Set<string> {
  let s = stashedFiles.get(sid);
  if (!s) { s = new Set<string>(); stashedFiles.set(sid, s); }
  return s;
}

function subtaskSetFor(sid: string): Set<string> {
  let s = seenSubtaskIds.get(sid);
  if (!s) { s = new Set<string>(); seenSubtaskIds.set(sid, s); }
  return s;
}

function toolCallSetFor(sid: string): Set<string> {
  let s = seenToolCallIds.get(sid);
  if (!s) { s = new Set<string>(); seenToolCallIds.set(sid, s); }
  return s;
}

function pruneSessionMaps(sid: string): void {
  stashedFiles.delete(sid);
  seenSubtaskIds.delete(sid);
  seenToolCallIds.delete(sid);
  contextInjectedSessions.delete(sid);
  startContextCache.delete(sid);
}

function stashFile(sid: string, file: string): void {
  const stash = stashFor(sid);
  stash.add(file);
  if (stash.size > MAX_STASHED_FILES) {
    const keep = Array.from(stash).slice(-MAX_STASHED_FILES);
    stash.clear();
    for (const f of keep) stash.add(f);
  }
}

async function handleToolResult(
  sid: string,
  state: Record<string, unknown>,
  toolName: string,
  callId: string,
  hookType: string,
  outputField: string,
  extra?: Record<string, unknown>,
): Promise<void> {
  const callSet = toolCallSetFor(sid);
  if (callSet.has(callId)) return;
  callSet.add(callId);
  const rawTime = (state.time as Record<string, unknown>) || {};
  const startTime = typeof rawTime.start === "number" ? rawTime.start : null;
  const endTime = typeof rawTime.end === "number" ? rawTime.end : null;
  await observe(sid, hookType, {
    tool_name: toolName,
    call_id: callId,
    tool_input: safeSlice(state.input, 4000),
    tool_output: safeSlice(state[outputField], 8000),
    duration_ms: (startTime != null && endTime != null) ? endTime - startTime : null,
    ...(extra || {}),
  });
}

function safeSlice(v: unknown, max: number): string {
  if (typeof v === "string") return v.slice(0, max);
  if (v == null) return "";
  try { return JSON.stringify(v).slice(0, max); } catch { return ""; }
}

function extractFilePaths(args: Record<string, unknown>): string[] {
  const files: string[] = [];
  for (const key of FILE_KEYS) {
    const val = args[key];
    if (typeof val === "string" && val.length > 0) {
      files.push(val);
    }
  }
  return files;
}

function extractErrorMessage(err: unknown): string {
  if (typeof err === "string") return err;
  if (err && typeof err === "object") {
    const e = err as Record<string, unknown>;
    if (typeof e.message === "string") return e.message;
    if (e.data && typeof e.data === "object") {
      const d = e.data as Record<string, unknown>;
      if (typeof d.message === "string") return d.message;
    }
    if (typeof e.name === "string") return e.name;
    try { return JSON.stringify(err); } catch { return ""; }
  }
  return String(err ?? "");
}

function normalizeConfigKeys(
  value: unknown,
): string[] {
  if (typeof value === "object" && value !== null && !Array.isArray(value)) {
    return Object.keys(value as Record<string, unknown>);
  }
  if (Array.isArray(value)) return value;
  return [];
}

const AGENTMEMORY_INSTRUCTIONS = `<agentmemory-instructions>
You have access to agentmemory for persistent cross-session memory. Use these tools proactively.

CORE TOOLS:

memory_save — Save an insight, decision, or fact to long-term memory.
  Required: content (text), concepts (2-5 comma-separated keywords), type (pattern/preference/architecture/bug/workflow/fact)
  Optional: files (comma-separated paths)
  Use when: user says "remember this", after discovering a bug, after making an architectural decision, after learning a project convention.

memory_recall — Search past observations by keywords.
  Use when: user says "recall", "what did we do", "do you remember", or needs context from past sessions.

memory_smart_search — Hybrid semantic+keyword search with progressive disclosure.
  Use when: you need the most relevant past context, fuzzy/conceptual searches, or recall doesn't find what you need.

memory_sessions — List recent sessions with status and observation counts.
  Use when: user asks about session/past history, "what did we work on".

memory_file_history — Get past observations about specific files (across all sessions).
  Use when: you're about to edit a file and want to know its history, common pitfalls, or past edits.

memory_lesson_save — Save a lesson learned (what worked, what to avoid).
  Use when: you discover a pattern that could help future sessions avoid mistakes.

memory_lesson_recall — Search lessons by query. Returns lessons sorted by confidence.
  Use when: before making a decision, check if past lessons apply.

memory_governance_delete — Delete specific memories. Requires explicit user confirmation.
  Use when: user says "forget this", "delete that memory".

memory_patterns — Detect recurring patterns across sessions.
  Use when: you want to understand project-level trends over time.

memory_consolidate — Run the 4-tier memory consolidation pipeline.
  Use when: you want to compress and organize accumulated session observations.

All memory tools start with \`agentmemory_memory_\`. Use the exact names as they appear in your tool list. Tool results are JSON. Always check what was returned before presenting to the user.
</agentmemory-instructions>`;

export const AgentmemoryCapturePlugin: Plugin = async (ctx) => {
  projectPath = ctx.worktree || ctx.project?.id || process.cwd();

  return {
    event: async ({ event }) => {
      const type = event.type;
      const props = (event as { properties?: Record<string, unknown> }).properties || {};

      // ── session.created ──
      if (type === "session.created") {
        const info = props.info as Record<string, unknown> | undefined;
        const sid = (info?.id as string) || (props.sessionID as string) || null;
        if (!sid) return;
        activeSessions.set(sid, null);
        stashedFiles.set(sid, new Set());
        seenSubtaskIds.delete(sid);
        seenToolCallIds.delete(sid);
        contextInjectedSessions.delete(sid);
        // Snapshot the session id locally — `activeSessionId` is mutable
        // and another `session.created` event during the await could
        // rebind it, causing context to be cached against the wrong key.
        const sessionId = sid;
        const startResult = await postJson("/session/start", {
          sessionId,
          title: info?.title ?? null,
          parentID: info?.parentID ?? null,
          version: info?.version ?? null,
          project: projectPath,
          cwd: projectPath,
        });
        // cache the context returned at session/start so the
        // chat.system.transform hook injects it without a second fetch.
        const startCtx = (startResult as Record<string, unknown>)?.context;
        if (typeof startCtx === "string" && startCtx.length > 0) {
          startContextCache.set(sessionId, startCtx);
        }
        if (pendingConfig) {
          await observe(sessionId, "config_loaded", pendingConfig);
          pendingConfig = null;
        }
      }

      // ── session.idle ── (summarize handled in session.status idle branch)

      // ── session.status ──
      if (type === "session.status") {
        const status = props.status as Record<string, unknown> | undefined;
        const sid = (props.sessionID as string) || getActiveSessionId();
        if (!sid || !status) return;
        if (status.type === "idle") {
          await post("/summarize", { sessionId: sid });
        }
        await observe(sid, "session_status", {
          status_type: status.type,
          attempt: status.attempt ?? null,
          message: safeSlice(status.message, 2000),
        });
      }

      // ── session.compacted ──
      if (type === "session.compacted") {
        const sid = (props.sessionID as string) || getActiveSessionId();
        if (sid) {
          await post("/summarize", { sessionId: sid });
          await observe(sid, "session_compacted", {});
        }
      }

      // ── session.updated ──
      if (type === "session.updated") {
        const info = props.info as Record<string, unknown> | undefined;
        const sid = (info?.id as string) || (props.sessionID as string) || getActiveSessionId();
        if (!sid) return;
        const summary = info?.summary as Record<string, unknown> | undefined;
        await observe(sid, "session_updated", {
          title: info?.title ?? null,
          parentID: info?.parentID ?? null,
          additions: summary?.additions ?? null,
          deletions: summary?.deletions ?? null,
          files: summary?.files ?? null,
        });
      }

      // ── session.diff ──
      if (type === "session.diff") {
        const sid = (props.sessionID as string) || getActiveSessionId();
        if (!sid || !Array.isArray(props.diff)) return;
        const diffs = props.diff as Array<Record<string, unknown>>;
        await observe(sid, "session_diff", {
          files: diffs.map(d => d.file as string),
          additions: diffs.reduce((s, d) => s + ((d.additions as number) || 0), 0),
          deletions: diffs.reduce((s, d) => s + ((d.deletions as number) || 0), 0),
          diffs: diffs.slice(0, 50),
        });
      }

      // ── session.deleted ──
      if (type === "session.deleted") {
        const sid = (props.info as Record<string, unknown>)?.id as string || (props.sessionID as string) || getActiveSessionId();
        if (!sid) {
          if (DEBUG) console.error("[agentmemory] session.deleted with no session ID");
          return;
        }
        await post("/session/end", { sessionId: sid });
        post("/crystals/auto", { olderThanDays: 7 }, 30000);
        post("/consolidate-pipeline", { tier: "all", force: true }, 30000);
        activeSessions.delete(sid);
        pruneSessionMaps(sid);
      }

      // ── session.error ──
      if (type === "session.error") {
        const sid = (props.sessionID as string) || getActiveSessionId();
        if (sid) {
          await observe(sid, "post_tool_failure", {
            tool_name: "session.error",
            tool_input: "",
            tool_output: safeSlice((props as Record<string, unknown>).error, 8000),
          });
        }
      }

      // ── message.updated ──
      if (type === "message.updated") {
        const info = props.info as Record<string, unknown> | undefined;
        if (!info) return;

        if (info.role === "assistant") {
          const sid = (props.sessionID as string) || (info.sessionID as string) || getActiveSessionId();
          if (!sid) return;
          const tokens = info.tokens as Record<string, unknown> | undefined;
          const cache = tokens?.cache as Record<string, unknown> | undefined;
          const error = info.error ? extractErrorMessage(info.error) : null;
          const time = info.time as Record<string, unknown> | undefined;
          await observe(sid, "assistant_message", {
            messageID: info.id,
            parentID: info.parentID,
            modelID: info.modelID,
            providerID: info.providerID,
            mode: info.mode,
            cost: info.cost ?? 0,
            tokens: {
              input: tokens?.input ?? 0,
              output: tokens?.output ?? 0,
              reasoning: tokens?.reasoning ?? 0,
              cache_read: cache?.read ?? 0,
              cache_write: cache?.write ?? 0,
            },
            finish: info.finish ?? null,
            error,
            duration_ms: (time && typeof time.completed === "number")
              ? time.completed - (typeof time.created === "number" ? time.created : 0)
              : null,
          });
        }
      }

      // ── message.removed ──
      if (type === "message.removed") {
        const sid = (props.sessionID as string) || getActiveSessionId();
        if (sid) {
          await observe(sid, "message_removed", {
            messageID: (props as Record<string, unknown>).messageID as string,
          });
        }
      }

      // ── message.part.updated ──
      if (type === "message.part.updated") {
        const part = props.part as Record<string, unknown> | undefined;
        if (!part) return;
        const sid = (part.sessionID as string) || (props.sessionID as string) || getActiveSessionId();
        if (!sid) return;

        if (part.type === "subtask") {
          const subtaskId = (part as Record<string, unknown>).id as string;
          if (!subtaskId) return;
          const subtaskSet = subtaskSetFor(sid);
          if (subtaskSet.has(subtaskId)) return;
          subtaskSet.add(subtaskId);
          await observe(sid, "subagent_start", {
            subtask_id: (part as Record<string, unknown>).id as string,
            agent: (part as Record<string, unknown>).agent as string,
            prompt: safeSlice((part as Record<string, unknown>).prompt, 4000),
            description: safeSlice((part as Record<string, unknown>).description, 2000),
          });
          return;
        }

        if (part.type === "tool") {
          const state = part.state as Record<string, unknown> | undefined;
          if (!state) return;
          const callId = part.callID as string;
          if (!callId) return;
          const toolName = part.tool as string;

          if (state.status === "completed") {
            const st = state as Record<string, unknown>;
            await handleToolResult(sid, st, toolName, callId, "post_tool_use", "output", {
              title: st.title ?? null,
              metadata: st.metadata || {},
              attachments: Array.isArray(st.attachments)
                ? (st.attachments as Array<Record<string, unknown>>).map(a => (a.filename as string) || (a.url as string))
                : [],
            });
          } else if (state.status === "error") {
            await handleToolResult(sid, state as Record<string, unknown>, toolName, callId, "post_tool_failure", "error");
          }
          return;
        }

        if (part.type === "step-finish") {
          const partRecord = part as Record<string, unknown>;
          const tokens = partRecord.tokens as Record<string, unknown> | undefined;
          await observe(sid, "step_finish", {
            messageID: partRecord.messageID as string,
            reason: partRecord.reason ?? null,
            cost: partRecord.cost ?? 0,
            input_tokens: tokens?.input ?? 0,
            output_tokens: tokens?.output ?? 0,
            reasoning_tokens: tokens?.reasoning ?? 0,
          });
          return;
        }

        if (part.type === "reasoning") {
          const partRecord = part as Record<string, unknown>;
          await observe(sid, "reasoning", {
            messageID: partRecord.messageID as string,
            text: safeSlice(partRecord.text, 4000),
          });
          return;
        }

        if (part.type === "file") {
          const partRecord = part as Record<string, unknown>;
          const filename = partRecord.filename as string || partRecord.url as string || null;
          if (filename) stashFor(sid).add(filename);
          return;
        }

        if (part.type === "patch") {
          const partRecord = part as Record<string, unknown>;
          await observe(sid, "patch_applied", {
            messageID: partRecord.messageID as string,
            hash: partRecord.hash as string,
            files: partRecord.files as string[] || [],
          });
          return;
        }

        if (part.type === "compaction") {
          const partRecord = part as Record<string, unknown>;
          await observe(sid, "compaction_event", {
            messageID: partRecord.messageID as string,
            auto: partRecord.auto ?? false,
          });
          return;
        }

        if (part.type === "agent") {
          const partRecord = part as Record<string, unknown>;
          await observe(sid, "agent_selected", {
            messageID: partRecord.messageID as string,
            name: partRecord.name as string,
          });
          return;
        }

        if (part.type === "retry") {
          const partRecord = part as Record<string, unknown>;
          await observe(sid, "retry_attempt", {
            messageID: partRecord.messageID as string,
            attempt: partRecord.attempt as number,
            error: safeSlice(partRecord.error, 2000),
          });
          return;
        }
      }

      // ── file.edited ──
      if (type === "file.edited") {
        const sid = (props.sessionID as string) || getActiveSessionId();
        const file = (props as Record<string, unknown>).file as string;
        if (sid && typeof file === "string" && file.length > 0) {
          stashFile(sid, file);
        }
      }

      // ── permission.updated ──
      if (type === "permission.updated") {
        const sid = (props.sessionID as string) || getActiveSessionId();
        if (!sid) return;
        const p = props as Record<string, unknown>;
        await observe(sid, "notification", {
          notification_type: "permission_prompt",
          permission: p.type as string || "unknown",
          pattern: Array.isArray(p.pattern)
            ? (p.pattern as string[]).join(", ")
            : (p.pattern as string || ""),
          tool_call_id: p.callID as string || null,
          title: (p.title as string) || (p.type as string) || "",
          metadata: p.metadata as Record<string, unknown> || {},
        });
      }

      // ── permission.replied ──
      if (type === "permission.replied") {
        const sid = (props.sessionID as string) || getActiveSessionId();
        if (!sid) return;
        const p = props as Record<string, unknown>;
        await observe(sid, "permission_replied", {
          permission_id: (p.permissionID as string) || (p.requestID as string) || "",
          response: (p.response as string) || (p.reply as string) || "",
        });
      }

      // ── todo.updated ──
      if (type === "todo.updated") {
        const sid = (props.sessionID as string) || getActiveSessionId();
        const p = props as Record<string, unknown>;
        const todos = Array.isArray(p.todos) ? (p.todos as Array<Record<string, unknown>>).slice(0, 100) : [];
        if (!sid || todos.length === 0) return;
        const completed = todos.filter(t => t.status === "completed");
        const active = todos.filter(t => t.status !== "completed");
        await observe(sid, "task_completed", {
          completed: completed.map(t => ({ content: t.content as string, priority: t.priority as string })),
          in_progress: active.map(t => ({ content: t.content as string, priority: t.priority as string })),
          total: todos.length,
        });
      }

      // ── command.executed ──
      if (type === "command.executed") {
        const sid = (props.sessionID as string) || getActiveSessionId();
        if (sid) {
          const p = props as Record<string, unknown>;
          await observe(sid, "command_executed", {
            name: p.name as string,
            arguments: p.arguments as string || "",
          });
        }
      }
    },

    // ── chat.message ──
    "chat.message": async (input, output) => {
      const sid = (input.sessionID as string) || getActiveSessionId();
      if (!sid) return;
      const parts = (output.parts || []) as Array<Record<string, unknown>>;
      const files = parts
        .filter(p => p.type === "file")
        .map(p => (p.filename as string) || (p.url as string))
        .filter(Boolean);
      for (const f of files) {
        stashFile(sid, f);
      }

      const textParts = parts.filter(p => p.type === "text" && !p.synthetic && !p.ignored);
      const userText = textParts.map(p => (p.text as string) || "").join("\n");

      await observe(sid, "prompt_submit", {
        agent: input.agent ?? null,
        model: input.model ?? null,
        variant: input.variant ?? null,
        prompt: userText.slice(0, 8000),
        files: files.slice(0, 20),
        parts_summary: parts.map(p => p.type as string).filter(Boolean),
      });
    },

    // ── chat.params ──
    "chat.params": async (input, output) => {
      if (!input.model || !output) return;
      const sid = (input.sessionID as string) || getActiveSessionId();
      if (!sid) return;
      await observe(sid, "llm_params", {
        agent: input.agent,
        model: `${input.model.providerID}/${input.model.id}`,
        provider_url: input.model.api?.url ?? null,
        temperature: output.temperature,
        topP: output.topP,
        max_output_tokens: input.model.limit?.output ?? null,
        context_limit: input.model.limit?.context ?? null,
        cost_1k_input: input.model.cost?.input ?? 0,
        cost_1k_output: input.model.cost?.output ?? 0,
      });
    },

    // ── tool.execute.before ──
    "tool.execute.before": async (input, output) => {
      if (!FILE_TOOLS.has(input.tool)) return;
      const sid = (input.sessionID as string) || getActiveSessionId();
      if (!sid) return;
      const args = output.args as Record<string, unknown> | undefined;
      if (!args) return;
      for (const fp of extractFilePaths(args)) {
        stashFile(sid, fp);
      }
    },

    // ── experimental.chat.system.transform ──
    "experimental.chat.system.transform": async (input, output) => {
      const sid = (input.sessionID as string) || getActiveSessionId();
      if (!sid) return;

      if (!contextInjectedSessions.has(sid)) {
        if (!Array.isArray(output.system)) return;
        output.system.push(AGENTMEMORY_INSTRUCTIONS);
        // prefer the context already fetched at session.created;
        // fall back to a fresh /context call if the cache missed (e.g.
        // session resumed across plugin reloads).
        let ctx = startContextCache.get(sid);
        if (typeof ctx !== "string" || ctx.length === 0) {
          const result = await postJson("/context", {
            sessionId: sid,
            project: projectPath,
          });
          ctx = (result as Record<string, unknown>)?.context as string | undefined;
        } else {
          startContextCache.delete(sid);
        }
        if (typeof ctx === "string" && ctx.length > 0) {
          if (Array.isArray(output.system)) {
            output.system.push(ctx);
          }
        }
        contextInjectedSessions.add(sid);
      }

      const stash = stashFor(sid);
      if (stash.size === 0) return;
      const files = Array.from(stash).slice(0, 10);

      const enrichResult = await postJson("/enrich", {
        sessionId: sid,
        files,
        toolName: "enrich_inject",
      });

      const enrichCtx = (enrichResult as Record<string, unknown>)?.context;
      if (typeof enrichCtx === "string" && enrichCtx.length > 0) {
        if (Array.isArray(output.system)) {
          output.system.push(enrichCtx);
        }
        for (const f of files) stash.delete(f);
      }
    },

    // ── experimental.session.compacting (WIP) ──
    "experimental.session.compacting": async (input, output) => {
      const sid = (input.sessionID as string) || getActiveSessionId();
      if (!sid) return;

      const result = await postJson("/context", {
        sessionId: sid,
        project: projectPath,
      });
      const ctx = (result as Record<string, unknown>)?.context;
      if (typeof ctx === "string" && ctx.length > 0) {
        if (Array.isArray(output.context)) {
          output.context.push(ctx);
        }
      }
    },

    // ── config ──
    config: async (input) => {
      const payload: Record<string, unknown> = {
        theme: input.theme ?? null,
        model: input.model ?? null,
        autoupdate: input.autoupdate ?? null,
        agents: normalizeConfigKeys(input.agent),
        mcp_servers: normalizeConfigKeys(input.mcp),
        providers: normalizeConfigKeys(input.provider),
        permission: input.permission ?? null,
      };
      if (activeSessions.size > 0) {
        await observe(getActiveSessionId()!, "config_loaded", payload);
      } else {
        pendingConfig = payload;
      }
    },
  };
};