defmodule FunSheep.Discovery.RegistrySeederTest do
  use FunSheep.DataCase, async: false

  import Ecto.Query

  alias FunSheep.{Repo}
  alias FunSheep.ContentFixtures
  alias FunSheep.Discovery.{RegistrySeeder, SourceRegistryEntry}
  alias FunSheep.Content.DiscoveredSource

  defp insert_registry_entry(attrs) do
    defaults = %{
      test_type: "sat",
      catalog_subject: nil,
      url_or_pattern: "https://example.com/#{:erlang.unique_integer([:positive])}",
      domain: "example.com",
      source_type: "practice_test",
      tier: 2
    }

    Repo.insert!(%SourceRegistryEntry{}
    |> SourceRegistryEntry.changeset(Map.merge(defaults, attrs)))
  end

  defp course_fixture(attrs \\ %{}) do
    defaults = %{
      catalog_test_type: "sat",
      catalog_subject: "mathematics",
      access_level: "premium"
    }

    ContentFixtures.create_course(Map.merge(defaults, attrs))
  end

  describe "seed_from_registry/1" do
    test "inserts a DiscoveredSource for each matching registry entry" do
      insert_registry_entry(%{test_type: "sat", catalog_subject: nil, tier: 1})
      insert_registry_entry(%{test_type: "sat", catalog_subject: nil, tier: 2})
      course = course_fixture()

      assert {:ok, 2} = RegistrySeeder.seed_from_registry(course)

      sources =
        from(ds in DiscoveredSource, where: ds.course_id == ^course.id)
        |> Repo.all()

      assert length(sources) == 2
    end

    test "sets discovery_strategy to 'registry' on inserted sources" do
      insert_registry_entry(%{test_type: "sat"})
      course = course_fixture()

      RegistrySeeder.seed_from_registry(course)

      sources =
        from(ds in DiscoveredSource, where: ds.course_id == ^course.id)
        |> Repo.all()

      assert Enum.all?(sources, &(&1.discovery_strategy == "registry"))
    end

    test "includes nil-subject (wildcard) entries for any subject" do
      insert_registry_entry(%{test_type: "sat", catalog_subject: nil})
      insert_registry_entry(%{test_type: "sat", catalog_subject: "mathematics"})
      insert_registry_entry(%{test_type: "sat", catalog_subject: "verbal"})

      # Course with "mathematics" subject should get the nil entry + math entry
      course = course_fixture(%{catalog_subject: "mathematics"})

      assert {:ok, 2} = RegistrySeeder.seed_from_registry(course)
    end

    test "excludes disabled entries" do
      insert_registry_entry(%{test_type: "sat", is_enabled: true})
      insert_registry_entry(%{test_type: "sat", is_enabled: false})
      course = course_fixture()

      assert {:ok, 1} = RegistrySeeder.seed_from_registry(course)
    end

    test "is idempotent — re-seeding the same course returns 0 new insertions" do
      insert_registry_entry(%{test_type: "sat"})
      course = course_fixture()

      assert {:ok, 1} = RegistrySeeder.seed_from_registry(course)
      assert {:ok, 0} = RegistrySeeder.seed_from_registry(course)

      # Still only one source in the DB
      count =
        from(ds in DiscoveredSource, where: ds.course_id == ^course.id)
        |> Repo.aggregate(:count)

      assert count == 1
    end

    test "returns {:ok, 0} when no matching registry entries exist" do
      insert_registry_entry(%{test_type: "act"})
      course = course_fixture(%{catalog_test_type: "sat"})

      assert {:ok, 0} = RegistrySeeder.seed_from_registry(course)
    end

    test "does not seed entries for other test types" do
      insert_registry_entry(%{test_type: "act"})
      insert_registry_entry(%{test_type: "gre"})
      course = course_fixture(%{catalog_test_type: "sat"})

      assert {:ok, 0} = RegistrySeeder.seed_from_registry(course)
    end
  end

  describe "entries_for/2 — MCAT integration scenario" do
    test "seeding an MCAT course creates >= 1 discovered source per registry entry" do
      # Simulate a minimal MCAT registry
      insert_registry_entry(%{
        test_type: "mcat",
        catalog_subject: nil,
        url_or_pattern: "https://students-residents.aamc.org/mcat-prep",
        domain: "aamc.org",
        source_type: "official",
        tier: 1
      })

      insert_registry_entry(%{
        test_type: "mcat",
        catalog_subject: nil,
        url_or_pattern: "https://www.khanacademy.org/test-prep/mcat",
        domain: "khanacademy.org",
        source_type: "question_bank",
        tier: 2
      })

      insert_registry_entry(%{
        test_type: "mcat",
        catalog_subject: nil,
        url_or_pattern: "https://www.magoosh.com/mcat",
        domain: "magoosh.com",
        source_type: "question_bank",
        tier: 2
      })

      course =
        ContentFixtures.create_course(%{
          catalog_test_type: "mcat",
          catalog_subject: nil,
          access_level: "premium"
        })

      assert {:ok, count} = RegistrySeeder.seed_from_registry(course)
      assert count >= 3, "Expected >= 3 MCAT sources, got #{count}"

      sources =
        from(ds in DiscoveredSource,
          where: ds.course_id == ^course.id and ds.discovery_strategy == "registry"
        )
        |> Repo.all()

      assert length(sources) >= 3
    end
  end

  describe "entries_for/2" do
    test "returns enabled entries matching test_type" do
      insert_registry_entry(%{test_type: "sat", is_enabled: true})
      insert_registry_entry(%{test_type: "sat", is_enabled: false})
      insert_registry_entry(%{test_type: "act", is_enabled: true})

      entries = RegistrySeeder.entries_for("sat")
      assert length(entries) == 1
      assert hd(entries).test_type == "sat"
    end

    test "orders entries by tier ascending" do
      insert_registry_entry(%{test_type: "gre", tier: 3})
      insert_registry_entry(%{test_type: "gre", tier: 1})
      insert_registry_entry(%{test_type: "gre", tier: 2})

      entries = RegistrySeeder.entries_for("gre")
      tiers = Enum.map(entries, & &1.tier)
      assert tiers == Enum.sort(tiers)
    end
  end
end
