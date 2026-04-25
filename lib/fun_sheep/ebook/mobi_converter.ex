defmodule FunSheep.Ebook.MobiConverter do
  @moduledoc """
  Converts MOBI and AZW3 files to EPUB format using the calibre `ebook-convert` CLI.

  calibre is an open-source ebook management tool that handles the PalmDB binary
  format used by MOBI/AZW3 files. It must be installed in the Docker image or on
  the host system for conversions to succeed.

  DRM-protected files are detected from calibre's error output and returned as
  `{:error, :drm_protected}` rather than a generic failure.

  ## Calibre installation

  Add to Dockerfile:
  ```dockerfile
  RUN apt-get install -y calibre
  ```

  calibre installs `ebook-convert` at `/usr/bin/ebook-convert`.
  """

  require Logger

  @doc """
  Converts a MOBI or AZW3 file at `input_path` to EPUB, writing the result
  into `output_dir/converted.epub`.

  Returns `{:ok, epub_path}` on success, or `{:error, reason}` on failure.

  Reasons:
  - `:calibre_not_found`      — `ebook-convert` is not on PATH
  - `:drm_protected`          — calibre detected DRM encryption
  - `{:calibre_error, code, output}` — calibre exited with a non-zero status
  """
  @spec convert(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :calibre_not_found | :drm_protected | term()}
  def convert(input_path, output_dir) do
    output_path = Path.join(output_dir, "converted.epub")

    case System.find_executable("ebook-convert") do
      nil ->
        Logger.warning(
          "[MobiConverter] ebook-convert not found on PATH — calibre is not installed"
        )

        {:error, :calibre_not_found}

      exe ->
        Logger.info("[MobiConverter] Converting #{input_path} → #{output_path}")

        case System.cmd(
               exe,
               [input_path, output_path, "--output-profile=tablet"],
               stderr_to_stdout: true,
               timeout: 120_000
             ) do
          {_output, 0} ->
            Logger.info("[MobiConverter] Conversion succeeded: #{output_path}")
            {:ok, output_path}

          {output, _code} when is_binary(output) ->
            if output =~ "DRM" or output =~ "encrypted" do
              Logger.warning("[MobiConverter] DRM detected in #{input_path}")
              {:error, :drm_protected}
            else
              Logger.error(
                "[MobiConverter] calibre failed for #{input_path}: #{String.slice(output, 0, 500)}"
              )

              {:error, {:calibre_error, 1, output}}
            end

          {output, code} ->
            Logger.error(
              "[MobiConverter] calibre exited #{code} for #{input_path}: #{String.slice(output, 0, 500)}"
            )

            {:error, {:calibre_error, code, output}}
        end
    end
  end

  @doc """
  Returns `true` if calibre's `ebook-convert` executable is available on PATH.
  """
  @spec calibre_available?() :: boolean()
  def calibre_available? do
    System.find_executable("ebook-convert") != nil
  end
end
