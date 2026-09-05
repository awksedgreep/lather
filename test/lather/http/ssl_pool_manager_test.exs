defmodule Lather.Http.SSLPoolManagerTest do
  use ExUnit.Case, async: false

  alias Lather.Http.SSLPoolManager
  alias Lather.Http.Transport

  setup do
    SSLPoolManager.reset()
    previous = Application.get_env(:lather, :max_ssl_pools)

    on_exit(fn ->
      SSLPoolManager.reset()

      case previous do
        nil -> Application.delete_env(:lather, :max_ssl_pools)
        value -> Application.put_env(:lather, :max_ssl_pools, value)
      end
    end)

    :ok
  end

  describe "pool_tag/1 canonicalization" do
    test "equivalent options in different key order share a pool tag" do
      opts_a = [verify: :verify_peer, versions: [:"tlsv1.2", :"tlsv1.3"]]
      opts_b = [versions: [:"tlsv1.2", :"tlsv1.3"], verify: :verify_peer]

      assert SSLPoolManager.pool_tag(opts_a) == SSLPoolManager.pool_tag(opts_b)
    end

    test "different options map to different pool tags" do
      opts_a = [verify: :verify_peer]
      opts_b = [verify: :verify_none]

      assert SSLPoolManager.pool_tag(opts_a) != SSLPoolManager.pool_tag(opts_b)
    end
  end

  describe "claim/2 limit enforcement" do
    test "claims within the limit succeed" do
      Application.put_env(:lather, :max_ssl_pools, 2)

      assert :ok = SSLPoolManager.claim("https://a.example.com/soap", verify: :verify_peer)
      assert :ok = SSLPoolManager.claim("https://b.example.com/soap", verify: :verify_peer)
      assert SSLPoolManager.count() == 2
    end

    test "claiming beyond the limit fails" do
      Application.put_env(:lather, :max_ssl_pools, 1)

      assert :ok = SSLPoolManager.claim("https://a.example.com/soap", verify: :verify_peer)

      assert {:error, :pool_limit_exceeded} =
               SSLPoolManager.claim("https://b.example.com/soap", verify: :verify_none)
    end

    test "same origin+options claimed twice counts once" do
      Application.put_env(:lather, :max_ssl_pools, 1)

      assert :ok = SSLPoolManager.claim("https://a.example.com/soap", verify: :verify_peer)
      assert :ok = SSLPoolManager.claim("https://a.example.com/other-path", verify: :verify_peer)
      assert SSLPoolManager.count() == 1
    end

    test "distinct paths on the same origin share one registry slot" do
      Application.put_env(:lather, :max_ssl_pools, 2)

      assert :ok = SSLPoolManager.claim("https://a.example.com/soap-a", verify: :verify_peer)
      assert :ok = SSLPoolManager.claim("https://a.example.com/soap-b", verify: :verify_peer)
      assert SSLPoolManager.count() == 1
    end
  end

  describe "Transport.post/3 with exhausted pool budget" do
    test "returns :ssl_pool_limit_exceeded without starting a pool" do
      Application.put_env(:lather, :max_ssl_pools, 1)

      # Fill the single slot with an unrelated origin.
      assert :ok =
               SSLPoolManager.claim("https://filler.example.com/soap", verify: :verify_peer)

      unique_ssl = [verify: :verify_peer, custom_marker: System.unique_integer([:positive])]

      assert {:error, %{type: :transport_error, reason: :ssl_pool_limit_exceeded}} =
               Transport.post("https://127.0.0.1:9/soap", "<soap/>",
                 ssl_options: unique_ssl,
                 timeout: 100,
                 pool_timeout: 100
               )
    end

    test "requests without ssl_options are unaffected by the limit" do
      Application.put_env(:lather, :max_ssl_pools, 0)
      SSLPoolManager.reset()

      # Unroutable IP with short timeouts: must fail with a plain
      # transport error, not the pool-limit error.
      assert {:error, %{type: :transport_error, reason: reason}} =
               Transport.post("http://10.255.255.1:12345/soap", "<soap/>",
                 timeout: 100,
                 pool_timeout: 100
               )

      refute reason == :ssl_pool_limit_exceeded
    end

    test "ssl pool is pre-started with custom transport opts before the request" do
      unique_ssl = [verify: :verify_peer, custom_marker: System.unique_integer([:positive])]
      url = "https://127.0.0.1:9/soap"
      tag = SSLPoolManager.pool_tag(unique_ssl)

      # Connection is refused, but the pool itself must have been started
      # explicitly (not auto-started by Finch with default opts).
      assert {:error, %{type: :transport_error}} =
               Transport.post(url, "<soap/>",
                 ssl_options: unique_ssl,
                 timeout: 100,
                 pool_timeout: 100
               )

      assert {:ok, _pid} = Finch.find_pool(Lather.Finch, Finch.Pool.new(url, tag: tag))
    end
  end
end
