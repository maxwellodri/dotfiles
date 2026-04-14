import type { Plugin } from "@opencode-ai/plugin"

export const LLMTimoutPing: Plugin = async ({ $ }) => {
  let lastUserMessageTime: number | null = null
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
    "message.updated": async (input) => {
      if (input.role === "user") {
        lastUserMessageTime = Date.now()
      }
    },
    "session.idle": async () => {
      if (lastUserMessageTime && Date.now() - lastUserMessageTime > THRESHOLD) {
        const duration = formatDuration(Date.now() - lastUserMessageTime)
        const tmuxInfo = await getTmuxInfo()
        const body = `Done${tmuxInfo} (${duration})`
        try {
          await $`herald message --title ${"Human, I am done 🥹"} --sound --no-store ${body}`
        } catch {
          // herald not available
        }
      }
      lastUserMessageTime = null
    },
  }
}
