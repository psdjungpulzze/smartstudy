defmodule FunSheep.Content.DiscoveredSource do
  @moduledoc """
  Schema for content sources discovered via web search.

  When a course is created, the system searches the web for relevant
  textbooks, question banks, practice tests, and study materials.
  Each found source is recorded here with its URL, type, and processing status.

  Source types:
  - "official" — official resource from the test maker or governing body
  - "textbook" — a known textbook (e.g., Campbell Biology, Pearson AP prep)
  - "question_bank" — online question collections, practice problems
  - "practice_test" — full practice exams, past papers
  - "study_guide" — study notes, review sheets, flashcards
  - "curriculum" — official curriculum/syllabus documents
  - "video" — educational video content references

  Processing flow: discovered → scraping → scraped → processed
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "discovered_sources" do
    field :source_type, :string
    field :title, :string
    field :url, :string
    field :description, :string
    field :publisher, :string
    field :content_preview, :string
    field :status, :string, default: "discovered"
    field :questions_extracted, :integer, default: 0
    field :content_size_bytes, :integer, default: 0
    field :scraped_text, :string
    field :search_query, :string
    field :confidence_score, :float, default: 0.0
    field :error_message, :string
    field :discovery_strategy, :string, default: "web_search"
    field :scrape_attempts, :integer, default: 0
    field :last_scraped_at, :utc_datetime

    belongs_to :course, FunSheep.Courses.Course
    belongs_to :section, FunSheep.Courses.Section

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(source, attrs) do
    source
    |> cast(attrs, [
      :source_type,
      :title,
      :url,
      :description,
      :publisher,
      :content_preview,
      :status,
      :questions_extracted,
      :content_size_bytes,
      :scraped_text,
      :search_query,
      :confidence_score,
      :error_message,
      :discovery_strategy,
      :scrape_attempts,
      :last_scraped_at,
      :course_id,
      :section_id
    ])
    |> validate_required([:source_type, :title, :course_id])
    |> validate_inclusion(
      :source_type,
      ~w(official textbook question_bank practice_test study_guide curriculum video)
    )
    |> validate_inclusion(:status, ~w(discovered scraping scraped processed failed skipped))
    |> foreign_key_constraint(:course_id)
    |> foreign_key_constraint(:section_id)
    |> unique_constraint([:course_id, :url])
  end
end
