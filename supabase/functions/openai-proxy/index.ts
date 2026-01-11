import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type ChatMessage = { role: string; content: string };

type ProxyRequest = {
  model?: string;
  messages?: ChatMessage[];
  temperature?: number;
  response_format?: unknown;
};

const FUNCTION_NAME = "openai-proxy";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const jsonResponse = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders,
    },
  });

const jsonError = (message: string, status = 400, details?: unknown) =>
  jsonResponse(
    details ? { error: message, details } : { error: message },
    status,
  );

const normalizeRoute = (pathname: string) => {
  const cleaned = pathname.replace(/\/+/g, "/");
  const prefix = `/${FUNCTION_NAME}`;
  if (cleaned.startsWith(prefix)) {
    const remainder = cleaned.slice(prefix.length);
    return remainder === "" ? "/" : remainder;
  }
  return cleaned === "" ? "/" : cleaned;
};

serve(async (req) => {
  const url = new URL(req.url);
  const route = normalizeRoute(url.pathname);

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method === "GET") {
    const isHealth =
      route === "/" ||
      route === "/health" ||
      url.searchParams.get("health") === "1";
    if (isHealth) {
      return jsonResponse({
        ok: true,
        function: FUNCTION_NAME,
        ts: new Date().toISOString(),
        version: 1,
      });
    }
  }

  if (route !== "/chat") {
    return jsonError("Not found", 404);
  }

  const openaiKey = Deno.env.get("OPENAI_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

  if (!openaiKey || !supabaseUrl || !supabaseAnonKey) {
    return jsonError(
      "Server misconfigured: missing OPENAI_API_KEY or Supabase env.",
      500,
    );
  }

  const supabaseClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: {
      headers: { Authorization: req.headers.get("Authorization") ?? "" },
    },
  });
  const {
    data: { user },
    error: userError,
  } = await supabaseClient.auth.getUser();

  if (userError || !user) {
    return jsonError("Unauthorized", 401);
  }

  let payload: ProxyRequest;
  try {
    payload = await req.json();
  } catch {
    return jsonError("Invalid JSON payload.", 400);
  }

  if (!Array.isArray(payload.messages) || payload.messages.length === 0) {
    return jsonError("Bad Request", 400, "messages array required");
  }

  const serializedLength = JSON.stringify(payload.messages).length;
  if (serializedLength > 12000) {
    return jsonError("Request too large.", 413);
  }

  try {
    const completionResp = await fetch(
      "https://api.openai.com/v1/chat/completions",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${openaiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: payload.model ?? "gpt-4o-mini",
          messages: payload.messages,
          temperature:
            typeof payload.temperature === "number"
              ? payload.temperature
              : 0.2,
          response_format: payload.response_format as { type: string } | undefined,
        }),
      },
    );

    const data = await completionResp.json().catch(() => null);
    if (!completionResp.ok) {
      const details =
        data ??
        (await completionResp.text().catch(() => "OpenAI error with no body"));
      return jsonResponse(
        { error: "OpenAI request failed", details },
        completionResp.status,
      );
    }

    return jsonResponse(data ?? { ok: true });
  } catch (error) {
    const message =
      (error as { message?: string }).message ??
      "OpenAI request failed (unexpected).";
    console.error("openai proxy error", message);
    return jsonError(message, 500);
  }
});
