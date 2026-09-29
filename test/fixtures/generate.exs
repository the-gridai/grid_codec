fixtures = %{
  "header.hex" =>
    Base.encode16(<<32::little-16, 1::little-16, 100::little-16, 2::little-16>>, case: :lower),
  "primitives.hex" =>
    Base.encode16(
      <<42::little-32, -7::little-signed-64, 1::8, 4::8, "grid"::binary>>,
      case: :lower
    )
}

output_dir = Path.expand("../fixtures", __DIR__)
File.mkdir_p!(output_dir)

Enum.each(fixtures, fn {name, contents} ->
  File.write!(Path.join(output_dir, name), contents <> "\n")
end)
