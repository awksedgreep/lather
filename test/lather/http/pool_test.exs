defmodule Lather.Http.PoolTest do
  use ExUnit.Case, async: true

  doctest Lather.Http.Pool

  alias Lather.Http.Pool

  test "default_config provides sane SOAP defaults" do
    config = Pool.default_config()

    assert Keyword.get(config, :pool_timeout) > 0
    assert Keyword.get(config, :pool_max_idle_time) > 0
    assert is_list(Keyword.get(config, :transport_opts))
  end

  test "config_for_endpoint names pools from the host" do
    config = Pool.config_for_endpoint("https://api.example.com/soap")

    assert config[:name] == String.to_atom("lather_pool_api.example.com")
    assert config[:pool_timeout] == 5_000
  end

  test "config_for_endpoint honors pool_name override" do
    config = Pool.config_for_endpoint("https://api.example.com/soap", pool_name: :my_pool)

    assert config[:name] == :my_pool
  end

  test "config_for_endpoint merges overrides" do
    config =
      Pool.config_for_endpoint("https://api.example.com/soap", size: 50, pool_timeout: 1_000)

    assert Keyword.get(config, :size) == 50
    assert Keyword.get(config, :pool_timeout) == 1_000
  end

  test "validate_config accepts positive integer timeouts" do
    assert Pool.validate_config(pool_timeout: 1_000, pool_max_idle_time: 30_000) == :ok
    assert Pool.validate_config([]) == :ok
  end

  test "warm_connection rejects invalid pool config" do
    assert {:error, {:invalid_pool_config, _}} =
             Lather.Http.Transport.warm_connection("https://api.example.com/soap",
               pool_timeout: -1
             )
  end

  test "validate_config rejects bad timeouts" do
    assert Pool.validate_config(pool_timeout: -1) ==
             {:error, "timeout must be a positive integer"}

    assert Pool.validate_config(pool_max_idle_time: "nope") ==
             {:error, "timeout must be a positive integer"}
  end
end
