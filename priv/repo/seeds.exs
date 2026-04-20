# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     FunSheep.Repo.insert!(%FunSheep.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias FunSheep.Repo
alias FunSheep.Geo.{Country, State, District, School}
alias FunSheep.Learning.Hobby
alias FunSheep.Courses.{Course, Chapter}

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

countries_data = [
  # Major English-speaking
  %{code: "US", name: "United States"},
  %{code: "CA", name: "Canada"},
  %{code: "GB", name: "United Kingdom"},
  %{code: "AU", name: "Australia"},
  %{code: "NZ", name: "New Zealand"},
  %{code: "IE", name: "Ireland"},
  # East Asia
  %{code: "KR", name: "South Korea"},
  %{code: "JP", name: "Japan"},
  %{code: "CN", name: "China"},
  %{code: "TW", name: "Taiwan"},
  %{code: "HK", name: "Hong Kong"},
  # Southeast Asia
  %{code: "SG", name: "Singapore"},
  %{code: "PH", name: "Philippines"},
  %{code: "VN", name: "Vietnam"},
  %{code: "TH", name: "Thailand"},
  %{code: "MY", name: "Malaysia"},
  %{code: "ID", name: "Indonesia"},
  # South Asia
  %{code: "IN", name: "India"},
  %{code: "PK", name: "Pakistan"},
  %{code: "BD", name: "Bangladesh"},
  # Europe
  %{code: "DE", name: "Germany"},
  %{code: "FR", name: "France"},
  %{code: "IT", name: "Italy"},
  %{code: "ES", name: "Spain"},
  %{code: "NL", name: "Netherlands"},
  %{code: "SE", name: "Sweden"},
  %{code: "CH", name: "Switzerland"},
  # Americas
  %{code: "MX", name: "Mexico"},
  %{code: "BR", name: "Brazil"},
  %{code: "AR", name: "Argentina"},
  %{code: "CO", name: "Colombia"},
  # Middle East / Africa
  %{code: "AE", name: "United Arab Emirates"},
  %{code: "SA", name: "Saudi Arabia"},
  %{code: "IL", name: "Israel"},
  %{code: "ZA", name: "South Africa"},
  %{code: "NG", name: "Nigeria"},
  %{code: "EG", name: "Egypt"},
  %{code: "KE", name: "Kenya"}
]

countries =
  for attrs <- countries_data, into: %{} do
    c = Seeds.find_or_create!(Repo, Country, %{code: attrs.code}, %{name: attrs.name})
    {attrs.code, c}
  end

IO.puts("Seeded #{Repo.aggregate(Country, :count)} countries")

# ── US States (all 50 + DC) ──────────────────────────────────────────────────

us_states_data = [
  "Alabama",
  "Alaska",
  "Arizona",
  "Arkansas",
  "California",
  "Colorado",
  "Connecticut",
  "Delaware",
  "District of Columbia",
  "Florida",
  "Georgia",
  "Hawaii",
  "Idaho",
  "Illinois",
  "Indiana",
  "Iowa",
  "Kansas",
  "Kentucky",
  "Louisiana",
  "Maine",
  "Maryland",
  "Massachusetts",
  "Michigan",
  "Minnesota",
  "Mississippi",
  "Missouri",
  "Montana",
  "Nebraska",
  "Nevada",
  "New Hampshire",
  "New Jersey",
  "New Mexico",
  "New York",
  "North Carolina",
  "North Dakota",
  "Ohio",
  "Oklahoma",
  "Oregon",
  "Pennsylvania",
  "Rhode Island",
  "South Carolina",
  "South Dakota",
  "Tennessee",
  "Texas",
  "Utah",
  "Vermont",
  "Virginia",
  "Washington",
  "West Virginia",
  "Wisconsin",
  "Wyoming"
]

us_states =
  for name <- us_states_data, into: %{} do
    s = Seeds.find_or_create!(Repo, State, %{name: name, country_id: countries["US"].id})
    {name, s}
  end

# ── Canadian Provinces ────────────────────────────────────────────────────────

ca_provinces_data = [
  "Alberta",
  "British Columbia",
  "Manitoba",
  "New Brunswick",
  "Newfoundland and Labrador",
  "Nova Scotia",
  "Ontario",
  "Prince Edward Island",
  "Quebec",
  "Saskatchewan",
  "Northwest Territories",
  "Nunavut",
  "Yukon"
]

ca_provinces =
  for name <- ca_provinces_data, into: %{} do
    s = Seeds.find_or_create!(Repo, State, %{name: name, country_id: countries["CA"].id})
    {name, s}
  end

# ── South Korean Provinces (시/도) ───────────────────────────────────────────

kr_provinces_data = [
  "Seoul (서울)",
  "Busan (부산)",
  "Daegu (대구)",
  "Incheon (인천)",
  "Gwangju (광주)",
  "Daejeon (대전)",
  "Ulsan (울산)",
  "Sejong (세종)",
  "Gyeonggi (경기)",
  "Gangwon (강원)",
  "Chungbuk (충북)",
  "Chungnam (충남)",
  "Jeonbuk (전북)",
  "Jeonnam (전남)",
  "Gyeongbuk (경북)",
  "Gyeongnam (경남)",
  "Jeju (제주)"
]

kr_provinces =
  for name <- kr_provinces_data, into: %{} do
    s = Seeds.find_or_create!(Repo, State, %{name: name, country_id: countries["KR"].id})
    {name, s}
  end

# ── Japanese Prefectures (selected major ones) ──────────────────────────────

jp_prefectures_data = [
  "Tokyo",
  "Osaka",
  "Kyoto",
  "Kanagawa",
  "Aichi",
  "Hokkaido",
  "Fukuoka",
  "Hyogo",
  "Saitama",
  "Chiba"
]

for name <- jp_prefectures_data do
  Seeds.find_or_create!(Repo, State, %{name: name, country_id: countries["JP"].id})
end

# ── UK Regions ────────────────────────────────────────────────────────────────

gb_regions_data = [
  "England",
  "Scotland",
  "Wales",
  "Northern Ireland"
]

for name <- gb_regions_data do
  Seeds.find_or_create!(Repo, State, %{name: name, country_id: countries["GB"].id})
end

# ── Australian States ─────────────────────────────────────────────────────────

au_states_data = [
  "New South Wales",
  "Victoria",
  "Queensland",
  "South Australia",
  "Western Australia",
  "Tasmania",
  "Northern Territory",
  "Australian Capital Territory"
]

for name <- au_states_data do
  Seeds.find_or_create!(Repo, State, %{name: name, country_id: countries["AU"].id})
end

IO.puts("Seeded #{Repo.aggregate(State, :count)} states/provinces")

# ── US Districts & Schools (California) ──────────────────────────────────────

ca_districts_schools = [
  {"Saratoga Union School District",
   [
     "Saratoga High School",
     "Redwood Middle School",
     "Argonaut Elementary School"
   ]},
  {"Cupertino Union School District",
   [
     "Monta Vista High School",
     "Lynbrook High School",
     "Cupertino Middle School",
     "Kennedy Middle School"
   ]},
  {"Fremont Union High School District",
   [
     "Fremont High School",
     "Homestead High School"
   ]},
  {"Los Gatos-Saratoga Joint Union High School District",
   [
     "Los Gatos High School"
   ]},
  {"Palo Alto Unified School District",
   [
     "Palo Alto High School",
     "Gunn High School",
     "JLS Middle School"
   ]},
  {"San Jose Unified School District",
   [
     "Abraham Lincoln High School",
     "Willow Glen High School",
     "Pioneer High School"
   ]},
  {"Los Angeles Unified School District",
   [
     "Los Angeles High School",
     "Hollywood High School",
     "Fairfax High School"
   ]},
  {"San Francisco Unified School District",
   [
     "Lowell High School",
     "Washington High School",
     "Balboa High School"
   ]}
]

for {district_name, school_names} <- ca_districts_schools do
  d =
    Seeds.find_or_create!(Repo, District, %{
      name: district_name,
      state_id: us_states["California"].id
    })

  for school_name <- school_names do
    Seeds.find_or_create!(Repo, School, %{name: school_name, district_id: d.id})
  end
end

# ── US Districts & Schools (New York) ────────────────────────────────────────

ny_districts_schools = [
  {"New York City Department of Education",
   [
     "Stuyvesant High School",
     "Bronx Science High School",
     "Brooklyn Technical High School",
     "Townsend Harris High School"
   ]},
  {"Great Neck Public Schools",
   [
     "Great Neck South High School",
     "Great Neck North High School"
   ]}
]

for {district_name, school_names} <- ny_districts_schools do
  d =
    Seeds.find_or_create!(Repo, District, %{
      name: district_name,
      state_id: us_states["New York"].id
    })

  for school_name <- school_names do
    Seeds.find_or_create!(Repo, School, %{name: school_name, district_id: d.id})
  end
end

# ── US Districts & Schools (Texas) ───────────────────────────────────────────

tx_districts_schools = [
  {"Houston Independent School District",
   [
     "Bellaire High School",
     "Lamar High School",
     "Westside High School"
   ]},
  {"Dallas Independent School District",
   [
     "School for the Talented and Gifted",
     "Booker T. Washington High School"
   ]},
  {"Plano Independent School District",
   [
     "Plano Senior High School",
     "Plano West Senior High School",
     "Plano East Senior High School"
   ]}
]

for {district_name, school_names} <- tx_districts_schools do
  d =
    Seeds.find_or_create!(Repo, District, %{name: district_name, state_id: us_states["Texas"].id})

  for school_name <- school_names do
    Seeds.find_or_create!(Repo, School, %{name: school_name, district_id: d.id})
  end
end

# ── US Districts & Schools (New Jersey) ──────────────────────────────────────

nj_districts_schools = [
  {"Bergen County Academies",
   [
     "Bergen County Academies"
   ]},
  {"Fort Lee School District",
   [
     "Fort Lee High School"
   ]},
  {"Palisades Park School District",
   [
     "Palisades Park Jr/Sr High School"
   ]}
]

for {district_name, school_names} <- nj_districts_schools do
  d =
    Seeds.find_or_create!(Repo, District, %{
      name: district_name,
      state_id: us_states["New Jersey"].id
    })

  for school_name <- school_names do
    Seeds.find_or_create!(Repo, School, %{name: school_name, district_id: d.id})
  end
end

# ── US Districts & Schools (Virginia) ────────────────────────────────────────

va_districts_schools = [
  {"Fairfax County Public Schools",
   [
     "Thomas Jefferson High School for Science and Technology",
     "Langley High School",
     "McLean High School"
   ]}
]

for {district_name, school_names} <- va_districts_schools do
  d =
    Seeds.find_or_create!(Repo, District, %{
      name: district_name,
      state_id: us_states["Virginia"].id
    })

  for school_name <- school_names do
    Seeds.find_or_create!(Repo, School, %{name: school_name, district_id: d.id})
  end
end

# ── South Korea Districts & Schools (Seoul) ──────────────────────────────────

seoul_districts_schools = [
  {"강남구 (Gangnam)",
   [
     "대치고등학교 (Daechi High School)",
     "휘문고등학교 (Hwimun High School)",
     "경기고등학교 (Kyunggi High School)",
     "숙명여자고등학교 (Sookmyung Girls' High School)"
   ]},
  {"서초구 (Seocho)",
   [
     "서초고등학교 (Seocho High School)",
     "세화고등학교 (Sehwa High School)",
     "반포고등학교 (Banpo High School)"
   ]},
  {"송파구 (Songpa)",
   [
     "보인고등학교 (Boin High School)",
     "잠실고등학교 (Jamsil High School)"
   ]},
  {"종로구 (Jongno)",
   [
     "경복고등학교 (Gyeongbok High School)",
     "용산국제학교 (Yongsan International School)"
   ]},
  {"마포구 (Mapo)",
   [
     "서울국제학교 (Seoul Foreign School)",
     "마포고등학교 (Mapo High School)"
   ]}
]

for {district_name, school_names} <- seoul_districts_schools do
  d =
    Seeds.find_or_create!(Repo, District, %{
      name: district_name,
      state_id: kr_provinces["Seoul (서울)"].id
    })

  for school_name <- school_names do
    Seeds.find_or_create!(Repo, School, %{name: school_name, district_id: d.id})
  end
end

# ── South Korea Districts & Schools (Gyeonggi) ──────────────────────────────

gyeonggi_districts_schools = [
  {"분당구 (Bundang)",
   [
     "분당고등학교 (Bundang High School)",
     "낙생고등학교 (Naksaeng High School)"
   ]},
  {"수지구 (Suji)",
   [
     "수지고등학교 (Suji High School)"
   ]},
  {"일산 (Ilsan)",
   [
     "백석고등학교 (Baekseok High School)"
   ]}
]

for {district_name, school_names} <- gyeonggi_districts_schools do
  d =
    Seeds.find_or_create!(Repo, District, %{
      name: district_name,
      state_id: kr_provinces["Gyeonggi (경기)"].id
    })

  for school_name <- school_names do
    Seeds.find_or_create!(Repo, School, %{name: school_name, district_id: d.id})
  end
end

# ── Canadian Districts & Schools (Ontario) ───────────────────────────────────

on_districts_schools = [
  {"Toronto District School Board",
   [
     "University of Toronto Schools",
     "Marc Garneau Collegiate Institute"
   ]}
]

for {district_name, school_names} <- on_districts_schools do
  d =
    Seeds.find_or_create!(Repo, District, %{
      name: district_name,
      state_id: ca_provinces["Ontario"].id
    })

  for school_name <- school_names do
    Seeds.find_or_create!(Repo, School, %{name: school_name, district_id: d.id})
  end
end

IO.puts("Seeded #{Repo.aggregate(District, :count)} districts")
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
  },
  %{
    name: "Music (Instruments)",
    category: "Music",
    region_relevance: %{"US" => 0.7, "KR" => 0.7, "JP" => 0.7}
  },
  %{
    name: "Photography",
    category: "Art",
    region_relevance: %{"US" => 0.7, "KR" => 0.6, "JP" => 0.7}
  },
  %{
    name: "Fashion",
    category: "Lifestyle",
    region_relevance: %{"US" => 0.6, "KR" => 0.8, "JP" => 0.8}
  },
  %{
    name: "Fitness",
    category: "Sports",
    region_relevance: %{"US" => 0.8, "KR" => 0.6, "JP" => 0.6}
  },
  %{
    name: "Film & Movies",
    category: "Entertainment",
    region_relevance: %{"US" => 0.8, "KR" => 0.7, "JP" => 0.7}
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

# Look up Saratoga High School for linking
saratoga_high =
  Repo.one(from s in School, where: s.name == "Saratoga High School", limit: 1)

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

      school_id = if saratoga_high, do: dump_uuid.(saratoga_high.id), else: nil

      Repo.query!(
        """
        INSERT INTO courses (id, name, subject, grade, school_id, inserted_at, updated_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        """,
        [id, "AP Biology", "AP Biology", "11", school_id, now, now]
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

# ── ISO 3166-2 subdivision codes (required by ingestion pipelines) ────────────

Code.eval_file(Path.join(__DIR__, "seeds_geo_iso.exs"))

IO.puts("\nSeed data loaded successfully!")
