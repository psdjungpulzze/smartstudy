# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     StudySmart.Repo.insert!(%StudySmart.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias StudySmart.Repo
alias StudySmart.Geo.{Country, State, District, School}
alias StudySmart.Learning.Hobby
alias StudySmart.Courses.{Course, Chapter}

import Ecto.Query

# Helper: find or create a record
defmodule Seeds do
  def find_or_create!(repo, schema, match_attrs, extra_attrs \\ %{}) do
    case repo.get_by(schema, Map.to_list(match_attrs)) do
      nil ->
        attrs = Map.merge(match_attrs, extra_attrs)

        struct(schema)
        |> schema.changeset(attrs)
        |> repo.insert!()

      existing ->
        existing
    end
  end
end

# ── Countries ──────────────────────────────────────────────────────────────────

us = Seeds.find_or_create!(Repo, Country, %{code: "US"}, %{name: "United States"})
kr = Seeds.find_or_create!(Repo, Country, %{code: "KR"}, %{name: "South Korea"})
jp = Seeds.find_or_create!(Repo, Country, %{code: "JP"}, %{name: "Japan"})

IO.puts("Seeded #{Repo.aggregate(Country, :count)} countries")

# ── States ─────────────────────────────────────────────────────────────────────

california = Seeds.find_or_create!(Repo, State, %{name: "California", country_id: us.id})
_new_york = Seeds.find_or_create!(Repo, State, %{name: "New York", country_id: us.id})
_texas = Seeds.find_or_create!(Repo, State, %{name: "Texas", country_id: us.id})
seoul = Seeds.find_or_create!(Repo, State, %{name: "Seoul", country_id: kr.id})
_gyeonggi = Seeds.find_or_create!(Repo, State, %{name: "Gyeonggi", country_id: kr.id})
_tokyo = Seeds.find_or_create!(Repo, State, %{name: "Tokyo", country_id: jp.id})
_osaka = Seeds.find_or_create!(Repo, State, %{name: "Osaka", country_id: jp.id})

IO.puts("Seeded #{Repo.aggregate(State, :count)} states")

# ── Districts ──────────────────────────────────────────────────────────────────

saratoga_district =
  Seeds.find_or_create!(Repo, District, %{
    name: "Saratoga Union School District",
    state_id: california.id
  })

_cupertino_district =
  Seeds.find_or_create!(Repo, District, %{
    name: "Cupertino Union School District",
    state_id: california.id
  })

gangnam_district =
  Seeds.find_or_create!(Repo, District, %{name: "Gangnam District", state_id: seoul.id})

_seocho_district =
  Seeds.find_or_create!(Repo, District, %{name: "Seocho District", state_id: seoul.id})

IO.puts("Seeded #{Repo.aggregate(District, :count)} districts")

# ── Schools ────────────────────────────────────────────────────────────────────

saratoga_high =
  Seeds.find_or_create!(Repo, School, %{
    name: "Saratoga High School",
    district_id: saratoga_district.id
  })

_redwood_middle =
  Seeds.find_or_create!(Repo, School, %{
    name: "Redwood Middle School",
    district_id: saratoga_district.id
  })

_gangnam_high =
  Seeds.find_or_create!(Repo, School, %{
    name: "Gangnam High School",
    district_id: gangnam_district.id
  })

IO.puts("Seeded #{Repo.aggregate(School, :count)} schools")

# ── Hobbies ────────────────────────────────────────────────────────────────────

hobbies_data = [
  %{
    name: "KPOP",
    category: "Music",
    region_relevance: %{"KR" => 0.9, "US" => 0.6, "JP" => 0.7}
  },
  %{
    name: "Basketball",
    category: "Sports",
    region_relevance: %{"US" => 0.9, "KR" => 0.5, "JP" => 0.5}
  },
  %{
    name: "Gaming",
    category: "Entertainment",
    region_relevance: %{"US" => 0.8, "KR" => 0.9, "JP" => 0.9}
  },
  %{
    name: "Drawing",
    category: "Art",
    region_relevance: %{"US" => 0.7, "KR" => 0.7, "JP" => 0.8}
  },
  %{
    name: "Coding",
    category: "Technology",
    region_relevance: %{"US" => 0.8, "KR" => 0.7, "JP" => 0.7}
  },
  %{
    name: "Dance",
    category: "Performing Arts",
    region_relevance: %{"US" => 0.6, "KR" => 0.8, "JP" => 0.6}
  },
  %{
    name: "Soccer",
    category: "Sports",
    region_relevance: %{"US" => 0.6, "KR" => 0.7, "JP" => 0.7}
  },
  %{
    name: "Anime",
    category: "Entertainment",
    region_relevance: %{"US" => 0.7, "KR" => 0.6, "JP" => 0.95}
  },
  %{
    name: "Reading",
    category: "Literature",
    region_relevance: %{"US" => 0.7, "KR" => 0.7, "JP" => 0.7}
  },
  %{
    name: "Cooking",
    category: "Lifestyle",
    region_relevance: %{"US" => 0.6, "KR" => 0.7, "JP" => 0.8}
  }
]

for attrs <- hobbies_data do
  Seeds.find_or_create!(Repo, Hobby, %{name: attrs.name}, Map.delete(attrs, :name))
end

IO.puts("Seeded #{Repo.aggregate(Hobby, :count)} hobbies")

# ── Courses ────────────────────────────────────────────────────────────────────
# Note: Schema/migration mismatch for courses and chapters, so we use raw SQL.

now = DateTime.utc_now() |> DateTime.truncate(:second)

# Helper to generate binary UUIDs for raw SQL
gen_uuid = fn -> Ecto.UUID.bingenerate() end

dump_uuid = fn uuid_string ->
  {:ok, bin} = Ecto.UUID.dump(uuid_string)
  bin
end

# AP Biology
%{rows: rows} =
  Repo.query!(
    "SELECT id FROM courses WHERE subject = $1 AND grade = $2",
    ["AP Biology", "11"]
  )

ap_bio_id =
  case rows do
    [[id]] ->
      id

    [] ->
      id = gen_uuid.()

      Repo.query!(
        """
        INSERT INTO courses (id, name, subject, grade, school_id, inserted_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        """,
        [id, "AP Biology", "AP Biology", "11", dump_uuid.(saratoga_high.id), now, now]
      )

      id
  end

# Algebra 2
%{rows: rows} =
  Repo.query!(
    "SELECT id FROM courses WHERE subject = $1 AND grade = $2",
    ["Algebra 2", "10"]
  )

case rows do
  [[_id]] ->
    :ok

  [] ->
    id = gen_uuid.()

    Repo.query!(
      """
      INSERT INTO courses (id, name, subject, grade, inserted_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6)
      """,
      [id, "Algebra 2", "Algebra 2", "10", now, now]
    )
end

IO.puts("Seeded courses")

# ── Chapters (for AP Biology) ─────────────────────────────────────────────────

chapters_data = [
  %{name: "Chemistry of Life", position: 1},
  %{name: "Cell Structure", position: 2},
  %{name: "Cellular Energetics", position: 3}
]

for attrs <- chapters_data do
  %{rows: rows} =
    Repo.query!(
      "SELECT id FROM chapters WHERE name = $1 AND course_id = $2",
      [attrs.name, ap_bio_id]
    )

  if rows == [] do
    id = gen_uuid.()

    Repo.query!(
      """
      INSERT INTO chapters (id, course_id, name, position, inserted_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6)
      """,
      [id, ap_bio_id, attrs.name, attrs.position, now, now]
    )
  end
end

IO.puts("Seeded chapters")

IO.puts("\nSeed data loaded successfully!")
