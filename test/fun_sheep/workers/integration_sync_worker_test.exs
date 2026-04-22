defmodule FunSheep.Workers.IntegrationSyncWorkerTest do
  use FunSheep.DataCase, async: false

  alias FunSheep.Integrations
  alias FunSheep.Integrations.Providers.Fake
  alias FunSheep.Workers.IntegrationSyncWorker
  alias FunSheep.Courses
  alias FunSheep.Assessments

  setup do
    original = Application.get_env(:fun_sheep, :integrations_provider_modules, %{})

    Application.put_env(:fun_sheep, :integrations_provider_modules, %{google_classroom: Fake})

    on_exit(fn ->
      Application.put_env(:fun_sheep, :integrations_provider_modules, original)
      Application.delete_env(:fun_sheep, :fake_provider)
    end)

    {:ok, user_role} =
      FunSheep.Accounts.create_user_role(%{
        interactor_user_id: "worker_interactor_#{System.unique_integer([:positive])}",
        role: :student,
        email: "worker_#{System.unique_integer([:positive])}@test.example",
        display_name: "Worker Student"
      })

    {:ok, connection} =
      Integrations.create_connection(%{
        user_role_id: user_role.id,
        provider: :google_classroom,
        service_id: "google_classroom",
        external_user_id: user_role.interactor_user_id,
        credential_id: "cred_worker"
      })

    %{user_role: user_role, connection: connection}
  end

  test "happy path: creates a course and a test schedule", %{
    user_role: user_role,
    connection: connection
  } do
    Application.put_env(:fun_sheep, :fake_provider, %{
      courses:
        {:ok,
         [
           %{"id" => "c_1", "name" => "Algebra", "subject" => "Math", "grade" => "9"}
         ]},
      assignments: %{
        "c_1" => [
          %{"id" => "a_1", "name" => "Unit Test", "due_at" => Date.utc_today()}
        ]
      }
    })

    :ok = Integrations.subscribe(user_role.id)

    assert :ok =
             perform_job(IntegrationSyncWorker, %{"connection_id" => connection.id})

    courses = Courses.list_courses_for_user(user_role.id)
    assert length(courses) == 1
    [course] = courses
    assert course.name == "Algebra"
    assert course.external_id == "c_1"

    schedules = Assessments.list_test_schedules_for_user(user_role.id)
    assert length(schedules) == 1
    [schedule] = schedules
    assert schedule.name == "Unit Test"
    assert schedule.external_id == "a_1"

    reloaded = Integrations.get_connection(connection.id)
    assert reloaded.status == :active
    assert reloaded.last_sync_at
    assert reloaded.last_sync_error == nil

    assert_receive {:integration_event, :syncing, _}
    assert_receive {:integration_event, :synced, payload}
    assert payload.courses == 1
    assert payload.assignments == 1
  end

  test "honest failure: upstream error marks connection errored and creates no rows", %{
    user_role: user_role,
    connection: connection
  } do
    Application.put_env(:fun_sheep, :fake_provider, %{
      courses: {:error, {503, "upstream unavailable"}}
    })

    assert {:error, _reason} =
             perform_job(IntegrationSyncWorker, %{"connection_id" => connection.id})

    assert Courses.list_courses_for_user(user_role.id) == []
    assert Assessments.list_test_schedules_for_user(user_role.id) == []

    reloaded = Integrations.get_connection(connection.id)
    assert reloaded.status == :error
    assert reloaded.last_sync_error =~ "503"
  end

  test "idempotent: running twice with same data doesn't duplicate rows",
       %{user_role: user_role, connection: connection} do
    Application.put_env(:fun_sheep, :fake_provider, %{
      courses: {:ok, [%{"id" => "c_x", "name" => "Bio", "subject" => "Bio", "grade" => "10"}]},
      assignments: %{"c_x" => []}
    })

    assert :ok = perform_job(IntegrationSyncWorker, %{"connection_id" => connection.id})
    assert :ok = perform_job(IntegrationSyncWorker, %{"connection_id" => connection.id})

    assert length(Courses.list_courses_for_user(user_role.id)) == 1
  end

  defp perform_job(worker, args) do
    args
    |> worker.new()
    |> Oban.insert!()

    # inline mode already executed the job; grab the result from state
    worker_module = worker

    job = %Oban.Job{
      args: args,
      worker: Atom.to_string(worker_module),
      attempt: 1,
      max_attempts: 3
    }

    worker_module.perform(job)
  end
end
