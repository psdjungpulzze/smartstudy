defmodule FunSheep.Ingest.Sources.NcesCcdTest do
  use FunSheep.DataCase, async: false

  alias FunSheep.Geo.{District, School}
  alias FunSheep.Ingest.Cache
  alias FunSheep.Ingest.Sources.NcesCcd
  alias FunSheep.IngestFixtures

  setup do
    # Point cache root at a tmp dir so ensure_local/1 finds our fixtures
    # and the ingester skips the HTTP download.
    tmp_root = Path.join(System.tmp_dir!(), "fs_cache_#{System.unique_integer([:positive])}")
    Application.put_env(:fun_sheep, FunSheep.Ingest.Cache, root: tmp_root)

    on_exit(fn ->
      Application.delete_env(:fun_sheep, FunSheep.Ingest.Cache)
      File.rm_rf!(tmp_root)
    end)

    IngestFixtures.seed_us()
    {:ok, tmp_root: tmp_root}
  end

  describe "run('lea', ...)" do
    test "ingests districts from a CCD-shaped CSV", %{tmp_root: tmp_root} do
      lea_csv = """
      LEAID,LEA_NAME,STABR,ST,LEA_TYPE_TEXT,SY_STATUS_TEXT,LSTREET1,LCITY,LSTATE,LZIP,PHONE,WEBSITE
      0622710,Saratoga Union Elementary School District,CA,CA,Regular local school district,Open,20460 Forrest Hills Dr,Saratoga,CA,95070,408-867-3424,http://www.saratogausd.org
      0630930,Palo Alto Unified School District,CA,CA,Regular local school district,Open,25 Churchill Ave,Palo Alto,CA,94306,650-329-3700,http://pausd.org
      """

      # Seed both the pre-extracted CSV and the "zip" entry (NcesCcd's
      # extract_first_csv short-circuits when the CSV cache already exists)
      key = Cache.build_key("nces_ccd", "ccd_lea.csv")
      local = Path.join(tmp_root, key)
      File.mkdir_p!(Path.dirname(local))
      File.write!(local, lea_csv)

      zip_key = Cache.build_key("nces_ccd", "ccd_lea.zip")
      zip_local = Path.join(tmp_root, zip_key)
      File.mkdir_p!(Path.dirname(zip_local))
      # Minimal placeholder so ensure_local returns a path
      File.write!(zip_local, "placeholder")

      assert {:ok, stats} = NcesCcd.run("lea")
      assert stats.inserted == 2

      districts = Repo.all(District) |> Enum.sort_by(& &1.nces_leaid)
      assert length(districts) == 2

      [saratoga, palo_alto] = districts
      assert saratoga.nces_leaid == "0622710"
      assert saratoga.source == "nces_ccd"
      assert saratoga.source_id == "0622710"
      assert saratoga.name =~ "Saratoga"
      assert saratoga.operational_status == "open"
      assert saratoga.city == "Saratoga"
      assert palo_alto.postal_code == "94306"
    end

    test "re-ingesting updates, doesn't duplicate", %{tmp_root: tmp_root} do
      lea_csv = """
      LEAID,LEA_NAME,STABR,SY_STATUS_TEXT,LCITY,LZIP
      0622710,Saratoga USD,CA,Open,Saratoga,95070
      """

      write_fixture(tmp_root, "ccd_lea.csv", lea_csv)
      write_fixture(tmp_root, "ccd_lea.zip", "placeholder")

      {:ok, _} = NcesCcd.run("lea")
      assert Repo.aggregate(District, :count) == 1
      original = Repo.one(District)

      # Registry renames the LEA; re-ingest
      updated_csv =
        String.replace(lea_csv, "Saratoga USD", "Saratoga Union School District")

      write_fixture(tmp_root, "ccd_lea.csv", updated_csv)

      {:ok, _} = NcesCcd.run("lea")

      assert Repo.aggregate(District, :count) == 1
      refreshed = Repo.one(District)
      assert refreshed.id == original.id, "PK must stay stable across upsert"
      assert refreshed.name == "Saratoga Union School District"
    end
  end

  describe "run('school', ...)" do
    test "ingests schools and links them to their district", %{tmp_root: tmp_root} do
      lea_csv = """
      LEAID,LEA_NAME,STABR,SY_STATUS_TEXT,LCITY,LZIP
      0622710,Saratoga USD,CA,Open,Saratoga,95070
      """

      school_csv = """
      NCESSCH,LEAID,SCH_NAME,STABR,SCH_TYPE_TEXT,SY_STATUS_TEXT,LEVEL,GSLO,GSHI,LSTREET1,LCITY,LZIP,LATCOD,LONCOD,LOCALE,CHARTER_TEXT,MAGNET_TEXT,TITLEI_STATUS_TEXT
      062271000001,0622710,Saratoga High School,CA,Regular School,Open,High,9,12,20300 Herriman Ave,Saratoga,95070,37.2564,-122.0324,21,No,No,Not a Title I School
      062271000002,0622710,Redwood Middle School,CA,Regular School,Open,Middle,6,8,13925 Fruitvale Ave,Saratoga,95070,37.2621,-122.0296,21,No,No,Not a Title I School
      """

      write_fixture(tmp_root, "ccd_lea.csv", lea_csv)
      write_fixture(tmp_root, "ccd_lea.zip", "placeholder")
      write_fixture(tmp_root, "ccd_school.csv", school_csv)
      write_fixture(tmp_root, "ccd_school.zip", "placeholder")

      {:ok, _} = NcesCcd.run("lea")
      {:ok, stats} = NcesCcd.run("school")

      assert stats.inserted == 2
      schools = Repo.all(School) |> Enum.sort_by(& &1.nces_id)
      assert length(schools) == 2

      [saratoga, redwood] = schools
      assert saratoga.nces_id == "062271000001"
      assert saratoga.source == "nces_ccd"
      assert saratoga.level == "high"
      assert saratoga.lowest_grade == "9"
      assert saratoga.highest_grade == "12"
      assert saratoga.lat == 37.2564
      assert saratoga.lng == -122.0324
      assert saratoga.locale_code == "21"
      assert saratoga.district_id != nil

      assert redwood.level == "middle"
    end

    test "marks charter schools as charter type", %{tmp_root: tmp_root} do
      school_csv = """
      NCESSCH,LEAID,SCH_NAME,STABR,SCH_TYPE_TEXT,SY_STATUS_TEXT,LEVEL,GSLO,GSHI,CHARTER_TEXT,MAGNET_TEXT
      062271000099,0622710,Charter Example,CA,Regular School,Open,High,9,12,Yes,No
      """

      write_fixture(tmp_root, "ccd_school.csv", school_csv)
      write_fixture(tmp_root, "ccd_school.zip", "placeholder")

      {:ok, _} = NcesCcd.run("school")
      [school] = Repo.all(School)
      assert school.type == "charter"
    end
  end

  defp write_fixture(root, filename, content) do
    key = FunSheep.Ingest.Cache.build_key("nces_ccd", filename)
    path = Path.join(root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    path
  end
end
