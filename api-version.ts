export type VersionStatus = "stable" | "beta" | "preview" | "deprecated" | "sunset";
export const API_VERSIONS: Record<string, { status: VersionStatus; sunset?: string }> = {
  "2026-01": { status: "stable" },
  "2026-04": { status: "stable" },
  "2026-07": { status: "beta" },
};
export const LATEST_STABLE = "2026-04";

export function resolveVersion(v: string) {
  const info = API_VERSIONS[v];
  if (!info || info.status === "sunset") return null;
  const headers: Record<string, string> = { "X-Sasha-API-Version": v, "X-Sasha-API-Status": info.status };
  if (info.status === "deprecated") {
    headers["Deprecation"] = "true";
    if (info.sunset) headers["Sunset"] = new Date(info.sunset).toUTCString();
  }
  return { info, headers };
}
