module text.json.DecodeTest;

import boilerplate;
import dshould;
import std.datetime;
import std.json;
import std.typecons;
import text.json.Decode;
import text.json.Json;
import text.json.ParserMarker;

static foreach (fromJsonValue; [false, true])
{
    @("JSON text with various types is decoded" ~ (fromJsonValue ? " from JSONValue" : ""))
    unittest
    {
        // given
        const text = `
        {
            "IntValueElement": 23,
            "StringValueElement": "FOO",
            "BoolValueElement": true,
            "NestedElement": {
                "Element": "Bar"
            },
            "ArrayElement": [1, 2, 3],
            "AssocArrayElement": {
                "foo": "bar",
                "baz": "whee"
            },
            "DateElement": "2000-01-02",
            "SysTimeElement": "2000-01-02T10:00:00Z"
        }
        `;


        // when
        static if (fromJsonValue)
        {
            auto value = decodeJson!Value(text.parseJSON);
        }
        else
        {
            auto value = decode!Value(text);
        }

        // then

        auto expected = Value.Builder();

        with (expected)
        {
            import text.time.Convert : Convert;

            intValue = 23;
            stringValue = "FOO";
            boolValue = true;
            nestedValue = NestedValue("Bar");
            arrayValue = [1, 2, 3];
            assocArray = ["foo": "bar", "baz": "whee"];
            dateValue = Date(2000, 1, 2);
            sysTimeValue = SysTime.fromISOExtString("2000-01-02T10:00:00Z");
        }

        value.should.equal(expected.value);
    }
}

@("Nullable fields are optional")
unittest
{
    decode!OptionalValues(`{}`).should.not.throwAn!Exception;
}

@("informative errors are reported when failing to decode types")
unittest
{
    decode!OptionalValues(`{ "boolValue": "" }`).should.throwA!JSONException
        (`Invalid JSON: text.json.DecodeTest.OptionalValues.boolValue expected bool, but got ""`);
    decode!OptionalValues(`{ "intValue": "" }`).should.throwA!JSONException
        (`Invalid JSON: text.json.DecodeTest.OptionalValues.intValue expected int, but got ""`);
    decode!OptionalValues(`{ "enumValue": "B" }`).should.throwA!JSONException
        (`Invalid JSON: text.json.DecodeTest.OptionalValues.enumValue expected member of Enum, but got "B"`);
    decode!OptionalValues(`{ "enumValue": 5 }`).should.throwA!JSONException
        (`Invalid JSON: text.json.DecodeTest.OptionalValues.enumValue expected enum string, but got 5`);
    decode!OptionalValues(`{ "stringValue": 5 }`).should.throwA!JSONException
        (`Invalid JSON: text.json.DecodeTest.OptionalValues.stringValue expected string, but got 5`);
    decode!OptionalValues(`{ "arrayValue": [""] }`).should.throwA!JSONException
        (`Invalid JSON: text.json.DecodeTest.OptionalValues.arrayValue[0] expected int, but got ""`);
}

struct OptionalValues
{
    enum Enum
    {
        A
    }

    Nullable!bool boolValue;
    Nullable!int intValue;
    Nullable!Enum enumValue;
    Nullable!string stringValue;
    Nullable!(int[]) arrayValue;

    mixin(GenerateThis);
}

@("custom decoders are used on fields")
unittest
{
    // given
    const text = `{ "asFoo": "foo", "asBar": "bar" }`;

    // when
    auto value = decode!ValueWithDecoders(text);

    // then
    const expected = ValueWithDecoders("foobla", "barbla");

    value.should.equal(expected);
}

@("custom decoders are used on a type")
unittest
{
    // given
    const text = `{ "field": "bla" }`;

    // when
    struct Value
    {
        TypeWithDecoder field;

        mixin(GenerateThis);
    }

    auto value = decode!Value(text);

    // then
    const expected = Value(TypeWithDecoder("123"));

    value.should.equal(expected);
}

@("custom decoder with int array")
unittest
{
    // when
    const value = decode!TypeWithIntArrayDecoder(`[2, 3, 4]`);

    // then
    auto arr = [2, 3, 4];
    auto exp = TypeWithIntArrayDecoder(arr);

    value.should.equal(exp);
}

@(Json.Decode!decodeTypeWithIntArrayDecoder)
struct TypeWithIntArrayDecoder
{
    int[] value;
}

TypeWithIntArrayDecoder decodeTypeWithIntArrayDecoder(JSONValue value)
{
    return TypeWithIntArrayDecoder(decodeJson!(int[])(value));
}

@("enums are decoded from strings")
unittest
{
    enum Enum
    {
        A
    }

    struct Value
    {
        Enum field;

        mixin(GenerateAll);
    }

    // given
    const text = `{ "field": "A" }`;

    // when
    const value = decode!Value(text);

    // then
    const expected = Value(Enum.A);

    value.should.equal(expected);
}

@("enum supports keyword")
unittest
{
    enum Enum
    {
        void_,
    }

    // given
    const text = `"void"`;

    // when
    const value = decode!Enum(text);

    // then
    value.should.equal(Enum.void_);
}

@("alias-this is decoded from inline keys")
unittest
{
    struct A
    {
        int value2;

        mixin(GenerateAll);
    }

    struct B
    {
        int value1;

        A a;

        alias a this;

        mixin(GenerateAll);
    }

    // given
    const text = `{ "value1": 3, "value2": 5 }`;

    // when
    const actual = decode!B(text);

    // then
    const expected = B(3, A(5));

    actual.should.equal(expected);
}

@("@AliasThis is decoded from inline keys")
unittest
{
    struct A
    {
        int value2;

        mixin(GenerateAll);
    }

    struct B
    {
        int value1;

        @AliasThis
        A a;

        mixin(GenerateAll);
    }

    // given
    const text = `{ "value1": 3, "value2": 5 }`;

    // when
    const actual = decode!B(text);

    // then
    const expected = B(3, A(5));

    actual.should.equal(expected);
}

@("alias-this is decoded from inline keys for aliased methods")
unittest
{
    struct A
    {
        int value2;

        mixin(GenerateAll);
    }

    struct B
    {
        int value1;

        @ConstRead
        A a_;

        mixin(GenerateAll);

        alias a this;
    }

    // given
    const text = `{ "value1": 3, "value2": 5 }`;

    // when
    const actual = decode!B(text);

    // then
    const expected = B(3, A(5));

    actual.should.equal(expected);
}

static foreach (bool useJsonValueRange; [false, true])
{
    @("array of structs with alias-this is decoded" ~ (useJsonValueRange ? " from JsonStream" : ""))
    unittest
    {
        struct A
        {
            int a;

            mixin(GenerateAll);
        }

        struct B
        {
            A a;

            int b;

            alias a this;

            mixin(GenerateAll);
        }

        // given
        const text = `[{ "a": 1, "b": 2 }, { "a": 3, "b": 4}]`;

        // when
        static if (useJsonValueRange)
        {
            const actual = decodeJson!(B[])(text.parseJSON);
        }
        else
        {
            const actual = decode!(B[])(text);
        }

        // then
        const expected = [B(A(1), 2), B(A(3), 4)];

        actual.should.equal(expected);
    }
}

struct NestedValue
{
    @(Json("Element"))
    public string value;

    mixin (GenerateAll);
}

struct Value
{
    @(Json("IntValueElement"))
    public int intValue;

    @(Json("StringValueElement"))
    public string stringValue;

    @(Json("BoolValueElement"))
    public bool boolValue;

    @(Json("NestedElement"))
    public NestedValue nestedValue;

    @(Json("ArrayElement"))
    public const int[] arrayValue;

    @(Json("AssocArrayElement"))
    public string[string] assocArray;

    @(Json("DateElement"))
    public Date dateValue;

    @(Json("SysTimeElement"))
    public SysTime sysTimeValue;

    mixin (GenerateAll);
}

struct ValueWithDecoders
{
    @(Json("asFoo"))
    @(Json.Decode!fromFoo)
    public string foo;

    @(Json("asBar"))
    @(Json.Decode!fromBar)
    public string bar;

    static string fromFoo(JSONValue value)
    {
        value.str.should.equal("foo");

        return "foobla";
    }

    static string fromBar(JSONValue value)
    {
        value.str.should.equal("bar");

        return "barbla";
    }

    mixin(GenerateThis);
}

@(Json.Decode!decodeTypeWithDecoder)
struct TypeWithDecoder
{
    string value;
}

TypeWithDecoder decodeTypeWithDecoder(JSONValue value)
{
    value.should.equal(JSONValue("bla"));

    return TypeWithDecoder("123");
}

@("transform functions may modify the values that are decoded")
unittest
{
    import std.conv : to;

    struct InnerDto
    {
        string encodedValue;

        mixin(GenerateThis);
    }

    struct Inner
    {
        int value;

        mixin(GenerateThis);
    }

    struct Struct
    {
        Inner inner;

        mixin(GenerateThis);
    }

    alias transform(T : Inner) = (InnerDto innerDto) =>
        Inner(innerDto.encodedValue.to!int);

    // !!! important to instantiate transform somewhere, to shake out errors
    assert(transform!Inner(InnerDto("3")) == Inner(3));

    // given
    const text = `{ "inner": { "encodedValue": "5" } }`;

    // when
    const actual = decode!(Struct, transform)(text);

    // then
    const expected = Struct(Inner(5));

    actual.should.equal(expected);
}

@("transform function with JSONValue parameter")
unittest
{
    import std.conv : to;

    struct Inner
    {
        int value;

        mixin(GenerateThis);
    }

    struct Struct
    {
        Inner inner;

        mixin(GenerateThis);
    }

    alias transform(T : Inner) = (JSONValue json) =>
        Inner(json.str.to!int);

    // !!! important to instantiate transform somewhere, to shake out errors
    assert(transform!Inner(JSONValue("3")) == Inner(3));

    // given
    const text = `{ "inner": "5" }`;

    // when
    const actual = decode!(Struct, transform)(text);

    // then
    const expected = Struct(Inner(5));

    actual.should.equal(expected);
}

@("decode const array")
unittest
{
    // given
    const text = `[1, 2, 3]`;

    // when
    const actual = decode!(const(int[]))(text);

    // Then
    const expected = [1, 2, 3];

    actual.should.equal(expected);
}

@("missing fields")
unittest
{
    // given
    const text = `{}`;

    struct S
    {
        int field;

        mixin(GenerateThis);
    }

    // when/then
    decode!S(text).should.throwA!JSONException("expected S.field, but got {}");
}

@("decode object from non-object")
unittest
{
    // given
    const text = `[]`;

    struct S
    {
        int field;

        mixin(GenerateThis);
    }

    // when/then
    decode!S(text).should.throwA!JSONException;
}

@("decode null object")
unittest
{
    // given
    const text = `null`;

    static class Value
    {
        mixin(GenerateAll);
    }

    // when/then
    decode!Value(text).should.be(null);
}

@("struct with version_ field")
unittest
{
    // given
    const text = `{ "version": 1 }`;

    struct Value
    {
        int version_;

        mixin(GenerateAll);
    }

    // when/then
    text.decode!Value.should.equal(Value(1));
}

@("const associative array")
unittest
{
    // given
    const text = ` { "key": "value" }`;

    // when/then
    text.decode!(const(string[string])).should.equal(["key": "value"]);
}

@("associative array in immutable struct")
unittest
{
    // given
    const text = `{ "entry": { "key": "value" } }`;

    immutable struct Value
    {
        string[string] entry;

        mixin(GenerateAll);
    }

    // when/then
    text.decode!Value.should.equal(Value(["key": "value"]));
}

@("parsing is resumed")
unittest
{
    static immutable struct FirstPass
    {
        string str;

        int i;

        ParserMarker value;

        mixin(GenerateThis);
    }

    static struct Value
    {
        string message;

        int[] array;

        mixin(GenerateThis);
    }

    // given
    const text = `
    {
        "value": {
            "message": "Hello World",
            "array": [4, 5, 6]
        },
        "str": "String",
        "i": 5
    }
    `;

    const firstPass = decode!FirstPass(text);
    const secondPass = firstPass.value.decode!Value;

    secondPass.should.equal(Value("Hello World", [4, 5, 6]));
}

@("associative array aliased to this in immutable struct")
unittest
{
    // given
    const text = `{ "entry": { "key": "value" } }`;

    immutable struct Entry
    {
        string[string] entry;

        alias entry this;

        mixin(GenerateAll);
    }

    immutable struct Container
    {
        Entry entry;

        mixin(GenerateAll);
    }

    // when/then
    text.decode!Container.should.equal(Container(Entry(["key": "value"])));
}

@("JSONValue alias-this matches all extra keys")
unittest
{
    // given
    const text = `{ "a": 1, "b": 2, "c": 3 }`;

    struct Value
    {
        int b;

        JSONValue extras;

        alias extras this;

        mixin(GenerateAll);
    }

    // when/then
    text.decode!Value.should.equal(Value(2, JSONValue(["a": 1, "c": 3])));
}

@("alias-this does not match keys from the parent")
unittest
{
    // given
    const text = `{ "a": 1, "b": 2 }`;

    struct Inner
    {
        @(This.Default!0)
        int a;

        int b;

        mixin(GenerateAll);
    }

    struct Value
    {
        int a;

        Inner inner;

        alias inner this;

        mixin(GenerateAll);
    }

    // when/then
    text.decode!Value.should.equal(Value(1, Inner(2, 0)));
}

@("immutable struct with alias this")
unittest
{
    // given
    immutable struct Struct
    {
        int value;

        alias value this;

        mixin(GenerateThis);
    }

    // when/then
    "5".decode!Struct.should.equal(Struct(5));
}

@("type with invariant")
unittest
{
    import std.algorithm : endsWith;

    // given
    const text = `{ "a": 2, "b": 3 }`;

    static struct Value
    {
        int a;

        int b;

        invariant (this.a == this.b);

        mixin(GenerateAll);
    }

    // when/then
    text.decode!Value.should.throwA!JSONException
        .where.msg.endsWith("while decoding Value: Assertion failure").should.be(true);
}

@("non-default Nullable")
unittest
{
    static struct Value
    {
        Nullable!int field;

        mixin(GenerateThis);
    }

    // given
    const text = `{ "field": null }`;

    // when/then
    text.decode!Value.should.equal(Value(Nullable!int()));
}

@("nullable value")
unittest
{
    `null`.decode!(Nullable!int).should.be(Nullable!int());
    `5`.decode!(Nullable!int).should.be(5);
}

@("decode type with fromString method")
unittest
{
    // given
    struct S
    {
        size_t length;

        static S fromString(string text)
        {
            return S(text.length);
        }

        mixin(GenerateThis);
    }

    // when/then
    decode!S(`"Hello"`).should.be(S(5));
}
