// InsForge edge function: "challenge a friend" (spec AC-C1..C5).
//
// The mobile app POSTs { target_email } with the caller's Bearer token. This
// function decides the existing-vs-non-user branch server-side and sends the
// adaptive email via Resend from noreply@bardizz.ca -- no Resend credentials
// ever live in the app. It reuses the audited request_friend() RPC for the
// existing-user path (self/duplicate/invalid guards included) and
// defer_challenge_invite() for the non-user path.
//
// Secrets (set via `npx @insforge/cli secrets add`):
//   INSFORGE_BASE_URL   e.g. https://5e3smxnc.us-east.insforge.app
//   RESEND_API_KEY      Resend API key for the verified bardizz.ca domain
// Optional:
//   CHALLENGE_LINK_BASE universal/app link base (default https://bardizz.ca/challenge)

import { createClient } from 'npm:@insforge/sdk';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

const FROM = 'BarDizz <noreply@bardizz.ca>';

function json(status: string, httpStatus = 200): Response {
  return new Response(JSON.stringify({ status }), {
    status: httpStatus,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

function ratePct(rate: number): string {
  return `${Math.round((rate ?? 0) * 100)}%`;
}

function challengeLink(): string {
  return Deno.env.get('CHALLENGE_LINK_BASE') ?? 'https://bardizz.ca/challenge';
}

function existingUserEmail(sender: string, rate: string, count: number): { subject: string; html: string } {
  const link = challengeLink();
  return {
    subject: `${sender} challenged you on BarDizz`,
    html: `
      <div style="font-family:sans-serif">
        <h2>${sender} wants to see if you can beat their best.</h2>
        <p>High score: <strong>${rate} bar-down rate</strong> (${count} bar downs).</p>
        <p><a href="${link}">Open BarDizz</a> — you have a friend request from ${sender} waiting to accept.</p>
      </div>`,
  };
}

function inviteEmail(sender: string, rate: string, count: number): { subject: string; html: string } {
  const link = challengeLink();
  return {
    subject: `${sender} challenged you to beat their BarDizz score`,
    html: `
      <div style="font-family:sans-serif">
        <h2>${sender} thinks you can't beat this.</h2>
        <p>Their best: <strong>${rate} bar-down rate</strong> (${count} bar downs).</p>
        <p><a href="${link}">Install BarDizz to beat it.</a> Sign up with this email and you'll be
        added as ${sender}'s friend automatically.</p>
      </div>`,
  };
}

async function fetchDisplayName(baseUrl: string | undefined, token: string, userId: string): Promise<string | null> {
  try {
    const res = await fetch(`${baseUrl}/api/auth/profiles/${userId}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) return null;
    const body = await res.json();
    return (body?.profile?.name as string | undefined) ?? null;
  } catch (_) {
    return null;
  }
}

async function sendEmail(to: string, subject: string, html: string): Promise<boolean> {
  const key = Deno.env.get('RESEND_API_KEY');
  if (!key) return false;
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: FROM, to, subject, html }),
  });
  return res.ok;
}

export default async function (req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (req.method !== 'POST') return json('error', 405);

  const authHeader = req.headers.get('Authorization');
  const token = authHeader ? authHeader.replace('Bearer ', '') : null;
  if (!token) return json('error', 401);

  const baseUrl = Deno.env.get('INSFORGE_BASE_URL');
  const client = createClient({ baseUrl, accessToken: token });

  const { data: userData } = await client.auth.getCurrentUser();
  const caller = userData?.user;
  if (!caller?.id) return json('error', 401);

  let targetEmail = '';
  try {
    const body = await req.json();
    targetEmail = (body?.target_email ?? '').toString().trim();
  } catch (_) {
    return json('invalid_email');
  }
  if (!targetEmail) return json('invalid_email');

  // Sender high score for the email body (own snapshot is readable under RLS).
  // Missing snapshot => a fresh challenger with no recorded session yet: 0 is a
  // legitimate score to be challenged to beat.
  const { data: snapshot } = await client.database
    .from('snapshots')
    .select('bar_down_rate, bar_down_count')
    .eq('user_id', caller.id)
    .maybeSingle();
  const rate = ratePct((snapshot?.bar_down_rate as number) ?? 0);
  const count = (snapshot?.bar_down_count as number) ?? 0;

  // Display name comes from the profile, not the snapshot: the profile is set at
  // signup (AC-A4) and always present, whereas a snapshot only exists once a
  // high score has been published -- so challenging before your first session
  // must still use your real name, not a placeholder (AC-C1).
  const senderName = (await fetchDisplayName(baseUrl, token, caller.id)) || 'A BarDizz player';

  // Existing-user / self / duplicate / invalid all resolved by request_friend.
  const { data: rf, error: rfError } = await client.database.rpc('request_friend', {
    target_email: targetEmail,
  });
  if (rfError) return json('error', 502);
  const rfStatus = typeof rf === 'string' ? rf : (rf?.request_friend ?? rf?.result ?? '');

  if (rfStatus === 'self') return json('self');
  if (rfStatus === 'invalid_email') return json('invalid_email');

  if (rfStatus === 'requested' || rfStatus === 'duplicate') {
    // Existing user: pending request now exists (or already did -> re-notify).
    const { subject, html } = existingUserEmail(senderName, rate, count);
    await sendEmail(targetEmail, subject, html);
    return json('existing_user');
  }

  if (rfStatus === 'not_a_user') {
    const { data: di, error: diError } = await client.database.rpc('defer_challenge_invite', {
      target_email: targetEmail,
    });
    if (diError) return json('error', 502);
    const diStatus = typeof di === 'string' ? di : (di?.defer_challenge_invite ?? di?.result ?? '');
    if (diStatus === 'invalid_email') return json('invalid_email');
    // 'invited' or 'already_a_user' (race: registered between the two calls) --
    // either way an install/challenge email is the right nudge.
    const { subject, html } = inviteEmail(senderName, rate, count);
    await sendEmail(targetEmail, subject, html);
    return json('invited');
  }

  return json('error', 502);
}
