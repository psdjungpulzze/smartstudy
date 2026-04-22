defmodule FunSheep.Courses.DiscoveredTOC do
  @moduledoc """
  One recorded discovery of a course's table of contents — from web scraping,
  partial textbook OCR, or a full textbook OCR. Rows accumulate over the
  course's lifetime; exactly zero or one row is "currently applied" at a
  time (enforced by a partial unique index).

  The `chapters` field stores the raw discovered structure:

      [
        %{"name" => "Chapter 1: Cells", "sections" => ["1.1 Intro", "1.2 ..."]},
        ...
      ]

  It's the source of truth for what the discovery *found*; the actual
  `chapters`/`sections` tables hold the course's current authoritative
  structure. They diverge while a new candidate TOC is pending rebase.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @sources ~w(web textbook_partial textbook_full)

  schema "discovered_tocs" do
    field :source, :string
    field :chapter_count, :integer
    field :ocr_char_count, :integer, default: 0
    field :chapters, {:array, :map}
    field :score, :float
    field :applied_at, :utc_datetime
    field :superseded_at, :utc_datetime

    belongs_to :course, FunSheep.Courses.Course

    timestamps(type: :utc_datetime)
  end

  @required [:course_id, :source, :chapter_count, :chapters, :score]
  @optional [:ocr_char_count, :applied_at, :superseded_at]

  @doc false
  def changeset(record, attrs) do
    record
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:source, @sources)
    |> validate_number(:chapter_count, greater_than_or_equal_to: 0)
    |> validate_number(:ocr_char_count, greater_than_or_equal_to: 0)
    |> validate_number(:score, greater_than_or_equal_to: 0.0)
    |> foreign_key_constraint(:course_id)
  end

  @doc "Returns the allowed source enum values."
  def sources, do: @sources
end
