defmodule Mix.Tasks.Funsheep.Admin.Grant do
  @shortdoc "Promote an Interactor user to platform admin"

  @moduledoc """
  Promote an Interactor user to FunSheep platform admin.

  Sets the user's Interactor profile `metadata.role` to `"admin"` (preserving
  any other metadata keys), upserts the local `user_roles` bridge row, and
  writes an audit log entry.

  ## Usage

      mix funsheep.admin.grant --user-id usr_abc123 [--org studysmart]

  The `--org` flag defaults to the value of `:fun_sheep, :interactor_org_name`.

  This task is intended to run at a shell on the production host; it is the
  only supported bootstrap path for the first admin. After one admin exists,
  further grants can be performed via the `/admin/users` UI.
  """
  use Mix.Task

  require Logger

  alias FunSheep.{Accounts, Admin}

  @switches [user_id: :string, org: :string]

  @impl Mix.Task
  def run(argv) do
    {opts, _argv, _invalid} = OptionParser.parse(argv, switches: @switches)

    user_id = Keyword.get(opts, :user_id) || Mix.raise("--user-id is required")
    org = Keyword.get(opts, :org) || default_org()

    Mix.Task.run("app.start")

    {:ok, token} = fetch_app_token()
    profile = fetch_user(org, user_id, token)

    existing_metadata = Map.get(profile, "metadata") || %{}
    new_metadata = Map.put(existing_metadata, "role", "admin")

    :ok = patch_metadata(org, user_id, new_metadata, token)

    {:ok, local} =
      Accounts.create_user_role(%{
        interactor_user_id: user_id,
        role: :admin,
        email: profile["email"] || "#{user_id}@unknown",
        display_name: profile["username"] || user_id
      })
      |> maybe_reuse_existing(user_id)

    {:ok, _} =
      Admin.record(%{
        actor_label: "mix-task:admin.grant",
        action: "user.promote_to_admin",
        target_type: "interactor_user",
        target_id: user_id,
        metadata: %{
          "org" => org,
          "username" => profile["username"],
          "local_user_role_id" => local.id
        }
      })

    Mix.shell().info("Granted admin to #{profile["username"] || user_id} (#{user_id}).")
  end

  defp maybe_reuse_existing({:ok, _} = ok, _user_id), do: ok

  defp maybe_reuse_existing({:error, _changeset}, user_id) do
    case Accounts.get_user_role_by_interactor_id_and_role(user_id, :admin) do
      nil -> {:error, :could_not_create_or_find}
      existing -> {:ok, existing}
    end
  end

  defp fetch_app_token do
    case FunSheep.Interactor.Auth.get_token() do
      {:ok, token} -> {:ok, token}
      {:error, reason} -> Mix.raise("Failed to get Interactor app token: #{inspect(reason)}")
    end
  end

  defp fetch_user(org, user_id, token) do
    url = "#{interactor_url()}/api/v1/orgs/#{org}/users/#{user_id}"

    case Req.get(url, headers: [{"authorization", "Bearer #{token}"}]) do
      {:ok, %{status: 200, body: body}} ->
        body

      {:ok, %{status: 404}} ->
        Mix.raise("User #{user_id} not found in org #{org}")

      {:ok, %{status: status, body: body}} ->
        Mix.raise("Failed to fetch user (#{status}): #{inspect(body)}")

      {:error, reason} ->
        Mix.raise("Interactor request failed: #{inspect(reason)}")
    end
  end

  defp patch_metadata(org, user_id, metadata, token) do
    url = "#{interactor_url()}/api/v1/orgs/#{org}/users/#{user_id}"

    case Req.patch(url,
           headers: [{"authorization", "Bearer #{token}"}],
           json: %{metadata: metadata}
         ) do
      {:ok, %{status: s}} when s in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Mix.raise("Failed to update user metadata (#{status}): #{inspect(body)}")

      {:error, reason} ->
        Mix.raise("Interactor PATCH failed: #{inspect(reason)}")
    end
  end

  defp interactor_url,
    do: Application.get_env(:fun_sheep, :interactor_url, "https://auth.interactor.com")

  defp default_org,
    do: Application.get_env(:fun_sheep, :interactor_org_name, "studysmart")
end
