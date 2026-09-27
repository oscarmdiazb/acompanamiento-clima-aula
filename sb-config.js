// Backend del aplicativo de acompañamiento (Supabase, proyecto «oscar-apps»).
// Este archivo es PÚBLICO. La anon key solo permite llamar a sed_get / sed_post;
// las tablas sed_* tienen RLS sin políticas, así que no se pueden leer directo.
const SUPABASE_URL = "https://sxfbzcnsbcvitaenwpct.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN4ZmJ6Y25zYmN2aXRhZW53cGN0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkxNTUzODksImV4cCI6MjEwNDczMTM4OX0.AwTQ4lNfFQXEOWUcgOcyI3QUxsYP7-GFo7zuPkHuOJM";

const SED_HEADERS = {
  "apikey": SUPABASE_ANON_KEY,
  "Authorization": "Bearer " + SUPABASE_ANON_KEY,
  "Content-Type": "application/json"
};

// Agenda de visitas: se lee del aplicativo de reservas (solo lectura, sin datos
// de estudiantes). Así la agenda nunca queda desactualizada aquí.
const VISITAS_API = SUPABASE_URL + "/rest/v1/rpc/api_get";
const SED_GET     = SUPABASE_URL + "/rest/v1/rpc/sed_get";
const SED_POST    = SUPABASE_URL + "/rest/v1/rpc/sed_post";

async function traerVisitas() {
  const r = await fetch(VISITAS_API, { headers: SED_HEADERS });
  if (!r.ok) throw new Error("HTTP " + r.status);
  return await r.json();
}
async function sedGet(token) {
  const q = token ? "?p_token=" + encodeURIComponent(token) : "";
  const r = await fetch(SED_GET + q, { headers: SED_HEADERS });
  if (!r.ok) throw new Error("HTTP " + r.status);
  return await r.json();
}
async function sedPost(body) {
  const r = await fetch(SED_POST, { method: "POST", headers: SED_HEADERS,
                                    body: JSON.stringify({ body }) });
  if (!r.ok) throw new Error("HTTP " + r.status);
  return await r.json();
}
