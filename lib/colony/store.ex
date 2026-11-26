defmodule Colony.Store do
  @moduledoc """
  The save file. It is one file with one Erlang term.
  """

  require Logger

  @doc "The path of the save file from the game config."
  def path(cfg), do: Path.expand(Keyword.fetch!(cfg, :save_file))

  @doc "Writes the term. The write goes to a second file first, thus a stop in the middle does not break the save file."
  def save(path, term) do
    File.mkdir_p!(Path.dirname(path))
    temporary = path <> ".tmp"
    File.write!(temporary, :erlang.term_to_binary(term, [:compressed]))
    File.rename!(temporary, path)
    :ok
  end

  @doc "Reads the term. Returns `{:ok, term}` or `:none`."
  def load(path) do
    with {:ok, binary} <- File.read(path),
         {:ok, term} <- decode(binary) do
      {:ok, term}
    else
      {:error, :enoent} ->
        :none

      error ->
        Logger.warning("Cannot read the save file #{path}: #{inspect(error)}. A new world starts.")
        :none
    end
  end

  @doc "Deletes the save file."
  def reset(path) do
    case File.rm(path) do
      :ok -> :deleted
      {:error, :enoent} -> :none
    end
  end

  defp decode(binary) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  rescue
    ArgumentError -> {:error, :bad_file}
  end
end
