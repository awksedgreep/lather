defmodule Lather.PropertyHardeningTest do
  use ExUnit.Case, async: true

  alias Lather.Auth.{Signature, JWT}
  alias Lather.Mtom.{Attachment, Builder}
  alias Lather.Policy

  defp random_int(min, max) do
    min + :rand.uniform(max - min + 1) - 1
  end

  defp random_string(len) do
    chars = ?a..?z |> Enum.to_list()

    1..len
    |> Enum.map(fn _ ->
      Enum.at(chars, :rand.uniform(length(chars)) - 1)
    end)
    |> List.to_string()
  end

  test "WS-Security signatures verify for random operations and tampering is detected" do
    for _ <- 1..25 do
      operation = random_string(random_int(3, 10))
      key_name = random_string(4)
      value = random_string(random_int(1, 20))
      number = random_int(1, 10_000)
      hmac_key = random_string(16)

      params = %{key_name => value, "n" => number}
      header = Signature.sign_header(operation, params, hmac_key)

      assert Signature.verify(header, operation, params, hmac_key) == :ok

      assert Signature.verify(
               header,
               operation,
               %{key_name => value, "n" => number + 1},
               hmac_key
             ) ==
               {:error, :digest_mismatch}

      assert Signature.verify(header, operation, params, random_string(16)) ==
               {:error, :invalid_signature}
    end
  end

  test "JWT tokens round-trip with random claims" do
    for _ <- 1..20 do
      secret = random_string(12)

      claims = %{
        "sub" => random_string(8),
        "roles" => Enum.shuffle(["admin", "user", "auditor"]) |> Enum.take(random_int(1, 3)),
        "count" => random_int(1, 500)
      }

      token = JWT.token(claims, secret)

      assert match?({:ok, _}, JWT.verify(token, secret))
      assert {:error, :invalid_signature} = JWT.verify(token, random_string(12))
    end
  end

  test "attachments survive random sizes and validate" do
    for _ <- 1..20 do
      data = random_string(random_int(1, 4000))
      attachment = Attachment.new(data, "application/octet-stream")

      assert attachment.size == byte_size(data)
      assert Attachment.validate(attachment) == :ok
      assert Attachment.compressed?(attachment) == false
    end
  end

  test "MTOM is chosen exactly when attachments exceed the threshold" do
    for _ <- 1..25 do
      size = random_int(1, 4000)
      data = random_string(size)
      params = %{"file" => {:attachment, data, "application/octet-stream"}}
      threshold = random_int(500, 3000)

      expect_mtom = size > threshold
      actual = Builder.use_mtom?(params, mtom_threshold: threshold)

      assert actual == expect_mtom

      {:ok, {content_type, body}} =
        Builder.build_message("Upload", params, mtom_threshold: threshold)

      if actual do
        assert content_type =~ "multipart"
        assert body =~ "cid:"
        assert body =~ data
      else
        assert content_type =~ "xml"
        assert body =~ Base.encode64(data)
        refute body =~ "cid:"
      end
    end
  end

  test "policies round-trip through build and parse with random assertions" do
    for _ <- 1..20 do
      auth_factors = Enum.shuffle(["api_key", "jwt", "basic"]) |> Enum.take(random_int(1, 3))

      policy = %{
        "require_auth" => auth_factors,
        "max_body_size" => random_int(100, 10_000),
        "supports_mtom" => :rand.uniform(2) == 1
      }

      {:ok, parsed} = Policy.parse_policy(Policy.build_policy_xml(policy))

      assert parsed["max_body_size"] == policy["max_body_size"]
      assert parsed["supports_mtom"] == policy["supports_mtom"]
      assert Enum.sort(List.wrap(parsed["require_auth"])) == Enum.sort(auth_factors)
    end
  end

  test "policy validation rejects missing auth factors and accepts matching ones" do
    for _ <- 1..20 do
      factors = Enum.shuffle(["api_key", "jwt", "basic"]) |> Enum.take(random_int(1, 3))
      policy = %{"require_auth" => factors}

      first_factor = hd(factors)

      assert {:error, violations} = Policy.validate([], policy)
      assert length(violations) == length(factors)

      case length(factors) do
        1 ->
          assert Policy.validate(
                   [authentication: {String.to_atom(first_factor), "token"}],
                   policy
                 ) ==
                   :ok

        n ->
          assert {:error, partial} =
                   Policy.validate(
                     [authentication: {String.to_atom(first_factor), "token"}],
                     policy
                   )

          assert length(partial) == n - 1
      end
    end
  end
end
