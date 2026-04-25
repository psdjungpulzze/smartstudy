defmodule FunSheep.Workers.CreditMaterialUploadWorker do
  @moduledoc """
  Awards 2 quarter-units to a teacher when their uploaded material completes OCR.

  Idempotent — uses the uploaded_material id as source_ref_id.
  Only awards credits to users with the :teacher role.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias FunSheep.{Accounts, Content, Credits}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"uploaded_material_id" => material_id}}) do
    material = Content.get_uploaded_material!(material_id)
    uploader = Accounts.get_user_role!(material.user_role_id)

    if uploader.role == :teacher do
      case Credits.award_credit(uploader.id, "material_upload", 2, material_id, %{}) do
        {:ok, _} -> :ok
        {:error, :already_awarded} -> :ok
        error -> error
      end
    else
      :ok
    end
  end
end
