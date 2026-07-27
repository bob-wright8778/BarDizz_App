-- Friend graph: mutual-consent links keyed by user id. Adding a friend is done
-- through request_friend(email) so the app never reads auth.users directly and
-- an email is never returned to any client.

CREATE TABLE public.friend_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  addressee_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT friend_links_not_self CHECK (requester_id <> addressee_id)
);

CREATE INDEX idx_friend_links_requester ON public.friend_links (requester_id);
CREATE INDEX idx_friend_links_addressee ON public.friend_links (addressee_id);

-- One link per unordered pair: blocks a duplicate A->B and a reverse B->A alike.
CREATE UNIQUE INDEX uq_friend_links_pair ON public.friend_links (
  LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id)
);

ALTER TABLE public.friend_links ENABLE ROW LEVEL SECURITY;

-- Either party can see the link.
CREATE POLICY "friend_links_select" ON public.friend_links
  FOR SELECT TO authenticated
  USING (requester_id = (SELECT auth.uid()) OR addressee_id = (SELECT auth.uid()));

-- Only the addressee may accept (pending -> accepted); the trigger enforces the
-- transition and column immutability.
CREATE POLICY "friend_links_accept" ON public.friend_links
  FOR UPDATE TO authenticated
  USING (addressee_id = (SELECT auth.uid()))
  WITH CHECK (addressee_id = (SELECT auth.uid()) AND status = 'accepted');

-- Either party may delete: decline a pending request, or unfriend an accepted one.
CREATE POLICY "friend_links_delete" ON public.friend_links
  FOR DELETE TO authenticated
  USING (requester_id = (SELECT auth.uid()) OR addressee_id = (SELECT auth.uid()));

-- Force all inserts through request_friend(); narrow updates to status only.
REVOKE INSERT ON public.friend_links FROM anon, authenticated;
REVOKE UPDATE ON public.friend_links FROM anon, authenticated;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, DELETE ON public.friend_links TO authenticated;
GRANT UPDATE (status) ON public.friend_links TO authenticated;

CREATE TRIGGER friend_links_updated_at
  BEFORE UPDATE ON public.friend_links
  FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();

-- Guards identity/created_at immutability and the pending -> accepted transition
-- (RLS decides who reaches the row; this decides what the row may become).
CREATE OR REPLACE FUNCTION public.friend_links_guard_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.requester_id IS DISTINCT FROM OLD.requester_id
     OR NEW.addressee_id IS DISTINCT FROM OLD.addressee_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'friend_links: identity columns are immutable';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT (OLD.status = 'pending' AND NEW.status = 'accepted') THEN
    RAISE EXCEPTION 'friend_links: invalid status transition % -> %', OLD.status, NEW.status;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER friend_links_guard
  BEFORE UPDATE ON public.friend_links
  FOR EACH ROW EXECUTE FUNCTION public.friend_links_guard_update();

-- Resolve an email to a user server-side and create a pending request, applying
-- the not-a-user / self / duplicate guards atomically. Returns a status code:
-- 'requested' | 'not_a_user' | 'self' | 'duplicate' | 'invalid_email'.
CREATE OR REPLACE FUNCTION public.request_friend(target_email text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  caller uuid := auth.uid();
  target uuid;
  norm text := lower(trim(target_email));
BEGIN
  IF caller IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF norm IS NULL OR norm = '' THEN
    RETURN 'invalid_email';
  END IF;
  SELECT id INTO target FROM auth.users WHERE lower(email) = norm LIMIT 1;
  IF target IS NULL THEN
    RETURN 'not_a_user';
  END IF;
  IF target = caller THEN
    RETURN 'self';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.friend_links
    WHERE (requester_id = caller AND addressee_id = target)
       OR (requester_id = target AND addressee_id = caller)
  ) THEN
    RETURN 'duplicate';
  END IF;
  INSERT INTO public.friend_links (requester_id, addressee_id, status)
  VALUES (caller, target, 'pending');
  RETURN 'requested';
END;
$$;

REVOKE ALL ON FUNCTION public.request_friend(text) FROM public;
GRANT EXECUTE ON FUNCTION public.request_friend(text) TO authenticated;
