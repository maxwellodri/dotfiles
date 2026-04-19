import type { Plugin } from "@opencode-ai/plugin"

export const HeraldNotifications: Plugin = async ({ $, client }) => {
  await client.app.log({
    body: {
      service: "herald-notifications",
      level: "info",
      message: "Plugin loaded",
    },
  })

  let lastUserMessageTime: number | null = null
  let usedSubagent = false
  let usedTodowrite = false
  let userAborted = false
  const THRESHOLD = 2 * 60 * 1000

  function formatDuration(ms: number): string {
    const seconds = Math.floor(ms / 1000)
    if (seconds < 60) return `${seconds}s`
    const minutes = Math.floor(seconds / 60)
    const secs = seconds % 60
    if (minutes < 60) return `${minutes}m ${secs}s`
    const hours = Math.floor(minutes / 60)
    const mins = minutes % 60
    return `${hours}h ${mins}m`
  }

  async function getTmuxInfo(): Promise<string> {
    try {
      const result = await $`tmux display-message -p #S`.quiet()
      if (result.stdout.trim()) {
        return ` in tmux session \`${result.stdout.trim()}\``
      }
    } catch {
      // not in tmux
    }
    return ", opencode"
  }

  return {
    event: async ({ event }) => {
      if (event.type === "message.updated") {
        const props = (event as any).properties
        const info = props?.info
        const role = info?.role
        if (role === "user") {
          lastUserMessageTime = Date.now()
        }
      }

      if (event.type === "message.part.updated") {
        const props = (event as any).properties
        const part = props?.part
        if (!part) return
        await client.app.log({
          body: {
            service: "herald-notifications",
            level: "info",
            message: `message.part.updated part: ${JSON.stringify({ type: part.type, tool: part.tool })}`,
          },
        })
        if (part.type === "tool" && part.tool === "task") {
          usedSubagent = true
        }
        if (part.type === "tool" && part.tool === "todowrite") {
          usedTodowrite = true
        }
      }

      if (event.type === "session.error") {
        const error = (event as any).error ?? (event as any).properties?.error
        if (error?.name === "MessageAbortedError") {
          userAborted = true
        }
      }

      if (event.type === "session.idle") {
        await client.app.log({
          body: {
            service: "herald-notifications",
            level: "info",
            message: `session.idle fired`,
            extra: { timedOut: lastUserMessageTime != null && Date.now() - lastUserMessageTime > THRESHOLD, usedSubagent, usedTodowrite, userAborted, lastUserMessageTime },
          },
        })
        const timedOut =
          lastUserMessageTime != null &&
          Date.now() - lastUserMessageTime > THRESHOLD
        if (!userAborted && (timedOut || usedSubagent || usedTodowrite)) {
          const duration = lastUserMessageTime
            ? formatDuration(Date.now() - lastUserMessageTime)
            : ""
          const tmuxInfo = await getTmuxInfo()
          const body = `Done${tmuxInfo} (${duration})`
          try {
            await $`herald message --title ${"Human, I am done 🥹"} --sound --no-store ${body}`
          } catch (e: any) {
            await client.app.log({
              body: {
                service: "herald-notifications",
                level: "error",
                message: `herald failed: ${e?.message ?? e}`,
              },
            })
          }
        }
        lastUserMessageTime = null
        usedSubagent = false
        usedTodowrite = false
        userAborted = false
      }
    },
  }
}
