module text.xml.EncodeTest;

import boilerplate;
import dshould;
import dxml.writer;
import std.array;
import std.datetime;
import std.sumtype : match, SumType;
import std.typecons;
import text.xml.Encode;
import text.xml.Tree;
import text.xml.Writer;
import text.xml.Xml;

// All the tests are executed with both `encode(value)` (encodes to a string)
// and `encode(value, writer)` (encodes to a writer).
static foreach (bool streamEncode; [false, true])
{
    mixin encodeTests!(streamEncode);
}

template encodeTests(bool streamEncode)
{
    static if (streamEncode)
    {
        enum prefix = "stream encode";

        string testEncode(T)(T value)
        {
            auto writer = appender!string();

            .encode(value, writer);
            return writer[];
        }
    }
    else
    {
        enum prefix = "string encode";

        string testEncode(T)(T value)
        {
            return .encode(value);
        }
    }

    @(prefix ~ ": fields tagged as Element are encoded as XML elements")
    unittest
    {
        const expected =
            `<root>` ~
                `<IntValueElement>23</IntValueElement>` ~
                `<StringValueElement>FOO</StringValueElement>` ~
                `<BoolValueElement>true</BoolValueElement>` ~
                `<NestedElement>` ~
                    `<Element>BAR</Element>` ~
                `</NestedElement>` ~
                `<ArrayElement>1</ArrayElement>` ~
                `<ArrayElement>2</ArrayElement>` ~
                `<ArrayElement>3</ArrayElement>` ~
                `<DateElement>2000-01-02</DateElement>` ~
                `<SysTimeElement>2000-01-02T10:00:00Z</SysTimeElement>` ~
                `<ContentElement attribute="hello">World</ContentElement>` ~
            `</root>`
        ;

        // given
        const value = (){
            import text.time.Convert : Convert;

            with (Value.Builder())
            {
                intValue = 23;
                stringValue = "FOO";
                boolValue = true;
                nestedValue = NestedValue("BAR");
                arrayValue = [1, 2, 3];
                dateValue = Date(2000, 1, 2);
                sysTimeValue = SysTime.fromISOExtString("2000-01-02T10:00:00Z");
                contentValue = ContentValue("hello", "World");
                return value;
            }
        }();

        // when
        auto text = testEncode(value);

        // then
        text.should.equal(expected);
    }

    @(prefix ~ ": fields tagged as Attribute are encoded as XML attributes")
    unittest
    {
        const expected = `<root intAttribute="23"/>`;

        // given
        const valueWithAttribute = ValueWithAttribute(23);

        // when
        auto text = testEncode(valueWithAttribute);

        // then
        text.should.equal(expected);
    }

    @(prefix ~ ": enum field with underscore")
    unittest
    {
        // given
        enum Enum
        {
            void_,
            foo_,
        }

        @(Xml.Element("element"))
        struct Element
        {
            @(Xml.Attribute("enum"))
            public Enum enum1;

            @(Xml.Element("enum"))
            public Enum enum2;

            mixin(GenerateAll);
        }

        const expected = `<element enum="void"><enum>void</enum></element>`;

        // when
        auto text = testEncode(Element(Enum.void_, Enum.void_));

        // then
        text.should.equal(expected);
    }

    @(prefix ~ ": custom encoders are used on fields")
    unittest
    {
        // given
        const value = ValueWithEncoders("bla", "bla");

        // when
        auto text = testEncode(value);

        // then
        const expected = `<root asFoo="foo"><asBar>bar</asBar></root>`;

        text.should.equal(expected);
    }

    @(prefix ~ ": custom encoders are used on types")
    unittest
    {
        @(Xml.Element("root"))
        struct Value
        {
            @(Xml.Element("foo"))
            EncodeNodeTestType foo;

            @(Xml.Attribute("bar"))
            EncodeAttributeTestType bar;
        }

        // given
        const value = Value(EncodeNodeTestType(), EncodeAttributeTestType());

        // when
        auto text = testEncode(value);

        // then
        const expected = `<root bar="123"><foo>123</foo></root>`;

        text.should.equal(expected);
    }

    @(prefix ~ ": custom encoder on Nullable element")
    unittest
    {
        @(Xml.Element("root"))
        struct Value
        {
            @(Xml.Element("foo"))
            @(Xml.Encode!encodeNodeTestType)
            Nullable!EncodeNodeTestType foo;
        }

        // given
        const value = Value(Nullable!EncodeNodeTestType());

        // when
        const text = testEncode(value);

        // then
        const expected = `<root><foo/></root>`;

        text.should.equal(expected);
    }

    @(prefix ~ ": fields with characters requiring predefined entities")
    unittest
    {
        @(Xml.Element("root"))
        struct Value
        {
            @(Xml.Attribute("foo"))
            string foo;

            @(Xml.Element("bar"))
            string bar;
        }

        // given
        enum invalidInAttr = `<&"`;
        enum invalidInText = `<&]]>`;
        const value = Value(invalidInAttr, invalidInText);

        // when
        auto text = testEncode(value);

        // then
        const expected = `<root foo="&lt;&amp;&quot;"><bar>&lt;&amp;]]&gt;</bar></root>`;

        text.should.equal(expected);
    }

    @(prefix ~ ": regression: encodes optional elements with arrays")
    unittest
    {
        struct Nested
        {
            @(Xml.Element("item"))
            string[] items;
        }

        @(Xml.Element("root"))
        struct Root
        {
            @(Xml.Element("foo"))
            Nullable!Nested nested;
        }

        // given
        const root = Root(Nullable!Nested(Nested(["foo", "bar"])));

        // when
        const text = root.testEncode;

        // then
        text.should.equal(`<root><foo><item>foo</item><item>bar</item></foo></root>`);
    }

    @(prefix ~ ": struct with optional date attribute")
    unittest
    {
        @(Xml.Element("root"))
        static struct NullableAttributes
        {
            @(Xml.Attribute("date"))
            @(This.Default)
            Nullable!Date date;

            mixin(GenerateThis);
        }

        // given
        const root = NullableAttributes();

        // when
        const text = root.testEncode;

        // then
        text.should.equal(`<root/>`);
    }

    @(prefix ~ ": struct with optional date element")
    unittest
    {
        @(Xml.Element("root"))
        static struct NullableAttributes
        {
            @(This.Default)
            @(Xml.Element("date"))
            Nullable!Date date;

            mixin(GenerateThis);
        }

        // given
        const root = NullableAttributes();

        // when
        const text = root.testEncode;

        // then
        text.should.equal(`<root/>`);
    }

    @(prefix ~ ": struct with empty date element")
    unittest
    {
        @(Xml.Element("root"))
        static struct NullableAttributes
        {
            @(Xml.Element("date"))
            Nullable!Date date;

            mixin(GenerateThis);
        }

        // given
        const root = NullableAttributes();

        // when
        const text = root.testEncode;

        // then
        text.should.equal(`<root><date/></root>`);
    }

    @(prefix ~ ": SumType")
    unittest
    {
        with (SumTypeFixture)
        {
            alias Either = SumType!(A, B);

            @(Xml.Element("root"))
            static struct Struct
            {
                Either field;

                mixin(GenerateThis);
            }

            // given/when/then
            Struct(Either(A(5))).testEncode.should.equal(`<root><A a="5"/></root>`);

            Struct(Either(B(3))).testEncode.should.equal(`<root><B b="3"/></root>`);
        }
    }

    @(prefix ~ ": SumType with arrays")
    unittest
    {
        with (SumTypeFixture)
        {
            alias Either = SumType!(A[], B[]);

            @(Xml.Element("root"))
            static struct Struct
            {
                Either field;

                mixin(GenerateThis);
            }

            // given/when/then
            Struct(Either([A(5), A(6)])).testEncode.should.equal(`<root><A a="5"/><A a="6"/></root>`);
        }
    }

    @(prefix ~ ": attribute/element without specified name")
    unittest
    {
        struct Value
        {
            @(Xml.Attribute)
            private int value_;

            mixin(GenerateThis);
        }

        @(Xml.Element)
        struct Container
        {
            @(Xml.Element)
            immutable(Value)[] values;

            mixin(GenerateThis);
        }

        // when
        const text = Container([Value(1), Value(2), Value(3)]).testEncode;

        // then
        text.should.equal(`<Container><Value value="1"/><Value value="2"/><Value value="3"/></Container>`);
    }

    @(prefix ~ ": SysTime as text")
    unittest
    {
        @(Xml.Element)
        struct Value
        {
            @(Xml.Text)
            SysTime time;

            mixin(GenerateThis);
        }

        // when
        const text = Value(SysTime.fromISOExtString("2003-02-01T12:00:00")).testEncode;

        // then
        text.should.equal(`<Value>2003-02-01T12:00:00</Value>`);
    }

    @(prefix ~ ": comment element")
    unittest
    {
        @(Xml.Element)
        struct Value
        {
            @(Xml.Comment)
            string comment;

            mixin(GenerateThis);
        }

        // when
        const text = Value("foo").testEncode;

        // then
        text.should.equal(`<!--foo--><Value/>`);
    }

    @(prefix ~ ": xml namespace")
    unittest
    {
        static struct Child
        {
            mixin(GenerateThis);
        }

        @(Xml.Element)
        static struct Parent
        {
            @(Xml.Attribute("xml:xmlns"))
            @(This.Init!"http://example.com/xmlns")
            string xmlns;

            // TODO it should pick this up on the Child
            @(Xml.Element("xml:child"))
            Child child;

            mixin(GenerateThis);
        }

        // when
        const text = Parent(Child()).testEncode;

        // then
        text.should.equal(`<Parent xml:xmlns="http://example.com/xmlns"><xml:child/></Parent>`);
    }
}

@(Xml.Element("root"))
private struct Value
{
    @(Xml.Element("IntValueElement"))
    public int intValue;

    @(Xml.Element("StringValueElement"))
    public string stringValue;

    @(Xml.Element("BoolValueElement"))
    public bool boolValue;

    @(Xml.Element("NestedElement"))
    public NestedValue nestedValue;

    // Fails to compile when serializing const values
    @(Xml.Element("ArrayElement"))
    public int[] arrayValue;

    @(Xml.Element("DateElement"))
    public Date dateValue;

    @(Xml.Element("SysTimeElement"))
    public SysTime sysTimeValue;

    @(Xml.Element("ContentElement"))
    public ContentValue contentValue;

    mixin (GenerateAll);
}

private struct NestedValue
{
    @(Xml.Element("Element"))
    public string value;

    mixin (GenerateAll);
}

private struct ContentValue
{
    @(Xml.Attribute("attribute"))
    public string attribute;

    @(Xml.Text)
    public string content;

    mixin (GenerateAll);
}

@(Xml.Element("root"))
private struct ValueWithAttribute
{
    @(Xml.Attribute("intAttribute"))
    public int value;

    mixin(GenerateAll);
}

@(Xml.Element("root"))
private struct ValueWithEncoders
{
    @(Xml.Attribute("asFoo"))
    @(Xml.Encode!asFoo)
    public string foo;

    @(Xml.Element("asBar"))
    @(Xml.Encode!asBar)
    public string bar;

    static string asFoo(string field)
    {
        field.should.equal("bla");

        return "foo";
    }

    static void asBar(Writer)(ref Writer writer, string field)
    {
        field.should.equal("bla");

        writer.writeText("bar", Newline.no);
    }

    mixin(GenerateThis);
}

package void encodeNodeTestType(Writer)(ref Writer writer, EncodeNodeTestType)
{
    writer.writeText("123", Newline.no);
}

@(Xml.Encode!encodeNodeTestType)
package struct EncodeNodeTestType
{
}

package string encodeAttributeTestType(EncodeAttributeTestType)
{
    return "123";
}

@(Xml.Encode!encodeAttributeTestType)
package struct EncodeAttributeTestType
{
}

private struct SumTypeFixture
{
    @(Xml.Element("A"))
    static struct A
    {
        @(Xml.Attribute("a"))
        int a;
    }

    @(Xml.Element("B"))
    static struct B
    {
        @(Xml.Attribute("b"))
        int b;
    }
}
