import { notFound, redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export default async function SuperAdminPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: me } = await supabase.from("profiles").select("is_super_admin").eq("id", user.id).single();
  if (!me?.is_super_admin) notFound();

  // Super admin RLS policies allow reading all rows.
  const { data: stores } = await supabase.from("stores").select("id,name,slug,plan_id,status,created_at").order("created_at", { ascending: false });
  const { count: users } = await supabase.from("profiles").select("*", { count: "exact", head: true });

  return (
    <main className="mx-auto max-w-4xl p-6">
      <h1 className="mb-1 text-2xl font-bold">Super Admin</h1>
      <p className="mb-6 text-sm text-neutral-500">{users ?? 0} users · {stores?.length ?? 0} stores</p>
      <table className="w-full rounded border bg-white text-sm">
        <thead className="bg-neutral-100 text-left"><tr><th className="p-2">Store</th><th>Slug</th><th>Plan</th><th>Status</th></tr></thead>
        <tbody>
          {(stores ?? []).map((s) => (
            <tr key={s.id} className="border-t"><td className="p-2">{s.name}</td><td>{s.slug}</td><td>{s.plan_id}</td><td>{s.status}</td></tr>
          ))}
        </tbody>
      </table>
    </main>
  );
}
