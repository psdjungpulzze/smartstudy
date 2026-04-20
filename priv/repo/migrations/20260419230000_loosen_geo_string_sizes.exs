defmodule FunSheep.Repo.Migrations.LoosenGeoStringSizes do
  @moduledoc """
  NCES CCD's `LEA_TYPE_TEXT` values like
  "Regular local school district that is a component of a supervisory union"
  overflow the 32-char cap. Real registry data is wider than the spec
  document implies — widen every classification/status column to text so
  we store whatever the upstream says.
  """

  use Ecto.Migration

  def change do
    for table <- [:districts, :schools, :universities] do
      alter table(table) do
        modify :type, :text, from: :string
        modify :operational_status, :text, from: :string
      end
    end

    alter table(:schools) do
      modify :level, :text, from: :string
      modify :locale_code, :text, from: :string
      modify :lowest_grade, :text, from: :string
      modify :highest_grade, :text, from: :string
    end

    alter table(:universities) do
      modify :control, :text, from: :string
      modify :level, :text, from: :string
    end

    alter table(:states) do
      modify :subdivision_type, :text, from: :string
    end
  end
end
