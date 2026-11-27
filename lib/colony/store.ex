defmodule Colony.Store do
  @moduledoc """
  The save file. It is one file with one Erlang term.
  """

  require Logger

  # The file reader accepts only atoms that the VM knows. In development the VM loads a
  # module at its first use, and the reader runs before the world module is used. This
  # list makes sure that the VM knows all the atoms of a save file when it reads one.
  @atoms [
    # The world.
    :version,
    :seed,
    :start,
    :locked,
    :lock_count,
    :scent,
    :piles,
    :stage,
    :first_lock,
    :food_nest,
    :food_credit,
    :workers,
    :food_by,
    :period,
    :records,
    :complete,
    # A pile.
    :id,
    :cell,
    :col,
    :size,
    :units,
    :appeared,
    :crossed,
    :fed,
    # A record.
    :time,
    :seconds,
    :names,
    :name,
    :helper,
    :bodies,
    :food,
    :rows,
    :width,
    :left,
    # Values.
    nil,
    true,
    false
  ]

  @doc "All the atoms that a save file can have."
  def atoms, do: @atoms

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

  @doc """
  Reads the term of a save file with the version `version`.

  Returns `{:ok, term}` or `:none`. A file of a different version is not loaded: it gets
  a new name, and the result is `{:old, new path}`.
  """
  def load(path, version) do
    case load(path) do
      {:ok, %{version: ^version} = term} ->
        {:ok, term}

      {:ok, term} ->
        old = if is_map(term) and is_integer(term[:version]), do: term[:version], else: 0
        kept = "#{path}.v#{old}"
        File.rename!(path, kept)
        {:old, kept}

      :none ->
        :none
    end
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
    _ = atoms()
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  rescue
    ArgumentError -> {:error, :bad_file}
  end
end
