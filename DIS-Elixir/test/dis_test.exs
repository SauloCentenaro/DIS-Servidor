defmodule DisTest do
  use ExUnit.Case
  import Plug.Test

  test "zero and known solutions for both algorithms" do
    h = Nx.tensor([[1, 0, 0], [0, 2, 0], [0, 0, 3]], type: :f64)

    for algorithm <- [:cgnr, :cgne] do
      {zero, 0} = Dis.Solver.solve(h, Nx.tensor([0, 0, 0], type: :f64), algorithm)
      assert Nx.to_flat_list(zero) == [0.0, 0.0, 0.0]
      {solution, iterations} = Dis.Solver.solve(h, Nx.tensor([2, -6, 12], type: :f64), algorithm)

      Enum.zip(Nx.to_flat_list(solution), [2, -3, 4])
      |> Enum.each(fn {a, b} -> assert_in_delta a, b, 1.0e-4 end)

      assert iterations <= 3
    end
  end

  test "singular CGNR returns zero and CGNE reports breakdown" do
    h = Nx.tensor([[0, 0], [0, 0]], type: :f64)
    g = Nx.tensor([1, 2], type: :f64)
    {f, 0} = Dis.Solver.solve(h, g)
    assert Nx.to_flat_list(f) == [0.0, 0.0]
    assert_raise ArithmeticError, fn -> Dis.Solver.solve(h, g, :cgne) end
  end

  test "both gains update each sample once" do
    for model <- [true, false] do
      samples = if model, do: 794, else: 436

      gains =
        Dis.Gain.apply(Nx.broadcast(Nx.tensor(1.0, type: :f64), {64 * samples}), model)
        |> Nx.to_flat_list()

      gains
      |> Enum.with_index()
      |> Enum.each(fn {value, index} ->
        s = rem(index, samples)
        assert_in_delta value, 100 + s * :math.sqrt(s) / 20, 1.0e-9
      end)
    end
  end

  test "pixels normalized, oriented and PNG encodes identical values" do
    f = Nx.tensor([0, -1000, 500] ++ List.duplicate(0, 897), type: :f64)
    pixels = Dis.Image.pixels(f)
    assert Enum.at(pixels, 30) == 255
    assert Enum.at(pixels, 60) == 128
    assert Enum.all?(pixels, &(&1 >= 0 and &1 <= 255))
    png = Dis.Image.png(pixels)

    <<137, 80, 78, 71, 13, 10, 26, 10, 13::32, "IHDR", _header::binary-size(13), _crc::32,
      length::32, "IDAT", data::binary-size(length), _rest::binary>> = png

    raw = :zlib.uncompress(data)

    expected =
      pixels |> Enum.chunk_every(30) |> Enum.flat_map(&[0 | &1]) |> :erlang.list_to_binary()

    assert raw == expected
    assert Dis.Image.pixels(Nx.broadcast(0.0, {900})) == List.duplicate(0, 900)
  end

  test "input validation and health/preflight" do
    assert_raise ArgumentError, fn -> Dis.Input.number!("nan") end
    assert_raise ArgumentError, fn -> Dis.Input.request!(%{}) end
    assert_raise ArgumentError, fn -> Dis.Input.number!("1garbage") end
    health = conn(:get, "/health") |> Dis.Router.call([])
    assert health.status == 200
    assert Jason.decode!(health.resp_body) == %{"status" => "ok"}
    assert (conn(:options, "/") |> Dis.Router.call([])).status == 204
    assert (conn(:post, "/", "bad") |> Dis.Router.call([])).status == 400
    assert (conn(:post, "/reconstruct", "bad") |> Dis.Router.call([])).status == 400
    assert (conn(:get, "/reconstruct") |> Dis.Router.call([])).status == 404
  end

  test "CSV loading and content type" do
    dir = Path.join(System.tmp_dir!(), "dis-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "model1"))
    path = Path.join(dir, "model1/MODEL1.csv")
    previous = Application.fetch_env!(:dis, :vector_dir)
    Application.put_env(:dis, :vector_dir, dir)

    on_exit(fn ->
      Application.put_env(:dis, :vector_dir, previous)
      File.rm_rf!(dir)
    end)

    File.write!(path, "1,2\n3,4\n")
    assert Nx.to_flat_list(Dis.Matrix.load!(path)) == [1.0, 2.0, 3.0, 4.0]
    result = conn(:get, "/assets/model1/MODEL1.csv") |> Dis.Router.call([])
    assert result.status == 200
    assert Plug.Conn.get_resp_header(result, "content-type") == ["text/csv; charset=utf-8"]
    File.write!(path, "1,2\n3\n")
    assert_raise ArgumentError, fn -> Dis.Matrix.load!(path) end
  end

  test "blocked operators and recursive solvers match dense matrices, including partial blocks" do
    path = Path.join(System.tmp_dir!(), "dis-blocks-#{System.unique_integer([:positive])}.csv")
    File.write!(path, "1,0,0\n0,2,0\n0,0,3\n1,1,0\n0,1,1\n")
    on_exit(fn -> File.rm!(path) end)
    dense = Dis.Matrix.load!(path)
    blocked = Dis.Matrix.load_blocks!(path, 2)
    assert blocked.rows == 5
    assert length(blocked.blocks) == 3
    {5, 3, forward, adjoint} = Dis.Matrix.operators(blocked)
    expected = Nx.tensor([2, -3, 4], type: :f64)
    rhs = forward.(expected)
    assert Nx.to_flat_list(rhs) == Nx.to_flat_list(Nx.dot(dense, expected))
    assert Nx.to_flat_list(adjoint.(rhs)) == Nx.to_flat_list(Nx.dot(Nx.transpose(dense), rhs))

    for algorithm <- [:cgnr, :cgne] do
      {actual, iterations} = Dis.Solver.solve(blocked, rhs, algorithm)
      assert iterations in 1..3

      Enum.zip(Nx.to_flat_list(actual), [2, -3, 4])
      |> Enum.each(fn {value, reference} -> assert_in_delta value, reference, 1.0e-4 end)
    end

    File.write!(path, "1,2\n3\n")
    assert_raise ArgumentError, fn -> Dis.Matrix.load_blocks!(path, 1) end
  end
end
