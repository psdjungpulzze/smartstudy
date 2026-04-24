defmodule FunSheep.Social.CourseShare do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "course_shares" do
    field :message, :string
    field :share_count, :integer, default: 1

    belongs_to :sharer, FunSheep.Accounts.UserRole
    belongs_to :course, FunSheep.Courses.Course

    has_many :recipients, FunSheep.Social.CourseShareRecipient, foreign_key: :share_id

    timestamps(updated_at: false)
  end

  def changeset(share, attrs) do
    share
    |> cast(attrs, [:sharer_id, :course_id, :message, :share_count])
    |> validate_required([:sharer_id, :course_id])
    |> validate_number(:share_count, greater_than: 0)
  end
end
