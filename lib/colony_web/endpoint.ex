defmodule ColonyWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :colony

  socket "/socket", ColonyWeb.UserSocket, websocket: true, longpoll: false

  plug :index

  plug Plug.Static, at: "/", from: :colony, only: ~w(index.html js)

  # The channel client of Phoenix comes from the Phoenix package. There is no build step.
  plug Plug.Static, at: "/vendor", from: {:phoenix, "priv/static"}, only: ~w(phoenix.mjs)

  plug :not_found

  # The game is one page. The address "/" gives that page.
  defp index(%Plug.Conn{path_info: []} = conn, _opts) do
    %{conn | path_info: ["index.html"], request_path: "/index.html"}
  end

  defp index(conn, _opts), do: conn

  defp not_found(conn, _opts) do
    conn
    |> Plug.Conn.put_resp_content_type("text/plain")
    |> Plug.Conn.send_resp(404, "Not found")
  end
end
