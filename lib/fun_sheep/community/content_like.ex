defmodule FunSheep.Community.ContentLike do
  @moduledoc """
  Schema for a user's like or dislike reaction to a content item.

  Currently supports course-level reactions. The `context` field is reserved
  for future granular tracking (e.g. post-test, per-question).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "content_likes" do
    belongs_to :user_role, FunSheep.Accounts.UserRole
    belongs_to :course, FunSheep.Courses.Course

    # "like" or "dislike"
    field :reaction, :string

    # Reserved for granular context: "course_completion", "post_test", "question_answer"
    field :context, :string

    timestamps(type: :utc_datetime)
  end

  @valid_reactions ["like", "dislike"]

  def changeset(like, attrs) do
    like
    |> cast(attrs, [:user_role_id, :course_id, :reaction, :context])
    |> validate_required([:user_role_id, :reaction])
    |> validate_inclusion(:reaction, @valid_reactions)
    |> validate_at_least_one_target()
    |> unique_constraint([:user_role_id, :course_id],
      name: :content_likes_user_course_unique,
      message: "already reacted to this course"
    )
    |> foreign_key_constraint(:user_role_id)
    |> foreign_key_constraint(:course_id)
  end

  defp validate_at_least_one_target(changeset) do
    course_id = get_field(changeset, :course_id)

    if is_nil(course_id) do
      add_error(changeset, :course_id, "must react to something (course_id required)")
    else
      changeset
    end
  end
end
