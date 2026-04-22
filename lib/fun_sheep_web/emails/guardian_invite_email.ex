defmodule FunSheepWeb.Emails.GuardianInviteEmail do
  @moduledoc """
  Renders the "a student has invited you to join their FunSheep
  learning team" email.

  Sent when a student enters the email of a grown-up who does not yet
  have a FunSheep account. The email contains a single-use claim link
  (`/guardian-invite/:token`) that completes the link after sign-up.
  """

  import Swoosh.Email

  alias FunSheep.Accounts.StudentGuardian
  alias FunSheep.Repo

  @from_name "FunSheep"
  @from_email "noreply@funsheep.com"

  @doc """
  Builds a Swoosh `%Email{}` for the given student_guardian.

  Preloads the student if necessary. Returns `{:error, reason}` when
  the row is not in an emailable state.
  """
  def build(%StudentGuardian{} = sg) do
    sg = Repo.preload(sg, :student)

    cond do
      is_nil(sg.invited_email) or sg.invited_email == "" ->
        {:error, :no_invited_email}

      is_nil(sg.invite_token) ->
        {:error, :no_invite_token}

      is_nil(sg.student) ->
        {:error, :no_student}

      true ->
        {:ok, render(sg)}
    end
  end

  defp render(%StudentGuardian{} = sg) do
    student_name = sg.student.display_name || "A FunSheep student"
    claim_url = FunSheepWeb.Endpoint.url() <> "/guardian-invite/#{sg.invite_token}"

    relationship_word =
      case sg.relationship_type do
        :parent -> "parent"
        :teacher -> "teacher"
      end

    new()
    |> to(sg.invited_email)
    |> from({@from_name, @from_email})
    |> subject("#{student_name} invited you to join their FunSheep learning team")
    |> text_body(text_body(student_name, relationship_word, claim_url))
    |> html_body(html_body(student_name, relationship_word, claim_url))
  end

  defp text_body(student_name, relationship_word, claim_url) do
    """
    Hi!

    #{student_name} invited you to be their #{relationship_word} on FunSheep —
    a personalised practice app that helps students master their weak topics.

    Accepting the invite lets you see their progress, unlock unlimited
    practice, and cheer them on.

    Accept the invite here (valid for 14 days):
    #{claim_url}

    If you weren't expecting this, you can safely ignore the email.

    — The FunSheep team
    """
  end

  defp html_body(student_name, relationship_word, claim_url) do
    """
    <!DOCTYPE html>
    <html>
      <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; color: #1C1C1E; background: #F5F5F7; margin: 0; padding: 24px;">
        <div style="max-width: 560px; margin: 0 auto; background: #FFFFFF; border-radius: 16px; padding: 32px; box-shadow: 0 2px 8px rgba(0,0,0,0.04);">
          <h1 style="font-size: 20px; font-weight: 600; margin: 0 0 16px;">
            #{Phoenix.HTML.html_escape(student_name) |> Phoenix.HTML.safe_to_string()} invited you to FunSheep
          </h1>
          <p style="font-size: 16px; line-height: 1.5; margin: 0 0 16px;">
            They asked you to be their <strong>#{relationship_word}</strong> — a
            grown-up who can follow their progress and unlock unlimited practice.
          </p>
          <p style="font-size: 16px; line-height: 1.5; margin: 0 0 24px;">
            Tap the button below to accept. The link is valid for 14 days.
          </p>
          <p style="text-align: center; margin: 0 0 24px;">
            <a href="#{claim_url}" style="background: #4CD964; color: #FFFFFF; font-weight: 500; text-decoration: none; padding: 12px 24px; border-radius: 9999px; display: inline-block;">
              Accept invitation
            </a>
          </p>
          <p style="font-size: 12px; color: #8E8E93; line-height: 1.5; margin: 0;">
            If the button doesn't work, paste this link into your browser:<br/>
            <a href="#{claim_url}" style="color: #007AFF;">#{claim_url}</a>
          </p>
          <p style="font-size: 12px; color: #8E8E93; line-height: 1.5; margin: 24px 0 0;">
            Weren't expecting this? You can safely ignore the email.
          </p>
        </div>
      </body>
    </html>
    """
  end
end
