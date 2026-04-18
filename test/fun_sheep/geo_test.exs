defmodule FunSheep.GeoTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Geo

  describe "countries" do
    test "list_countries/0 returns all countries" do
      {:ok, country} = Geo.create_country(%{name: "Test Country", code: "TC"})
      countries = Geo.list_countries()
      assert Enum.any?(countries, fn c -> c.id == country.id end)
    end
  end

  describe "states" do
    test "list_states_by_country/1 returns states for given country" do
      {:ok, country} = Geo.create_country(%{name: "Test Country", code: "TC"})
      {:ok, state} = Geo.create_state(%{name: "Test State", country_id: country.id})

      {:ok, other_country} = Geo.create_country(%{name: "Other Country", code: "OC"})
      {:ok, _other_state} = Geo.create_state(%{name: "Other State", country_id: other_country.id})

      states = Geo.list_states_by_country(country.id)
      assert length(states) == 1
      assert hd(states).id == state.id
    end

    test "list_states_by_country/1 returns empty list for country with no states" do
      {:ok, country} = Geo.create_country(%{name: "Empty Country", code: "EC"})
      assert Geo.list_states_by_country(country.id) == []
    end
  end

  describe "districts" do
    test "list_districts_by_state/1 returns districts for given state" do
      {:ok, country} = Geo.create_country(%{name: "Test Country", code: "TC"})
      {:ok, state} = Geo.create_state(%{name: "Test State", country_id: country.id})
      {:ok, district} = Geo.create_district(%{name: "Test District", state_id: state.id})

      {:ok, other_state} = Geo.create_state(%{name: "Other State", country_id: country.id})

      {:ok, _other_district} =
        Geo.create_district(%{name: "Other District", state_id: other_state.id})

      districts = Geo.list_districts_by_state(state.id)
      assert length(districts) == 1
      assert hd(districts).id == district.id
    end
  end

  describe "schools" do
    test "list_schools_by_district/1 returns schools for given district" do
      {:ok, country} = Geo.create_country(%{name: "Test Country", code: "TC"})
      {:ok, state} = Geo.create_state(%{name: "Test State", country_id: country.id})
      {:ok, district} = Geo.create_district(%{name: "Test District", state_id: state.id})
      {:ok, school} = Geo.create_school(%{name: "Test School", district_id: district.id})

      schools = Geo.list_schools_by_district(district.id)
      assert length(schools) == 1
      assert hd(schools).id == school.id
    end

    test "list_schools_by_district/1 returns empty for district with no schools" do
      {:ok, country} = Geo.create_country(%{name: "Test Country", code: "TC"})
      {:ok, state} = Geo.create_state(%{name: "Test State", country_id: country.id})
      {:ok, district} = Geo.create_district(%{name: "Empty District", state_id: state.id})

      assert Geo.list_schools_by_district(district.id) == []
    end
  end
end
