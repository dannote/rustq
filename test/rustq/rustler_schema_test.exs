defmodule RustQ.RustlerSchemaTest do
  use ExUnit.Case, async: true

  defmodule ContentSchema do
    use RustQ.Rustler.Schema

    schema Folio.Content do
      rust_prefix("Ex")
      tag_field(:__struct__)

      node Text, attrs: ["allow(dead_code)"] do
        field(:text, :String)
        field(:size, {:option, :String})
      end

      node Space do
      end

      tagged_enum Content, attrs: ["allow(dead_code)"] do
        variants(:all)
        unknown(:unknown_content_variant)
      end
    end
  end

  test "exposes normalized schema data" do
    schema = ContentSchema.schema()

    assert schema.module_prefix == Folio.Content
    assert schema.rust_prefix == "Ex"
    assert schema.tag_field == :__struct__
    assert {:Text, [text: :String, size: {:option, :String}]} not in schema.nodes

    assert {:Text, [{:text, :String, []}, {:size, {:option, :String}, []}],
            attrs: ["allow(dead_code)"]} in schema.nodes
  end

  test "generates Rustler structs and tagged enum" do
    code =
      "__splice_items!();"
      |> RustQ.render!("schema.rs", splice: [items: ContentSchema.rust_items()])

    assert code =~ "#[allow(dead_code)]"
    assert code =~ ~S/#[module = "Folio.Content.Text"]/
    assert code =~ "pub struct ExText"
    assert code =~ "pub size: Option<String>"
    assert code =~ "pub enum ExContent"
    assert code =~ "Text(ExText)"
    assert code =~ ~S/"Elixir.Folio.Content.Text" => Ok(ExContent::Text(Decoder::decode(term)?))/
    assert code =~ ~S/Err(rustler::Error::RaiseAtom("unknown_content_variant"))/
  end
end
