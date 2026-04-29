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

  function resetState() {
    lastUserMessageTime = null
    usedSubagent = false
    usedTodowrite = false
  }

  function resetAndSetTime() {
    usedSubagent = false
    usedTodowrite = false
    lastUserMessageTime = Date.now()
  }

  function checkConditions(): boolean {
    const timedOut =
      lastUserMessageTime != null &&
      Date.now() - lastUserMessageTime > THRESHOLD
    return timedOut || usedSubagent || usedTodowrite
  }

  async function getTmuxInfo(): Promise<string> {
    try {
      const envText = await $`echo $TMUX`.env({ ...process.env }).quiet().text()
      await client.app.log({
        body: {
          service: "herald-notifications",
          level: "info",
          message: `TMUX env: ${envText.trim() || "(empty)"}`,
        },
      })
      const tmuxOut = await $`tmux display-message -p '#S'`.env({ ...process.env }).quiet().text()
      await client.app.log({
        body: {
          service: "herald-notifications",
          level: "info",
          message: `tmux output: ${tmuxOut.trim()}`,
        },
      })
      if (tmuxOut.trim()) {
        return ` in tmux session \`${tmuxOut.trim()}\``
      }
    } catch (e: any) {
      await client.app.log({
        body: {
          service: "herald-notifications",
          level: "info",
          message: `tmux catch: ${e?.message ?? e}`,
        },
      })
    }
    return ", opencode"
  }

  async function notifyAndReset(title: string) {
    const duration = lastUserMessageTime
      ? formatDuration(Date.now() - lastUserMessageTime)
      : ""
    const tmuxInfo = await getTmuxInfo()
    const body = `Done${tmuxInfo} (${duration})`
    try {
      await $`herald message --title ${title} --sound --no-store ${body}`
    } catch (e: any) {
      await client.app.log({
        body: {
          service: "herald-notifications",
          level: "error",
          message: `herald failed: ${e?.message ?? e}`,
        },
      })
    }
    resetState()
  }

  return {
    event: async ({ event }) => {
      if (event.type === "session.status") {
        const status = (event as any).properties?.status
        await client.app.log({
          body: {
            service: "herald-notifications",
            level: "info",
            message: `session.status: ${JSON.stringify(status)}`,
          },
        })
        if (status?.type === "busy") {
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
          await client.app.log({
            body: {
              service: "herald-notifications",
              level: "info",
              message: "session aborted by user, resetting state",
            },
          })
          resetState()
        }
      }

      if (event.type === "question.asked" || event.type === "permission.asked") {
        if (checkConditions()) {
          await notifyAndReset("Human, I am done 🥹")
        }
      }

      if (event.type === "question.replied" || event.type === "question.rejected" || event.type === "permission.replied") {
        resetAndSetTime()
      }

      if (event.type === "session.idle") {
        const sessionID = (event as any).properties?.sessionID as string | undefined
        let isSubagent = false
        if (sessionID) {
          try {
            const res = await client.session.get({ path: { id: sessionID } })
            if ((res as any)?.data?.parentID) {
              isSubagent = true
            }
          } catch {
            // if lookup fails, proceed — worst case is an extra notification
          }
        }
        await client.app.log({
          body: {
            service: "herald-notifications",
            level: "info",
            message: `session.idle fired (isSubagent=${isSubagent})`,
            extra: { sessionID, timedOut: lastUserMessageTime != null && Date.now() - lastUserMessageTime > THRESHOLD, usedSubagent, usedTodowrite, lastUserMessageTime },
          },
        })
        if (isSubagent) {
          return
        }
        if (checkConditions()) {
          await notifyAndReset("Human, I am done 🥹")
        }
      }
    },
  }
}
