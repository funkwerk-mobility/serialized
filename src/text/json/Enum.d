module text.json.Enum;

import std.algorithm;
import std.ascii : isLower;
import std.json;
import std.range;
import std.utf;

version (unittest) import dshould;

/**
 * Helper to encode a DStyle enum ("entryName") as JSON style ("ENTRY_NAME").
 *
 * Use like so: `alias encode = encodeEnum!EnumType;` when forming your encode overload.
 */
string encodeEnum(T)(const T value)
if (is(T == enum))
{
    import serialized.util.SafeEnum : safeToString;
    import std.uni : toUpper;

    const enumString = value.safeToString;

    return enumString.splitByPredicate!isWord.map!toUpper.join("_");
}

/// ditto
unittest
{
    import text.json.Encode : encodeJson;

    enum Enum
    {
        testValue,
        isHttp,
        void_,
    }

    alias encode = encodeEnum!Enum;

    encodeJson!(Enum, encode)(Enum.testValue).should.be(JSONValue("TEST_VALUE"));
    encodeJson!(Enum, encode)(Enum.isHttp).should.be(JSONValue("IS_HTTP"));
    encodeJson!(Enum, encode)(Enum.void_).should.be(JSONValue("VOID"));
}

/**
 * Helper to decode a JSON style enum string (ENTRY_NAME) as a DStyle enum (entryName).
 *
 * Use like so: `alias decode = decodeEnum!EnumType;` when forming your decode overload.
 * Throws: JSONException if the input text does not represent an enum member.
 */
template decodeEnum(T)
if (is(T == enum))
{
    U decodeEnum(U : T)(const string text)
    {
        import serialized.util.SafeEnum : safeToString;
        import std.exception : enforce;
        import std.format : format;
        import std.traits : EnumMembers;

        enforce!JSONException(!text.empty, "expected member of " ~ T.stringof);

        switch (text)
        {
            static foreach (member; EnumMembers!T)
            {
            case member.safeToString.screamingSnake:
                    return member;
            }
            default:
                break;
        }

        alias allScreamingSnakes = () => [EnumMembers!T].map!(a => a.safeToString.screamingSnake);

        throw new JSONException(
            format!"expected member of %s (%-(%s, %)), not %s"(T.stringof, allScreamingSnakes(), text));
    }
}

private string screamingSnake(string text)
{
    import std.string : capitalize;
    import std.uni : isUpper, toUpper;
    import std.utf : toUTF8;

    string[] split;
    string buffer;

    void flush()
    {
        split ~= buffer;
        buffer = null;
    }
    foreach (ch; text)
    {
        if (ch.isUpper)
            flush;
        buffer ~= ch.toUpper;
    }
    flush;

    return split.map!((string s) => s.map!toUpper.array.toUTF8).join("_");
}

/// ditto
unittest
{
    import text.json.Decode : decodeJson;

    enum Enum
    {
        testValue,
        isHttp,
        void_,
    }

    alias decode = decodeEnum!Enum;

    // force instantiation
    if (false) decode!Enum("");

    decodeJson!(Enum, decode)(JSONValue("TEST_VALUE")).should.be(Enum.testValue);
    decodeJson!(Enum, decode)(JSONValue("IS_HTTP")).should.be(Enum.isHttp);
    decodeJson!(Enum, decode)(JSONValue("VOID")).should.be(Enum.void_);
    decodeJson!(Enum, decode)(JSONValue("")).should.throwA!JSONException;
    decodeJson!(Enum, decode)(JSONValue("ISNT_HTTP")).should.throwA!JSONException(
        "expected member of Enum (TEST_VALUE, IS_HTTP, VOID), not ISNT_HTTP");
}

alias isWord = text => text.length > 0 && text.drop(1).all!isLower;

private string[] splitByPredicate(alias pred)(string text)
{
    string[] result;
    while (text.length > 0)
    {
        size_t scan = 0;

        while (scan < text.length)
        {
            const newscan = scan + text[scan .. $].stride;

            if (pred(text[0 .. newscan]))
            {
                scan = newscan;
            }
            else
            {
                break;
            }
        }

        result ~= text[0 .. scan];
        text = text[scan .. $];
    }
    return result;
}

unittest
{
    splitByPredicate!isWord("FooBar").should.be(["Foo", "Bar"]);
    splitByPredicate!isWord("FooBAR").should.be(["Foo", "B", "A", "R"]);
    splitByPredicate!isWord("").should.be([]);
}
