// Free Visibility Score intake for the roqbusiness.com home page CTA.
//
// The page posts here with the project's publishable key, which is enough to
// clear the gateway's JWT check but carries no table privileges of its own.
// The insert below runs through a service-role client so that
// visibility_score_requests can stay admin-only under RLS -- the browser
// never holds a key that could read the lead queue back out.
//
// Every field is re-validated here. The form validates too, but that is a
// convenience for the visitor, not a control: this endpoint is public and
// anyone can post to it directly.

import { createClient } from 'jsr:@supabase/supabase-js@2';

// Browsers get a real allowlist. This is not a security boundary -- curl
// ignores CORS entirely -- it just keeps other sites from quietly embedding
// the form against this project.
const ALLOWED_ORIGINS = new Set([
  'https://roqbusiness.com',
  'https://www.roqbusiness.com',
]);

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

function corsHeaders(origin: string | null): Record<string, string> {
  const allowed = origin && ALLOWED_ORIGINS.has(origin)
    ? origin
    : 'https://roqbusiness.com';
  return {
    'Access-Control-Allow-Origin': allowed,
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    Vary: 'Origin',
  };
}

function json(body: unknown, status: number, origin: string | null): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), 'Content-Type': 'application/json' },
  });
}

// Trim, cap length, and reject anything that is not a string. The cap keeps a
// malicious payload from writing a megabyte into a text column.
function field(value: unknown, max: number): string {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin');

  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }

  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405, origin);
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: 'Expected a JSON body' }, 400, origin);
  }

  const businessName = field(payload.business_name, 200);
  const city = field(payload.city, 120);
  const website = field(payload.website, 300);
  const contactMethod = field(payload.contact_method, 10).toLowerCase();
  const contact = field(payload.contact, 200);
  const source = field(payload.source, 100) || 'roqbusiness.com';

  if (!businessName) return json({ error: 'business_name is required' }, 400, origin);
  if (!city) return json({ error: 'city is required' }, 400, origin);

  if (contactMethod !== 'email' && contactMethod !== 'text') {
    return json({ error: "contact_method must be 'email' or 'text'" }, 400, origin);
  }
  if (!contact) return json({ error: 'contact is required' }, 400, origin);

  if (contactMethod === 'email' && !EMAIL_RE.test(contact)) {
    return json({ error: 'contact must be a valid email address' }, 400, origin);
  }
  if (contactMethod === 'text' && contact.replace(/\D/g, '').length < 10) {
    return json({ error: 'contact must be a full phone number' }, 400, origin);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  );

  const { error } = await supabase.from('visibility_score_requests').insert({
    business_name: businessName,
    city,
    website: website || null,
    contact_method: contactMethod,
    contact,
    source,
    user_agent: req.headers.get('user-agent')?.slice(0, 500) ?? null,
  });

  if (error) {
    // Log the real reason for us; tell the visitor nothing about the schema.
    console.error('visibility_score_requests insert failed', error);
    return json({ error: 'Could not save that request' }, 500, origin);
  }

  return json({ ok: true }, 200, origin);
});
