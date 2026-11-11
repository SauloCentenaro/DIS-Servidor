defmodule Dis.Router do
  use Plug.Router
  plug(:cors)
  plug(:match)
  plug(:dispatch)

  defp cors(conn, _) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "content-type")
  end

  options(_, do: send_resp(conn, 204, ""))
  get("/health", do: json(conn, 200, %{status: "ok"}))

  get "/" do
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, Path.join(:code.priv_dir(:dis), "index.html"))
  end

  get "/assets/:model/:file" do
    if model in ["model1", "model2"] and file in ["MODEL1.csv", "MODEL2.csv", "MODEL3.csv"] do
      path = Path.join([Application.fetch_env!(:dis, :vector_dir), model, file])

      if File.regular?(path),
        do: conn |> put_resp_content_type("text/csv") |> send_file(200, path),
        else: json(conn, 404, %{error: "CSV não encontrado."})
    else
      json(conn, 404, %{error: "CSV inválido."})
    end
  end

  post("/", do: reconstruct(conn))
  post("/reconstruct", do: reconstruct(conn))

  defp reconstruct(conn) do
    case read_body(conn, length: 8_000_000, read_length: 8_000_000) do
      {:ok, body, conn} ->
        case Jason.decode(body) do
          {:ok, params} ->
            case Dis.Worker.reconstruct(params) do
              {:ok, result} -> json(conn, 200, result)
              {:error, status, message} -> json(conn, status, %{error: message})
            end

          {:error, _} ->
            json(conn, 400, %{error: "JSON inválido."})
        end

      {:more, _, conn} ->
        json(conn, 413, %{error: "Corpo da requisição muito grande."})

      {:error, _} ->
        json(conn, 400, %{error: "Não foi possível ler a requisição."})
    end
  end

  match(_, do: json(conn, 404, %{error: "Endpoint inexistente."}))

  defp json(conn, status, body),
    do:
      conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
end
