# Populate ISO 3166-2 subdivision codes on states for every country we'll
# ingest schools for. The ingestion pipelines (NCES, NEIS, GIAS, ACARA,
# Canada provincial) all look up states by `iso_code`, so this seed MUST
# run before any `mix funsheep.ingest.run ...`.
#
# Idempotent: upserts states by (country_id, iso_code) so re-running is safe.
# Existing states that only have `name` populated (from the original seed)
# are backfilled with their iso_code.

alias FunSheep.Repo
alias FunSheep.Geo.{Country, State}
import Ecto.Query

defmodule GeoIsoSeeds do
  def upsert!(repo, country_id, entries) do
    for %{iso: iso, name: name} = entry <- entries do
      attrs = %{
        country_id: country_id,
        name: name,
        iso_code: iso,
        native_name: Map.get(entry, :native),
        subdivision_type: Map.get(entry, :type)
      }

      case repo.one(from s in State, where: s.iso_code == ^iso, limit: 1) do
        nil ->
          case repo.one(
                 from s in State,
                   where: s.country_id == ^country_id and s.name == ^name,
                   limit: 1
               ) do
            nil ->
              %State{}
              |> State.changeset(attrs)
              |> repo.insert!()

            existing ->
              existing
              |> State.changeset(attrs)
              |> repo.update!()
          end

        existing ->
          existing
          |> State.changeset(attrs)
          |> repo.update!()
      end
    end

    length(entries)
  end
end

countries =
  Repo.all(Country)
  |> Map.new(fn c -> {c.code, c.id} end)

# ── United States: 50 states + DC + 5 territories ──────────────────────────

us_entries = [
  %{iso: "US-AL", name: "Alabama", type: "State"},
  %{iso: "US-AK", name: "Alaska", type: "State"},
  %{iso: "US-AZ", name: "Arizona", type: "State"},
  %{iso: "US-AR", name: "Arkansas", type: "State"},
  %{iso: "US-CA", name: "California", type: "State"},
  %{iso: "US-CO", name: "Colorado", type: "State"},
  %{iso: "US-CT", name: "Connecticut", type: "State"},
  %{iso: "US-DE", name: "Delaware", type: "State"},
  %{iso: "US-DC", name: "District of Columbia", type: "District"},
  %{iso: "US-FL", name: "Florida", type: "State"},
  %{iso: "US-GA", name: "Georgia", type: "State"},
  %{iso: "US-HI", name: "Hawaii", type: "State"},
  %{iso: "US-ID", name: "Idaho", type: "State"},
  %{iso: "US-IL", name: "Illinois", type: "State"},
  %{iso: "US-IN", name: "Indiana", type: "State"},
  %{iso: "US-IA", name: "Iowa", type: "State"},
  %{iso: "US-KS", name: "Kansas", type: "State"},
  %{iso: "US-KY", name: "Kentucky", type: "State"},
  %{iso: "US-LA", name: "Louisiana", type: "State"},
  %{iso: "US-ME", name: "Maine", type: "State"},
  %{iso: "US-MD", name: "Maryland", type: "State"},
  %{iso: "US-MA", name: "Massachusetts", type: "State"},
  %{iso: "US-MI", name: "Michigan", type: "State"},
  %{iso: "US-MN", name: "Minnesota", type: "State"},
  %{iso: "US-MS", name: "Mississippi", type: "State"},
  %{iso: "US-MO", name: "Missouri", type: "State"},
  %{iso: "US-MT", name: "Montana", type: "State"},
  %{iso: "US-NE", name: "Nebraska", type: "State"},
  %{iso: "US-NV", name: "Nevada", type: "State"},
  %{iso: "US-NH", name: "New Hampshire", type: "State"},
  %{iso: "US-NJ", name: "New Jersey", type: "State"},
  %{iso: "US-NM", name: "New Mexico", type: "State"},
  %{iso: "US-NY", name: "New York", type: "State"},
  %{iso: "US-NC", name: "North Carolina", type: "State"},
  %{iso: "US-ND", name: "North Dakota", type: "State"},
  %{iso: "US-OH", name: "Ohio", type: "State"},
  %{iso: "US-OK", name: "Oklahoma", type: "State"},
  %{iso: "US-OR", name: "Oregon", type: "State"},
  %{iso: "US-PA", name: "Pennsylvania", type: "State"},
  %{iso: "US-RI", name: "Rhode Island", type: "State"},
  %{iso: "US-SC", name: "South Carolina", type: "State"},
  %{iso: "US-SD", name: "South Dakota", type: "State"},
  %{iso: "US-TN", name: "Tennessee", type: "State"},
  %{iso: "US-TX", name: "Texas", type: "State"},
  %{iso: "US-UT", name: "Utah", type: "State"},
  %{iso: "US-VT", name: "Vermont", type: "State"},
  %{iso: "US-VA", name: "Virginia", type: "State"},
  %{iso: "US-WA", name: "Washington", type: "State"},
  %{iso: "US-WV", name: "West Virginia", type: "State"},
  %{iso: "US-WI", name: "Wisconsin", type: "State"},
  %{iso: "US-WY", name: "Wyoming", type: "State"},
  # Territories (schools ingested from NCES include these)
  %{iso: "US-AS", name: "American Samoa", type: "Territory"},
  %{iso: "US-GU", name: "Guam", type: "Territory"},
  %{iso: "US-MP", name: "Northern Mariana Islands", type: "Territory"},
  %{iso: "US-PR", name: "Puerto Rico", type: "Territory"},
  %{iso: "US-VI", name: "U.S. Virgin Islands", type: "Territory"},
  %{iso: "US-BI", name: "Bureau of Indian Education", type: "Federal"}
]

# ── South Korea: 17 시도 per ISO 3166-2 ──────────────────────────────────────

kr_entries = [
  %{iso: "KR-11", name: "Seoul", native: "서울특별시", type: "Special City"},
  %{iso: "KR-26", name: "Busan", native: "부산광역시", type: "Metropolitan City"},
  %{iso: "KR-27", name: "Daegu", native: "대구광역시", type: "Metropolitan City"},
  %{iso: "KR-28", name: "Incheon", native: "인천광역시", type: "Metropolitan City"},
  %{iso: "KR-29", name: "Gwangju", native: "광주광역시", type: "Metropolitan City"},
  %{iso: "KR-30", name: "Daejeon", native: "대전광역시", type: "Metropolitan City"},
  %{iso: "KR-31", name: "Ulsan", native: "울산광역시", type: "Metropolitan City"},
  %{iso: "KR-50", name: "Sejong", native: "세종특별자치시", type: "Special Self-Governing City"},
  %{iso: "KR-41", name: "Gyeonggi", native: "경기도", type: "Province"},
  %{iso: "KR-42", name: "Gangwon", native: "강원특별자치도", type: "Special Self-Governing Province"},
  %{iso: "KR-43", name: "North Chungcheong", native: "충청북도", type: "Province"},
  %{iso: "KR-44", name: "South Chungcheong", native: "충청남도", type: "Province"},
  %{iso: "KR-45", name: "North Jeolla", native: "전북특별자치도", type: "Special Self-Governing Province"},
  %{iso: "KR-46", name: "South Jeolla", native: "전라남도", type: "Province"},
  %{iso: "KR-47", name: "North Gyeongsang", native: "경상북도", type: "Province"},
  %{iso: "KR-48", name: "South Gyeongsang", native: "경상남도", type: "Province"},
  %{iso: "KR-49", name: "Jeju", native: "제주특별자치도", type: "Special Self-Governing Province"}
]

# ── Canada: 10 provinces + 3 territories ─────────────────────────────────────

ca_entries = [
  %{iso: "CA-AB", name: "Alberta", type: "Province"},
  %{iso: "CA-BC", name: "British Columbia", type: "Province"},
  %{iso: "CA-MB", name: "Manitoba", type: "Province"},
  %{iso: "CA-NB", name: "New Brunswick", type: "Province"},
  %{iso: "CA-NL", name: "Newfoundland and Labrador", type: "Province"},
  %{iso: "CA-NS", name: "Nova Scotia", type: "Province"},
  %{iso: "CA-ON", name: "Ontario", type: "Province"},
  %{iso: "CA-PE", name: "Prince Edward Island", type: "Province"},
  %{iso: "CA-QC", name: "Quebec", type: "Province"},
  %{iso: "CA-SK", name: "Saskatchewan", type: "Province"},
  %{iso: "CA-NT", name: "Northwest Territories", type: "Territory"},
  %{iso: "CA-NU", name: "Nunavut", type: "Territory"},
  %{iso: "CA-YT", name: "Yukon", type: "Territory"}
]

# ── United Kingdom: 4 countries + regions ────────────────────────────────────

gb_entries = [
  %{iso: "GB-ENG", name: "England", type: "Country"},
  %{iso: "GB-SCT", name: "Scotland", type: "Country"},
  %{iso: "GB-WLS", name: "Wales", type: "Country"},
  %{iso: "GB-NIR", name: "Northern Ireland", type: "Country"}
]

# ── Australia: 6 states + 2 territories ──────────────────────────────────────

au_entries = [
  %{iso: "AU-NSW", name: "New South Wales", type: "State"},
  %{iso: "AU-VIC", name: "Victoria", type: "State"},
  %{iso: "AU-QLD", name: "Queensland", type: "State"},
  %{iso: "AU-SA", name: "South Australia", type: "State"},
  %{iso: "AU-WA", name: "Western Australia", type: "State"},
  %{iso: "AU-TAS", name: "Tasmania", type: "State"},
  %{iso: "AU-NT", name: "Northern Territory", type: "Territory"},
  %{iso: "AU-ACT", name: "Australian Capital Territory", type: "Territory"}
]

# ── Japan: 47 prefectures ────────────────────────────────────────────────────

jp_entries = [
  %{iso: "JP-01", name: "Hokkaido", native: "北海道"},
  %{iso: "JP-02", name: "Aomori", native: "青森県"},
  %{iso: "JP-03", name: "Iwate", native: "岩手県"},
  %{iso: "JP-04", name: "Miyagi", native: "宮城県"},
  %{iso: "JP-05", name: "Akita", native: "秋田県"},
  %{iso: "JP-06", name: "Yamagata", native: "山形県"},
  %{iso: "JP-07", name: "Fukushima", native: "福島県"},
  %{iso: "JP-08", name: "Ibaraki", native: "茨城県"},
  %{iso: "JP-09", name: "Tochigi", native: "栃木県"},
  %{iso: "JP-10", name: "Gunma", native: "群馬県"},
  %{iso: "JP-11", name: "Saitama", native: "埼玉県"},
  %{iso: "JP-12", name: "Chiba", native: "千葉県"},
  %{iso: "JP-13", name: "Tokyo", native: "東京都"},
  %{iso: "JP-14", name: "Kanagawa", native: "神奈川県"},
  %{iso: "JP-15", name: "Niigata", native: "新潟県"},
  %{iso: "JP-16", name: "Toyama", native: "富山県"},
  %{iso: "JP-17", name: "Ishikawa", native: "石川県"},
  %{iso: "JP-18", name: "Fukui", native: "福井県"},
  %{iso: "JP-19", name: "Yamanashi", native: "山梨県"},
  %{iso: "JP-20", name: "Nagano", native: "長野県"},
  %{iso: "JP-21", name: "Gifu", native: "岐阜県"},
  %{iso: "JP-22", name: "Shizuoka", native: "静岡県"},
  %{iso: "JP-23", name: "Aichi", native: "愛知県"},
  %{iso: "JP-24", name: "Mie", native: "三重県"},
  %{iso: "JP-25", name: "Shiga", native: "滋賀県"},
  %{iso: "JP-26", name: "Kyoto", native: "京都府"},
  %{iso: "JP-27", name: "Osaka", native: "大阪府"},
  %{iso: "JP-28", name: "Hyogo", native: "兵庫県"},
  %{iso: "JP-29", name: "Nara", native: "奈良県"},
  %{iso: "JP-30", name: "Wakayama", native: "和歌山県"},
  %{iso: "JP-31", name: "Tottori", native: "鳥取県"},
  %{iso: "JP-32", name: "Shimane", native: "島根県"},
  %{iso: "JP-33", name: "Okayama", native: "岡山県"},
  %{iso: "JP-34", name: "Hiroshima", native: "広島県"},
  %{iso: "JP-35", name: "Yamaguchi", native: "山口県"},
  %{iso: "JP-36", name: "Tokushima", native: "徳島県"},
  %{iso: "JP-37", name: "Kagawa", native: "香川県"},
  %{iso: "JP-38", name: "Ehime", native: "愛媛県"},
  %{iso: "JP-39", name: "Kochi", native: "高知県"},
  %{iso: "JP-40", name: "Fukuoka", native: "福岡県"},
  %{iso: "JP-41", name: "Saga", native: "佐賀県"},
  %{iso: "JP-42", name: "Nagasaki", native: "長崎県"},
  %{iso: "JP-43", name: "Kumamoto", native: "熊本県"},
  %{iso: "JP-44", name: "Oita", native: "大分県"},
  %{iso: "JP-45", name: "Miyazaki", native: "宮崎県"},
  %{iso: "JP-46", name: "Kagoshima", native: "鹿児島県"},
  %{iso: "JP-47", name: "Okinawa", native: "沖縄県"}
]

seed_sets = [
  {"US", us_entries},
  {"KR", kr_entries},
  {"CA", ca_entries},
  {"GB", gb_entries},
  {"AU", au_entries},
  {"JP", jp_entries}
]

for {code, entries} <- seed_sets do
  case Map.get(countries, code) do
    nil ->
      IO.puts("Skipping #{code}: country not seeded")

    country_id ->
      count = GeoIsoSeeds.upsert!(Repo, country_id, entries)
      IO.puts("Seeded #{count} ISO states for #{code}")
  end
end

IO.puts("\nGeo ISO seeds loaded.")
