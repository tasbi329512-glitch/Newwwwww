import { NextResponse } from "next/server";
import { resolveVersion } from "@/lib/api-version";
import { createClient } from "@/lib/supabase/server";

export async function GET(_req: Request, { params }: { params: Promise<{ version: string }> }) {
  const { version } = await params;
  const v = resolveVersion(version);
  if (!v) return NextResponse.json({ error: "unsupported_api_version" }, { status: 404 });

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "unauthorized" }, { status: 401, headers: v.headers });

  const { data, error } = await supabase.from("stores").select("id,name,slug,plan_id,status,currency,locale");
  if (error) return NextResponse.json({ error: error.message }, { status: 500, headers: v.headers });
  return NextResponse.json({ stores: data }, { headers: v.headers });
}
