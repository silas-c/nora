export const DEEPSEEK_MODEL = "deepseek-flash";

export interface DeepSeekOptions {
  apiKey: string;
  model?: string;
  baseURL?: string;
  timeoutMs?: number;
  /** DeepSeek's reasoning before it answers. "none" is fastest; "low" thinks briefly first. */
  reasoning?: "none" | "low" | "high";
  fetch?: typeof fetch;
}

/** One DeepSeek V4.1 Flash call that must answer in JSON. */
export async function askDeepSeek(options: DeepSeekOptions, instructions: string, input: object, maxTokens: number, signal: AbortSignal): Promise<unknown> {
  const { apiKey, model = DEEPSEEK_MODEL, baseURL = "https://api.deepseek.com", timeoutMs = 15_000, reasoning = "none" } = options;
  const thinking = reasoning === "none" ? { type: "disabled" } : { type: "enabled", reasoning_effort: reasoning };
  let response: Response;
  try {
    response = await (options.fetch ?? fetch)(`${baseURL}/chat/completions`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
      body: JSON.stringify({
        model,
        messages: [{ role: "system", content: instructions }, { role: "user", content: JSON.stringify(input) }],
        response_format: { type: "json_object" },
        thinking,
        ...(reasoning === "none" ? { temperature: 0 } : {}),
        // Reasoning tokens count toward the limit, so leave room for them before the answer.
        max_tokens: reasoning === "none" ? maxTokens : maxTokens + 4_000,
      }),
      signal: AbortSignal.any([signal, AbortSignal.timeout(timeoutMs)]),
    });
  } catch {
    throw new Error(signal.aborted ? "DeepSeek was cancelled." : "DeepSeek is temporarily unavailable.");
  }
  if (response.status === 401) throw new Error("DeepSeek authentication failed. Check DEEPSEEK_API_KEY.");
  if (response.status === 402) throw new Error("The DeepSeek account is out of credit.");
  if (response.status === 429) throw new Error("DeepSeek rate limit reached. Try again in a moment.");
  if (!response.ok) throw new Error("DeepSeek could not answer.");
  const body = await response.json() as { choices?: Array<{ message?: { content?: unknown } }> };
  const content = body.choices?.[0]?.message?.content;
  if (typeof content !== "string") throw new Error("DeepSeek returned an empty answer.");
  try { return JSON.parse(content); } catch { throw new Error("DeepSeek returned an answer Nora can’t read."); }
}
