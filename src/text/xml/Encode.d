module text.xml.Encode;

import boilerplate.util;
import dxml.util;
import dxml.writer;
import serialized.meta.attributesOrNothing;
import std.array;
import std.meta;
import std.sumtype : match, SumType;
import std.traits;
import std.typecons;
import text.xml.Convert;
import text.xml.Xml;

/**
 * The `text.xml.encode` function encodes an arbitrary type as XML.
 * Each tagged field in the type is encoded.
 * Tags are @(Xml.Attribute("attributeName")) and @(Xml.Element("tagName")).
 * Types passed directly to `encode` must be annotated with an @(Xml.Element("...")) attribute.
 * Child types must be annotated at their fields in the containing type.
 * For array fields, their values are encoded sequentially.
 * Nullable fields are empty if they are null.
 * If they are also @(This.Default), they are omitted.
 */
public string encode(T)(const T value)
in
{
    static if (is(T == class))
    {
        assert(value !is null);
    }
}
do
{
    mixin enforceTypeHasElementTag!(T, "type passed to text.xml.encode");

    alias attributes = AliasSeq!(__traits(getAttributes, T));
    auto writer = xmlWriter(appender!string);

    encodeNode!(T, Appender!string, attributes)(writer, value);

    return writer.output.data;
}

/// Ditto.
public void encode(T, Writer)(const T value, ref Writer writer)
in
{
    static if (is(T == class))
    {
        assert(value !is null);
    }
}
do
{
    mixin enforceTypeHasElementTag!(T, "type passed to text.xml.encode");

    alias attributes = AliasSeq!(__traits(getAttributes, T));
    auto xmlWriter = .xmlWriter(&writer);

    encodeNode!(T, Writer*, attributes)(xmlWriter, value);
}

private void encodeNode(T, Writer, attributes...)(ref XMLWriter!Writer writer, const T value)
{
    enum elementName = Xml.elementName!attributes(typeName!T).get;

    writer.openStartTag(elementName, Newline.no);

    // encode all the attribute members
    static foreach (member; FilterMembers!(T, value, true))
    {{
        auto memberValue = __traits(getMember, value, member);
        alias memberAttrs = AliasSeq!(__traits(getAttributes, __traits(getMember, value, member)));
        alias PlainMemberT = typeof(cast() memberValue);
        enum name = Xml.attributeName!memberAttrs(optionallyRemoveTrailingUnderline!member).get;

        static if (is(PlainMemberT : Nullable!Arg, Arg))
        {
            if (!memberValue.isNull)
            {
                writer.writeAttr(name, encodeLeafImpl!(Arg, memberAttrs)(memberValue.get).encodeAttr, Newline.no);
            }
        }
        else
        {
            writer.writeAttr(name, encodeLeafImpl!(PlainMemberT, memberAttrs)(memberValue).encodeAttr, Newline.no);
        }
    }}

    bool tagIsEmpty = true;

    static foreach (member; FilterMembers!(T, value, false))
    {{
        alias memberAttrs = AliasSeq!(__traits(getAttributes, __traits(getMember, value, member)));
        alias PlainMemberT = typeof(cast() __traits(getMember, value, member));
        enum hasXmlTag = !Xml.elementName!memberAttrs(typeName!PlainMemberT).isNull
            || udaIndex!(Xml.Text, memberAttrs) != -1;
        enum isSumType = is(PlainMemberT : SumType!U, U...);
        static if (__traits(hasMember, T, "ConstructorInfo")
            && __traits(hasMember, T.ConstructorInfo.FieldInfo, member))
        {
            enum useDefault = __traits(getMember, T.ConstructorInfo.FieldInfo, member).useDefault;
        }
        else
        {
            enum useDefault = false;
        }

        static if (hasXmlTag || isSumType)
        {
            static if (is(PlainMemberT : Nullable!Arg, Arg))
            {
                // if @(This.Default) and null, tag is omitted.
                if (!(useDefault && __traits(getMember, value, member).isNull))
                {
                    tagIsEmpty = false;
                }
            }
            else
            {
                tagIsEmpty = false;
            }
        }
    }}

    writer.closeStartTag(tagIsEmpty ? EmptyTag.yes : EmptyTag.no);

    if (!tagIsEmpty)
    {
        static foreach (member; FilterMembers!(T, value, false))
        {{
            alias memberAttrs = AliasSeq!(__traits(getAttributes, __traits(getMember, value, member)));
            alias PlainMemberT = typeof(cast() __traits(getMember, value, member));
            enum name = Xml.elementName!memberAttrs(typeName!PlainMemberT);
            static if (__traits(hasMember, T, "ConstructorInfo")
                && __traits(hasMember, T.ConstructorInfo.FieldInfo, member))
            {
                enum useDefault = __traits(getMember, T.ConstructorInfo.FieldInfo, member).useDefault;
            }
            else
            {
                enum useDefault = false;
            }

            static if (!name.isNull)
            {
                enum string nameGet__ = name.get; // work around for weird compiler bug
                auto memberValue = __traits(getMember, value, member);

                encodeNodeImpl!(nameGet__, PlainMemberT, Writer, useDefault, memberAttrs)(writer, memberValue);
            }
            else static if (udaIndex!(Xml.Text, memberAttrs) != -1)
            {
                auto memberValue = __traits(getMember, value, member);

                writer.writeText(encodeLeafImpl(memberValue).encodeText, Newline.no);
            }
            else static if (is(PlainMemberT : SumType!U, U...))
            {
                auto memberValue = __traits(getMember, value, member);

                encodeSumType(writer, memberValue);
            }
        }}

        writer.writeEndTag(Newline.no);
    }
}

private void encodeSumType(T, Writer)(ref XMLWriter!Writer writer, const T value)
{
    value.match!(staticMap!((const value) {
        alias T = typeof(value);

        static if (is(T: U[], U))
        {
            alias BaseType = U;
        }
        else
        {
            alias BaseType = T;
        }

        mixin enforceTypeHasElementTag!(BaseType, "every member type of SumType");

        alias attributes = AliasSeq!(__traits(getAttributes, BaseType));
        enum name = Xml.elementName!attributes(typeName!BaseType).get;

        encodeNodeImpl!(name, T, Writer, false, attributes)(writer, value);
    }, T.Types));
}

private mixin template enforceTypeHasElementTag(T, string context)
{
    static assert(
        !Xml.elementName!(__traits(getAttributes, T))(typeName!T).isNull,
        fullyQualifiedName!T ~
        ": " ~ context ~ " must have an Xml.Element attribute indicating its element name.");
}

private enum typeName(T) = typeof(cast() T.init).stringof;

private template FilterMembers(T, alias value, bool keepXmlAttributes)
{
    alias pred = ApplyLeft!(attrFilter, value, keepXmlAttributes);
    alias FilterMembers = Filter!(pred, __traits(derivedMembers, T));
}

private template attrFilter(alias value, bool keepXmlAttributes, string member)
{
    // double-check that the member has a type to work around https://issues.dlang.org/show_bug.cgi?id=22214
    static if (is(typeof(__traits(getMember, value, member)))
        && __traits(compiles, { auto value = __traits(getMember, value, member); })
        && __traits(getOverloads, value, member).length <= 1)
    {
        alias attributes = AliasSeq!(__traits(getAttributes, __traits(getMember, value, member)));
        static if (keepXmlAttributes)
        {
            enum bool attrFilter = !Xml.attributeName!(attributes)("").isNull;
        }
        else
        {
            enum bool attrFilter = Xml.attributeName!(attributes)("").isNull;
        }
    }
    else
    {
        enum bool attrFilter = false;
    }
}

// test for https://issues.dlang.org/show_bug.cgi?id=22214
unittest
{
    static struct S
    {
        struct T { }
    }
    S s;
    static assert(attrFilter!(s, false, "T") == false);
}

private void encodeNodeImpl(string name, T, Writer, bool useDefault, attributes...)(
    ref XMLWriter!Writer writer, const T value)
{
    alias PlainT = typeof(cast() value);

    static if (__traits(compiles, __traits(getAttributes, T)))
    {
        alias typeAttributes = AliasSeq!(__traits(getAttributes, T));
    }
    else
    {
        alias typeAttributes = AliasSeq!();
    }

    static if (is(PlainT : Nullable!Arg, Arg))
    {
        if (!value.isNull)
        {
            encodeNodeImpl!(name, Arg, Writer, false, attributes)(writer, value.get);
        }
        else if (!useDefault)
        {
            // <foo />
            writer.openStartTag(name, Newline.no);
            writer.closeStartTag(EmptyTag.yes);
        }
    }
    else static if (udaIndex!(Xml.Encode, attributes) != -1)
    {
        alias customEncoder = attributes[udaIndex!(Xml.Encode, attributes)].EncodeFunction;

        writer.openStartTag(name, Newline.no);
        writer.closeStartTag;

        customEncoder(writer, value);
        writer.writeEndTag(name, Newline.no);
    }
    else static if (udaIndex!(Xml.Encode, typeAttributes) != -1)
    {
        alias customEncoder = typeAttributes[udaIndex!(Xml.Encode, typeAttributes)].EncodeFunction;

        writer.openStartTag(name, Newline.no);
        writer.closeStartTag;

        customEncoder(writer, value);
        writer.writeEndTag(name, Newline.no);
    }
    else static if (isLeafType!(PlainT, attributes))
    {
        writer.openStartTag(name, Newline.no);
        writer.closeStartTag;

        writer.writeText(encodeLeafImpl(value).encodeText, Newline.no);
        writer.writeEndTag(name, Newline.no);
    }
    else static if (isIterable!PlainT)
    {
        alias IterationType(T) = typeof({ foreach (value; T.init) return value; assert(0); }());

        foreach (IterationType!PlainT a; value)
        {
            encodeNodeImpl!(name, typeof(a), Writer, false, attributes)(writer, a);
        }
    }
    else
    {
        encodeNode!(PlainT, Writer, attributes)(writer, value);
    }
}

// must match encodeLeafImpl
private enum bool isLeafType(T, attributes...) =
    udaIndex!(Xml.Encode, attributes) != -1
    || udaIndex!(Xml.Encode, attributesOrNothing!T) != -1
    || is(T == string)
    || is(T == enum)
    || __traits(compiles, { Convert.toString(T.init); });

private string encodeLeafImpl(T, attributes...)(T value)
{
    alias typeAttributes = attributesOrNothing!T;

    static if (udaIndex!(Xml.Encode, attributes) != -1)
    {
        alias customEncoder = attributes[udaIndex!(Xml.Encode, attributes)].EncodeFunction;

        return customEncoder(value);
    }
    else static if (udaIndex!(Xml.Encode, typeAttributes) != -1)
    {
        alias customEncoder = typeAttributes[udaIndex!(Xml.Encode, typeAttributes)].EncodeFunction;

        return customEncoder(value);
    }
    else static if (is(T == string))
    {
        return value;
    }
    else static if (is(T == enum))
    {
        import serialized.util.SafeEnum : safeToString;

        return value.safeToString;
    }
    else static if (__traits(compiles, Convert.toString(value)))
    {
        return Convert.toString(value);
    }
    else
    {
        static assert(false, "Unknown value type: " ~ T.stringof);
    }
}
