defmodule GridCodec.RequiredCharArrayTest do
  use ExUnit.Case, async: true

  alias GridCodec.TestSupport.RequiredCharArrayFixture

  test "required char array round-trips and never decodes to nil" do
    orig = %RequiredCharArrayFixture{id: 7, code: "XY"}

    assert {:ok, bin} = RequiredCharArrayFixture.encode(orig)
    assert {:ok, decoded} = RequiredCharArrayFixture.decode(bin)
    assert decoded.id == 7
    assert decoded.code == "XY"
    refute is_nil(decoded.code)
  end

  test "required char array decodes an all-null wire slot to empty string" do
    orig = %RequiredCharArrayFixture{id: 1, code: ""}

    assert {:ok, bin} = RequiredCharArrayFixture.encode(orig)
    assert {:ok, %RequiredCharArrayFixture{id: 1, code: ""}} = RequiredCharArrayFixture.decode(bin)
  end
end
