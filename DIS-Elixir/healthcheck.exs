:inets.start()
port = System.get_env("PORT", "8081")
url = String.to_charlist("http://127.0.0.1:#{port}/health")

case :httpc.request(:get, {url, []}, [timeout: 3_000, connect_timeout: 3_000], []) do
  {:ok, {{_, 200, _}, _, _}} -> System.halt(0)
  _ -> System.halt(1)
end
