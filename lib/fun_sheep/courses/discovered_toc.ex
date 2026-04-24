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

  # Extended source type values — richer origin tracking for TOC rows.
  # "scraped"     — web scraping (maps to legacy "web" source)
  # "ebook_toc"   — parsed directly from EPUB/MOBI navigation document
  # "ai_inferred" — inferred by AI from OCR text
  @source_types ~w(scraped ebook_toc ai_inferred)

  schema "discovered_tocs" do
    field :source, :string
    field :chapter_count, :integer
    field :ocr_char_count, :integer, default: 0
    field :chapters, {:array, :map}
    field :score, :float
    field :applied_at, :utc_datetime
    field :superseded_at, :utc_datetime

    # Which uploaded material this TOC was extracted from.
    # Nil for web-scraped and AI-inferred TOCs.
    field :source_type, :string, default: "scraped"

    belongs_to :course, FunSheep.Courses.Course
    belongs_to :source_material, FunSheep.Content.UploadedMaterial

    timestamps(type: :utc_datetime)
  end

  @required [:course_id, :source, :chapter_count, :chapters, :score]
  @optional [:ocr_char_count, :applied_at, :superseded_at, :source_type, :source_material_id]

  @doc false
  def changeset(record, attrs) do
    record
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:source_type, @source_types)
    |> validate_number(:chapter_count, greater_than_or_equal_to: 0)
    |> validate_number(:ocr_char_count, greater_than_or_equal_to: 0)
    |> validate_number(:score, greater_than_or_equal_to: 0.0)
    |> foreign_key_constraint(:course_id)
    |> foreign_key_constraint(:source_material_id)
  end

  @doc "Returns the allowed source enum values."
  def sources, do: @sources

  @doc "Returns the allowed source_type values."
  def source_types, do: @source_types
end
