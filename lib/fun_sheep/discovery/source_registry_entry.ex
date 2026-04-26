defmodule FunSheep.Discovery.SourceRegistryEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "source_registry_entries" do
    field :test_type, :string
    field :catalog_subject, :string
    field :url_or_pattern, :string
    field :domain, :string
    field :source_type, :string
    field :tier, :integer
    field :is_enabled, :boolean, default: true
    field :extractor_module, :string
    field :avg_questions_per_page, :integer
    field :consecutive_failures, :integer, default: 0
    field :last_verified_at, :utc_datetime
    field :notes, :string

    timestamps(type: :utc_datetime)
  end

  @valid_source_types ~w(question_bank practice_test official study_guide curriculum video)
  @valid_tiers 1..4

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :test_type,
      :catalog_subject,
      :url_or_pattern,
      :domain,
      :source_type,
      :tier,
      :is_enabled,
      :extractor_module,
      :avg_questions_per_page,
      :consecutive_failures,
      :last_verified_at,
      :notes
    ])
    |> validate_required([:test_type, :url_or_pattern, :domain, :source_type, :tier])
    |> validate_inclusion(:source_type, @valid_source_types)
    |> validate_inclusion(:tier, Enum.to_list(@valid_tiers))
    |> validate_number(:avg_questions_per_page, greater_than: 0)
    |> validate_number(:consecutive_failures, greater_than_or_equal_to: 0)
    |> unique_constraint([:test_type, :catalog_subject, :url_or_pattern])
  end
end
