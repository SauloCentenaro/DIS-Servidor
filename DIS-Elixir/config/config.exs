import Config
config :nx, :default_backend, {EXLA.Backend, client: :host}
config :exla, :clients, host: [platform: :host]
config :exla, :preferred_clients, [:host]

config :dis,
  port: String.to_integer(System.get_env("PORT", "8081")),
  matrix_dir: System.get_env("MATRIX_DIR", "data"),
  vector_dir: System.get_env("VECTOR_DIR", "vectors"),
  image_dir: System.get_env("IMAGE_DIR", "imagens"),
  http: config_env() != :test
