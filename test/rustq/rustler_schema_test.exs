defmodule RustQ.RustlerSchemaTest do
  use ExUnit.Case, async: true

  defmodule ContentSchema do
    use RustQ.Rustler.Schema

    schema Folio.Content, default_attrs: ["allow(dead_code)"] do
      field_group :body_content do
        field(:body, {:vec, Content})
      end

      node Text do
        field(:text, :String)
        field(:size, {:option, :String})
      end

      node Space do
      end

      node Paragraph do
        fields(:body_content)
      end

      tagged_enum Content do
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
    assert schema.default_attrs == ["allow(dead_code)"]
    assert schema.type_aliases == []
    assert {:Text, [text: :String, size: {:option, :String}]} not in schema.nodes

    assert {:Text, [{:text, :String, []}, {:size, {:option, :String}, []}], []} in schema.nodes
  end

  defmodule OverrideSchema do
    use RustQ.Rustler.Schema

    schema Folio.Content do
      node Enum, rust: :ExEnum, module: Folio.Content.EnumList do
        field(:children, {:vec, Content})
      end

      node TermItem do
        field(:term, {:vec, Content})
      end

      tagged_enum Content do
        variants([:Enum, :TermItem])
      end
    end
  end

  test "generates Rustler structs and tagged enum" do
    code =
      "__rq_items!();"
      |> RustQ.render!("schema.rs", splice: [items: ContentSchema.rust_items()])

    assert code =~ "#[allow(dead_code)]"
    assert code =~ ~S/#[module = "Folio.Content.Text"]/
    assert code =~ "pub struct ExText"
    assert code =~ "pub size: Option<String>"
    assert code =~ "pub struct ExParagraph"
    assert code =~ "pub body: Vec<ExContent>"
    assert code =~ "pub enum ExContent"
    assert code =~ "Text(ExText)"
    assert code =~ ~S/"Elixir.Folio.Content.Text" => Ok(ExContent::Text(Decoder::decode(term)?))/
    assert code =~ ~S/Err(rustler::Error::RaiseAtom("unknown_content_variant"))/
  end

  test "raises for unknown field groups" do
    assert_raise ArgumentError, ~r/unknown field group/, fn ->
      Code.compile_string("""
      defmodule UnknownGroupSchema do
        use RustQ.Rustler.Schema

        schema Folio.Content do
          node Paragraph do
            fields(:missing)
          end
        end
      end
      """)
    end
  end

  test "supports node Rust and module overrides" do
    code =
      "__rq_items!();"
      |> RustQ.render!("schema.rs", splice: [items: OverrideSchema.rust_items()])

    assert code =~ ~S/#[module = "Folio.Content.EnumList"]/
    assert code =~ "pub struct ExEnum"
    assert code =~ "pub children: Vec<ExContent>"
    assert code =~ "Enum(ExEnum)"

    assert code =~ ~S/"Elixir.Folio.Content.EnumList" =>/
    assert code =~ "Ok(ExContent::Enum(Decoder::decode(term)?))"
    assert code =~ ~S/"Elixir.Folio.Content.TermItem" =>/
    assert code =~ "Ok(ExContent::TermItem(Decoder::decode(term)?))"
  end
end
