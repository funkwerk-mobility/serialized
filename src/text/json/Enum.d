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
    import std.conv : to;
    import std.uni : toUpper;

    const enumString = value.to!string;

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
    }

    alias encode = encodeEnum!Enum;

    encodeJson!(Enum, encode)(Enum.testValue).should.be(JSONValue("TEST_VALUE"));
    encodeJson!(Enum, encode)(Enum.isHttp).should.be(JSONValue("IS_HTTP"));
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
        return genericDecodeEnum!(U, Yes.expectScreaming)(text);
    }
}

package T genericDecodeEnum(T, Flag!"expectScreaming" expectScreaming)(const string text, const string target = null)
{
    import std.conv : to;
    import std.exception : enforce;
    import std.format : format;
    import std.traits : EnumMembers;

    version (strict)
    {
        enum bool checkCamelCase = expectScreaming == false;
        enum bool checkScreamingCase = expectScreaming == true;
    }
    else
    {
        enum bool checkCamelCase = true;
        enum bool checkScreamingCase = true;
    }

    switch (text)
    {
        static foreach (member; EnumMembers!T)
        {
            static if (checkCamelCase)
            {
                case member.to!string:
                    return member;
            }
            static if (checkScreamingCase && member.to!string.screamingSnake != member.to!string)
            {
                case member.to!string.screamingSnake:
                    return member;
            }
        }
        default:
            break;
    }

    enum allMembers = [EnumMembers!T]
        .map!(a => (checkScreamingCase ? [a.to!string.screamingSnake] : []) ~ (checkCamelCase ? [a.to!string] : []))
        .join
        .uniq;

    throw new JSONException(format!"Invalid JSON:%s expected member of %s (%-(%s, %)), but got \"%s\""(
            (target ? (" " ~ target) : ""), T.stringof, allMembers, text));
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
        if (!buffer.empty)
        {
            split ~= buffer;
        }
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
    }

    alias decode = decodeEnum!Enum;

    // force instantiation
    if (false) decode!Enum("");

    decodeJson!(Enum, decode)(JSONValue("TEST_VALUE")).should.be(Enum.testValue);
    decodeJson!(Enum, decode)(JSONValue("IS_HTTP")).should.be(Enum.isHttp);
    decodeJson!(Enum, decode)(JSONValue("")).should.throwA!JSONException;
    decodeJson!(Enum, decode)(JSONValue("ISNT_HTTP")).should.throwA!JSONException(
        `Invalid JSON: expected member of Enum (TEST_VALUE, testValue, IS_HTTP, isHttp), but got "ISNT_HTTP"`);
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
