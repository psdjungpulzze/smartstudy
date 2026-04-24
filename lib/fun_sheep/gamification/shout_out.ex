defmodule FunSheep.Gamification.ShoutOut do
  @moduledoc """
  Schema for weekly/monthly shout out winners.

  Shout outs spotlight the top performer in each category for a given period.
  Records are computed by `ComputeShoutOutsWorker` and displayed on the
  Flock leaderboard's Shout Outs tab.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @categories ~w(most_xp most_tests_taken most_textbooks_uploaded most_tests_created longest_streak most_generous_teacher)

  def categories, do: @categories

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "shout_outs" do
    field :category, :string
    field :period, :string, default: "weekly"
    field :period_start, :date
    field :period_end, :date
    field :metric_value, :integer

    belongs_to :user_role, FunSheep.Accounts.UserRole

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(shout_out, attrs) do
    shout_out
    |> cast(attrs, [:category, :period, :period_start, :period_end, :metric_value, :user_role_id])
    |> validate_required([
      :category,
      :period,
      :period_start,
      :period_end,
      :metric_value,
      :user_role_id
    ])
    |> validate_inclusion(:category, @categories)
    |> validate_inclusion(:period, ["weekly", "monthly"])
  end

  @doc """
  Returns display metadata for a given category.

  ## Examples

      iex> FunSheep.Gamification.ShoutOut.display_info("most_xp")
      %{label: "Most Active", icon: "⚡", unit: "FP"}

  """
  def display_info("most_xp"), do: %{label: "Most Active", icon: "⚡", unit: "FP"}
  def display_info("most_tests_taken"), do: %{label: "Test Taker", icon: "🎯", unit: "tests"}
  def display_info("most_textbooks_uploaded"), do: %{label: "Bookworm", icon: "📚", unit: "books"}

  def display_info("most_tests_created"),
    do: %{label: "Test Builder", icon: "✍️", unit: "tests created"}

  def display_info("longest_streak"), do: %{label: "Streak Star", icon: "🔥", unit: "days"}

  def display_info("most_generous_teacher"),
    do: %{label: "Giving Back", icon: "🎁", unit: "credits given"}

  def display_info(_), do: %{label: "Mystery", icon: "❓", unit: ""}
end
