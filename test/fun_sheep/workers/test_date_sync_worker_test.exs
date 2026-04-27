defmodule FunSheep.Workers.TestDateSyncWorkerTest do
  use FunSheep.DataCase, async: true

  alias FunSheep.Workers.TestDateSyncWorker
  alias FunSheep.Courses
  alias FunSheep.Repo
  alias FunSheep.Courses.KnownTestDate

  describe "perform/1 with missing API key" do
    test "returns error when ANTHROPIC_API_KEY is not set" do
      System.delete_env("ANTHROPIC_API_KEY")
      job = %Oban.Job{args: %{"test_type" => "sat"}}
      assert {:error, :missing_api_key} = TestDateSyncWorker.perform(job)
    end
  end

  describe "upsert via Courses.upsert_known_test_date/1" do
    test "inserts a new known test date" do
      attrs = %{
        test_type: "sat",
        test_name: "SAT October 2025",
        test_date: ~D[2025-10-04],
        registration_deadline: ~D[2025-09-19],
        region: "us",
        last_synced_at: DateTime.utc_now()
      }

      assert {:ok, record} = Courses.upsert_known_test_date(attrs)
      assert record.test_type == "sat"
      assert record.test_name == "SAT October 2025"
      assert record.test_date == ~D[2025-10-04]
    end

    test "updates an existing record on conflict (test_type + test_date + region)" do
      attrs = %{
        test_type: "sat",
        test_name: "SAT October 2025",
        test_date: ~D[2025-10-04],
        region: "us",
        last_synced_at: DateTime.utc_now()
      }

      {:ok, first} = Courses.upsert_known_test_date(attrs)
      {:ok, _second} = Courses.upsert_known_test_date(%{attrs | test_name: "SAT October 2025 (Updated)"})

      all = Repo.all(KnownTestDate)
      assert length(all) == 1
      assert hd(all).id == first.id
      assert hd(all).test_name == "SAT October 2025 (Updated)"
    end

    test "rejects invalid test_type" do
      attrs = %{
        test_type: "unknown_test",
        test_name: "Fake Test",
        test_date: ~D[2025-10-04],
        region: "us"
      }

      assert {:error, changeset} = Courses.upsert_known_test_date(attrs)
      assert errors_on(changeset) |> Map.has_key?(:test_type)
    end
  end

  describe "list_upcoming_known_dates/2" do
    test "returns only future dates for the given test type" do
      today = Date.utc_today()

      {:ok, _past} =
        Courses.upsert_known_test_date(%{
          test_type: "sat",
          test_name: "Past SAT",
          test_date: Date.add(today, -30),
          region: "us"
        })

      {:ok, _future} =
        Courses.upsert_known_test_date(%{
          test_type: "sat",
          test_name: "Future SAT",
          test_date: Date.add(today, 30),
          region: "us"
        })

      upcoming = Courses.list_upcoming_known_dates("sat")
      assert length(upcoming) == 1
      assert hd(upcoming).test_name == "Future SAT"
    end

    test "filters by region" do
      today = Date.utc_today()

      Courses.upsert_known_test_date(%{
        test_type: "sat",
        test_name: "SAT US",
        test_date: Date.add(today, 10),
        region: "us"
      })

      Courses.upsert_known_test_date(%{
        test_type: "sat",
        test_name: "SAT AU",
        test_date: Date.add(today, 10),
        region: "au"
      })

      us_dates = Courses.list_upcoming_known_dates("sat", "us")
      assert length(us_dates) == 1
      assert hd(us_dates).region == "us"
    end

    test "returns empty for test type with no dates" do
      assert Courses.list_upcoming_known_dates("mcat") == []
    end
  end
end
