defmodule Dis.Reconstruction do
  def run(params) do
    start = System.system_time(:microsecond) / 1_000_000
    tick = System.monotonic_time(:microsecond)
    input = Dis.Input.request!(params)
    file = if input.model, do: "H-1.csv", else: "H-2.csv"
    h = Dis.Matrix.load_blocks!(Path.join(Application.fetch_env!(:dis, :matrix_dir), file))
    cols = h.cols

    if cols not in [900, 3600],
      do: raise(ArgumentError, "Matriz com dimensões de imagem inválidas.")

    g = if input.gain, do: Dis.Gain.apply(input.vector, input.model), else: input.vector
    {f, iterations} = Dis.Solver.solve(h, g)
    pixels = Dis.Image.pixels(f)
    dir = Application.fetch_env!(:dis, :image_dir)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "#{input.user}.png"), Dis.Image.png(pixels))
    duration = (System.monotonic_time(:microsecond) - tick) / 1_000_000

    %{
      "user" => input.user,
      "imageVector" => pixels,
      "iteracoes" => iterations,
      "startTime" => start,
      "endTime" => start + duration,
      "durationSeconds" => duration
    }
  end
end
