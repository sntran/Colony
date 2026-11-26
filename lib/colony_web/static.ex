defmodule ColonyWeb.Static do
  @moduledoc """
  Sends the files of the page.

  There is no build step. This plug reads a file, compresses it with gzip, and keeps the
  result in memory. If the file changes, the plug reads it again.
  """

  @behaviour Plug

  import Plug.Conn

  @types %{
    ".html" => "text/html; charset=utf-8",
    ".js" => "text/javascript; charset=utf-8",
    ".mjs" => "text/javascript; charset=utf-8"
  }

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: method} = conn, _opts) when method in ["GET", "HEAD"] do
    case file(conn.path_info) do
      nil -> conn
      path -> send_file(conn, path)
    end
  end

  def call(conn, _opts), do: conn

  # Only these paths give a file.
  defp file([]), do: Application.app_dir(:colony, "priv/static/index.html")

  defp file(["js", name]) do
    if name =~ ~r/^[a-z_]+\.js$/, do: Application.app_dir(:colony, "priv/static/js/#{name}")
  end

  defp file(["vendor", "phoenix.mjs"]), do: Application.app_dir(:phoenix, "priv/static/phoenix.mjs")
  defp file(_), do: nil

  defp send_file(conn, path) do
    case load(path) do
      nil ->
        conn

      %{etag: etag, plain: plain, gzip: gzip} ->
        conn =
          conn
          |> put_resp_content_type(Map.fetch!(@types, Path.extname(path)), nil)
          |> put_resp_header("etag", etag)
          |> put_resp_header("cache-control", "no-cache")
          |> put_resp_header("vary", "accept-encoding")

        cond do
          etag in get_req_header(conn, "if-none-match") ->
            conn |> send_resp(304, "") |> halt()

          accepts_gzip?(conn) ->
            conn |> put_resp_header("content-encoding", "gzip") |> send_resp(200, gzip) |> halt()

          true ->
            conn |> send_resp(200, plain) |> halt()
        end
    end
  end

  defp accepts_gzip?(conn) do
    conn |> get_req_header("accept-encoding") |> Enum.any?(&String.contains?(&1, "gzip"))
  end

  defp load(path) do
    with {:ok, %File.Stat{mtime: mtime, size: size}} <- File.stat(path) do
      key = {__MODULE__, path}

      case :persistent_term.get(key, nil) do
        %{version: {^mtime, ^size}} = entry ->
          entry

        _ ->
          plain = File.read!(path)
          etag = ~s("#{Base.encode16(:crypto.hash(:md5, plain), case: :lower)}")
          entry = %{version: {mtime, size}, plain: plain, gzip: :zlib.gzip(plain), etag: etag}
          :persistent_term.put(key, entry)
          entry
      end
    else
      _ -> nil
    end
  end
end
