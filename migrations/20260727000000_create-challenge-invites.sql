-- Deferred challenge invites: when a user challenges an email that isn't a
-- BarDizz user yet, we can't create a friend_link (no addressee_id exists), so
-- we park the intent here keyed by the invitee's normalized email. A signup
-- trigger converts a matching invite into a pending friend_link once that email
-- registers, so the challenge "resolves into a friend request" (AC-C4). Rows
-- are written only through defer_challenge_invite() (SECURITY DEFINER), mirroring
-- how friend_links inserts go only through request_friend().

CREATE TABLE public.challenge_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inviter_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invitee_email TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_challenge_invite UNIQUE (inviter_id, invitee_email)
);

CREATE INDEX idx_challenge_invites_email ON public.challenge_invites (invitee_email);

ALTER TABLE public.challenge_invites ENABLE ROW LEVEL SECURITY;

-- The inviter may see their own pending invites; nobody reads by email (that
-- would leak who invited whom). No email is ever returned to a friend UI.
CREATE POLICY "challenge_invites_select" ON public.challenge_invites
  FOR SELECT TO authenticated
  USING (inviter_id = (SELECT auth.uid()));

-- All writes go through the SECURITY DEFINER functions below; the trigger that
-- resolves invites also runs as definer. No direct DML for clients.
REVOKE INSERT, UPDATE, DELETE ON public.challenge_invites FROM anon, authenticated;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON public.challenge_invites TO authenticated;

-- Park a challenge for an email that isn't a registered user yet. Normalizes
-- the email and upserts, so re-challenging the same address re-times the invite
-- rather than duplicating it (AC-C6 "re-notify, don't duplicate"). Returns:
-- 'invited' | 'invalid_email' | 'already_a_user' (caller should use
-- request_friend instead in the last case).
CREATE OR REPLACE FUNCTION public.defer_challenge_invite(target_email text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  caller uuid := auth.uid();
  norm text := lower(trim(target_email));
BEGIN
  IF caller IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF norm IS NULL OR norm = '' OR position('@' in norm) = 0 THEN
    RETURN 'invalid_email';
  END IF;
  IF EXISTS (SELECT 1 FROM auth.users WHERE lower(email) = norm) THEN
    RETURN 'already_a_user';
  END IF;
  INSERT INTO public.challenge_invites (inviter_id, invitee_email)
  VALUES (caller, norm)
  ON CONFLICT (inviter_id, invitee_email) DO UPDATE SET created_at = now();
  RETURN 'invited';
END;
$$;

REVOKE ALL ON FUNCTION public.defer_challenge_invite(text) FROM public;
GRANT EXECUTE ON FUNCTION public.defer_challenge_invite(text) TO authenticated;

-- On signup, turn any invites addressed to the new user's email into pending
-- friend requests from the inviter, then clear them. ON CONFLICT DO NOTHING
-- leans on friend_links' uq_friend_links_pair so a pre-existing link is never
-- duplicated. Runs as definer to reach both tables regardless of the new row's
-- own privileges.
CREATE OR REPLACE FUNCTION public.resolve_challenge_invites()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  inv RECORD;
BEGIN
  FOR inv IN
    SELECT * FROM public.challenge_invites WHERE invitee_email = lower(NEW.email)
  LOOP
    INSERT INTO public.friend_links (requester_id, addressee_id, status)
    VALUES (inv.inviter_id, NEW.id, 'pending')
    ON CONFLICT DO NOTHING;
    DELETE FROM public.challenge_invites WHERE id = inv.id;
  END LOOP;
  RETURN NEW;
END;
$$;

CREATE TRIGGER resolve_challenge_invites_on_signup
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.resolve_challenge_invites();
