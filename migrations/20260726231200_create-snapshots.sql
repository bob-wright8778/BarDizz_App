-- Per-user published high-score snapshot: display name, avatar, bar-down
-- rate/count, so friends' leaderboard rows can be read without exposing
-- email. One row per user, self-write-only; reads are scoped to self plus
-- accepted friends (mirrors friend_links' accepted-pair check).

CREATE TABLE public.snapshots (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  avatar_id TEXT,
  bar_down_rate DOUBLE PRECISION NOT NULL DEFAULT 0,
  bar_down_count INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.snapshots ENABLE ROW LEVEL SECURITY;

-- Read own row, or an accepted friend's row.
CREATE POLICY "snapshots_select" ON public.snapshots
  FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.friend_links f
      WHERE f.status = 'accepted'
        AND (
          (f.requester_id = (SELECT auth.uid()) AND f.addressee_id = snapshots.user_id)
          OR (f.addressee_id = (SELECT auth.uid()) AND f.requester_id = snapshots.user_id)
        )
    )
  );

-- Self-write-only: insert/update own row only.
CREATE POLICY "snapshots_insert" ON public.snapshots
  FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "snapshots_update" ON public.snapshots
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.snapshots TO authenticated;

CREATE TRIGGER snapshots_updated_at
  BEFORE UPDATE ON public.snapshots
  FOR EACH ROW EXECUTE FUNCTION system.update_updated_at();
