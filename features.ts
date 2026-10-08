import { createClient } from "@/lib/supabase/server";

// Resolution order (in SQL): store override -> plan entitlement -> flag default.
export async function isFeatureEnabled(storeId: string, flagKey: string): Promise<boolean> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("store_feature_enabled", { p_store: storeId, p_flag: flagKey });
  if (error) return false;
  return data === true;
}
