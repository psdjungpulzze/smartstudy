defmodule FunSheep.SocialCourseShareTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Social
  alias FunSheep.Social.{CourseShare, CourseShareRecipient}
  alias FunSheep.ContentFixtures
  alias FunSheep.Gamification

  defp make_student do
    ContentFixtures.create_user_role(%{role: :student})
  end

  defp make_course do
    ContentFixtures.create_course()
  end

  # ── share_course ───────────────────────────────────────────────────────────

  describe "share_course/4" do
    test "creates a share record with recipients" do
      sharer = make_student()
      r1 = make_student()
      r2 = make_student()
      course = make_course()

      assert {:ok, share} = Social.share_course(sharer.id, course.id, [r1.id, r2.id])
      assert share.sharer_id == sharer.id
      assert share.course_id == course.id
      assert share.share_count == 1
    end

    test "increments share_count on re-share of same course" do
      sharer = make_student()
      r1 = make_student()
      r2 = make_student()
      course = make_course()

      Social.share_course(sharer.id, course.id, [r1.id])
      {:ok, second} = Social.share_course(sharer.id, course.id, [r2.id])
      assert second.share_count == 2
    end

    test "excludes sharer from recipient list" do
      sharer = make_student()
      r1 = make_student()
      course = make_course()

      {:ok, _} = Social.share_course(sharer.id, course.id, [sharer.id, r1.id])

      recipients =
        Repo.all(
          from r in CourseShareRecipient,
            join: s in assoc(r, :share),
            where: s.sharer_id == ^sharer.id and s.course_id == ^course.id
        )

      recipient_ids = Enum.map(recipients, & &1.recipient_id)
      refute sharer.id in recipient_ids
    end

    test "accepts optional message" do
      sharer = make_student()
      r1 = make_student()
      course = make_course()

      {:ok, share} =
        Social.share_course(sharer.id, course.id, [r1.id], message: "Check this out!")

      assert share.message == "Check this out!"
    end
  end

  # ── mark_share_seen ────────────────────────────────────────────────────────

  describe "mark_share_seen/2" do
    test "marks a recipient record as seen" do
      sharer = make_student()
      recipient = make_student()
      course = make_course()

      {:ok, share} = Social.share_course(sharer.id, course.id, [recipient.id])

      recipient_record =
        Repo.get_by!(CourseShareRecipient, share_id: share.id, recipient_id: recipient.id)

      assert {:ok, updated} = Social.mark_share_seen(share.id, recipient.id)
      assert updated.seen_at != nil
      _ = recipient_record
    end

    test "returns :not_found when recipient not on share" do
      sharer = make_student()
      r1 = make_student()
      other = make_student()
      course = make_course()

      {:ok, share} = Social.share_course(sharer.id, course.id, [r1.id])
      assert {:error, :not_found} = Social.mark_share_seen(share.id, other.id)
    end
  end

  # ── list_received_shares / list_sent_shares ────────────────────────────────

  describe "list_received_shares/1" do
    test "returns shares received by user" do
      sharer = make_student()
      recipient = make_student()
      course = make_course()

      Social.share_course(sharer.id, course.id, [recipient.id])

      received = Social.list_received_shares(recipient.id)
      assert length(received) == 1
    end

    test "returns empty list when no shares received" do
      student = make_student()
      assert Social.list_received_shares(student.id) == []
    end
  end

  describe "list_sent_shares/1" do
    test "returns shares sent by user" do
      sharer = make_student()
      r1 = make_student()
      course = make_course()

      Social.share_course(sharer.id, course.id, [r1.id])
      sent = Social.list_sent_shares(sharer.id)
      assert length(sent) == 1
      assert hd(sent).sharer_id == sharer.id
    end
  end

  # ── already_shared_with ────────────────────────────────────────────────────

  describe "already_shared_with/2" do
    test "returns ids of recipients already shared with" do
      sharer = make_student()
      r1 = make_student()
      r2 = make_student()
      course = make_course()

      Social.share_course(sharer.id, course.id, [r1.id])

      already = Social.already_shared_with(sharer.id, course.id)
      assert r1.id in already
      refute r2.id in already
    end

    test "returns empty list when not shared yet" do
      sharer = make_student()
      course = make_course()
      assert Social.already_shared_with(sharer.id, course.id) == []
    end
  end

  # ── shareable_followers ────────────────────────────────────────────────────

  describe "shareable_followers/2" do
    test "returns only mutual followers not yet shared with" do
      a = make_student()
      b = make_student()
      c = make_student()
      course = make_course()

      Social.follow(a.id, b.id)
      Social.follow(b.id, a.id)
      Social.follow(a.id, c.id)

      eligible = Social.shareable_followers(a.id, course.id)
      eligible_ids = Enum.map(eligible, & &1.id)

      assert b.id in eligible_ids
      refute c.id in eligible_ids
    end

    test "excludes already-shared recipients" do
      a = make_student()
      b = make_student()
      course = make_course()

      Social.follow(a.id, b.id)
      Social.follow(b.id, a.id)
      Social.share_course(a.id, course.id, [b.id])

      eligible = Social.shareable_followers(a.id, course.id)
      refute Enum.any?(eligible, &(&1.id == b.id))
    end
  end

  # ── Study Buddy XP ──────────────────────────────────────────────────────────

  describe "maybe_award_study_buddy_xp/2" do
    test "awards XP to both mutual followers studying same course" do
      a = make_student()
      b = make_student()
      course = make_course()

      Social.follow(a.id, b.id)
      Social.follow(b.id, a.id)

      Gamification.award_xp(b.id, 10, "practice", source_id: course.id)
      Social.maybe_award_study_buddy_xp(a.id, course.id)

      a_events = Gamification.source_breakdown(a.id)
      b_events = Gamification.source_breakdown(b.id)

      assert Enum.any?(a_events, &(&1.source == "study_buddy"))
      assert Enum.any?(b_events, &(&1.source == "study_buddy"))
    end

    test "does not award XP when no mutual followers" do
      a = make_student()
      b = make_student()
      course = make_course()

      Social.follow(a.id, b.id)

      Gamification.award_xp(b.id, 10, "practice", source_id: course.id)
      Social.maybe_award_study_buddy_xp(a.id, course.id)

      a_events = Gamification.source_breakdown(a.id)
      refute Enum.any?(a_events, &(&1.source == "study_buddy"))
    end

    test "awards study_buddy achievement on first time" do
      a = make_student()
      b = make_student()
      course = make_course()

      Social.follow(a.id, b.id)
      Social.follow(b.id, a.id)

      Gamification.award_xp(b.id, 10, "practice", source_id: course.id)
      Social.maybe_award_study_buddy_xp(a.id, course.id)

      achievements = Gamification.list_achievements(a.id)
      assert Enum.any?(achievements, &(&1.achievement_type == "study_buddy"))
    end

    test "is idempotent — does not double-award on same day" do
      a = make_student()
      b = make_student()
      course = make_course()

      Social.follow(a.id, b.id)
      Social.follow(b.id, a.id)

      Gamification.award_xp(b.id, 10, "practice", source_id: course.id)
      Social.maybe_award_study_buddy_xp(a.id, course.id)
      Social.maybe_award_study_buddy_xp(a.id, course.id)

      breakdown = Gamification.source_breakdown(a.id)
      buddy_entry = Enum.find(breakdown, &(&1.source == "study_buddy"))
      assert buddy_entry.amount == 5
    end
  end
end
