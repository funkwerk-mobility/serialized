module text.xml.Decode;

import boilerplate.util : optionallyRemoveTrailingUnderline, udaIndex;
static import dxml.parser;
static import dxml.util;
import serialized.meta.attributesOrNothing;
import serialized.meta.never;
import serialized.meta.SafeUnqual;
import std.algorithm;
import std.array;
import std.exception : enforce;
import std.format : format;
import std.meta;
import std.range;
import std.string : stripLeft;
import std.sumtype;
import std.traits;
import std.typecons;
import text.xml.Convert;
import text.xml.Tree;
import text.xml.Validation : enforceName, normalize, safetyDup;
import text.xml.XmlException;
public import text.xml.Xml;

public alias XmlRange = dxml.parser.EntityRange!(dxml.parser.simpleXML, string);

/**
 * Throws: XmlException if the message is not well-formed or doesn't match the type
 */
public T decode(T, alias customDecode = never)(string message)
{
    static assert(__traits(isSame, customDecode, never), "XML does not yet support a decode function");

    auto range = dxml.parser.parseXML!(dxml.parser.simpleXML)(message);

    return decodeXml!T(range);
}

/**
 * Throws: XmlException if the XML element doesn't match the type
 */
public T decodeXml(T)(XmlRange range)
{
    static if (is(T : SumType!Types, Types...))
    {
        return decodeToplevelSumtype!Types(range);
    }
    else
    {
        enum name = Xml.elementName!(__traits(getAttributes, T))(typeName!T);

        static assert(
            !name.isNull,
            fullyQualifiedName!T ~
            ": type passed to text.xml.decode must have an Xml.Element attribute indicating its element name.");

        range.enforceName(name.get);

        return decodeUnchecked!T(range);
    }
}

/**
 * Throws: XmlException if the XML element doesn't match the type
 * Returns: T, or the type returned from a decoder function defined on T.
 */
public T decodeUnchecked(T, attributes...)(ref XmlRange range)
{
    import std.string : empty, strip;

    static if (isNodeLeafType!(T, attributes))
    {
        return decodeNodeLeaf!(T, attributes)(range);
    }
    else
    {
        static assert(
            __traits(hasMember, T, "ConstructorInfo"),
            fullyQualifiedName!T ~ " does not have a boilerplate constructor!");

        const currentTag = range.front.name;
        auto xmlBuilder = XmlBuilder!T();

        foreach (entry; range.front.attributes)
        {
        switchLabel:
            switch (entry.name)
            {
                static foreach (attributeMethod; definedAttributes!(XmlBuilder!T))
                {
                case __traits(getAttributes, __traits(getMember, xmlBuilder, attributeMethod))[0]:
                    const value = dxml.util.decodeXML(entry.value).safetyDup(entry.value);

                    __traits(getMember, xmlBuilder, attributeMethod) = value;
                    break switchLabel;
                }
                default:
                    // ignore unknown attributes
                    break;
            }
        }

        void tagElement()
        {
            switch (range.front.name)
            {
                static foreach (tagMethod; definedTags!(XmlBuilder!T))
                {
                case __traits(getAttributes, __traits(getMember, xmlBuilder, tagMethod))[0]:
                    __traits(getMember, xmlBuilder, tagMethod) = range;
                    return;
                }
                default:
                    range.skipElement;
                    return;
            }
        }

        void textElement()
        {
            static if (__traits(hasMember, xmlBuilder, "text"))
            {
                xmlBuilder.text = dxml.util.decodeXML(range.front.text).safetyDup(range.front.text);
                range.popFront;
            }
            else
            {
                throw new XmlException(format!"unexpected text entity in %s: '%s'"(currentTag, range.front.text));
            }
        }

        range.byChildElement(&tagElement, &textElement);

        static foreach (finalizerMethod; definedFinalizers!(XmlBuilder!T))
        {
            __traits(getMember, xmlBuilder, finalizerMethod)();
        }

        return xmlBuilder.builder.builderValue;
    }
}

private enum definedAttributes(T) = [__traits(allMembers, T)]
    .filter!(a => a.startsWith("attribute_"))
    .array;

private enum definedTags(T) = [__traits(allMembers, T)]
    .filter!(a => a.startsWith("tag_"))
    .array;

private enum definedFinalizers(T) = [__traits(allMembers, T)]
    .filter!(a => a.startsWith("finalize_"))
    .array;

/*
 * Technical explanation: to implement stream parsing, we take a type T and generate a XML parser type from it.
 * The parser type has three types of methods:
 *
 * - attribute_foo(string): Process a 'foo' attribute
 * - tag_Foo(Range): Process a 'Foo' tag
 * - text(string): Process a text node
 * - finalize_Foo(): called once after parsing
 *
 * The difference is that whereas T may have, say, aliased fields, the XmlBuilder!T corresponds *strictly*
 * to the XML structure of T's element: `<T a="b"><.../> some text </T>`.
 * It is capable of reacting to anything it sees directly, and setting the corresponding field on T's builder.
 */
private struct XmlBuilder(T)
{
    T.BuilderType!() builder;

    mixin BuilderFields!(T, "this.builder");
}

private mixin template BuilderFields(T, string builderPath)
{
    static foreach (string constructorField; T.ConstructorInfo.fields)
    {
        static if (anySatisfy!(ApplyLeft!(sameField, constructorField), __traits(getAliasThis, T)))
        {
            // aliased to this, recurse
            mixin BuilderFields!(
                Unqual!(__traits(getMember, T.ConstructorInfo.FieldInfo, constructorField).Type),
                builderPath ~ "." ~ optionallyRemoveTrailingUnderline!constructorField,
            );
        }
        else
        {
            mixin XmlBuilderField!(
                constructorField,
                Unqual!(__traits(getMember, T.ConstructorInfo.FieldInfo, constructorField).Type),
                builderPath ~ "." ~ optionallyRemoveTrailingUnderline!constructorField,
                AliasSeq!(__traits(getMember, T.ConstructorInfo.FieldInfo, constructorField).attributes),
            );
        }
    }
}

private template sameField(string lhs, string rhs)
{
    enum sameField = optionallyRemoveTrailingUnderline!lhs == optionallyRemoveTrailingUnderline!rhs;
}

private mixin template XmlBuilderField(string constructorField, T, string builderPath, attributes...)
if (!Xml.elementName!attributes("").isNull)
{
    static if (!is(T == string) && is(T : U[], U))
    {
        enum isArray = true;
        alias DecodeType = U;
    }
    else static if (is(T : Nullable!U, U) && !isNodeLeafType!(U, attributes))
    {
        enum isArray = false;
        alias DecodeType = U;
    }
    else
    {
        enum isArray = false;
        alias DecodeType = T;
    }

    static if (is(T : Nullable!V, V))
    {
        enum name = Xml.elementName!attributes(typeName!V).get;
    }
    else
    {
        enum name = Xml.elementName!attributes(typeName!DecodeType).get;
    }

    mixin(format!q{
        static if (isArray)
        {
            DecodeType[] array_;

            void finalize_%s()
            {
                mixin(builderPath) = array_;
            }
        }

        @(name)
        void tag_%s(ref XmlRange range)
        {
            static if (isArray)
            {
                array_ ~= decodeUnchecked!(Unqual!U, attributes)(range);
            }
            else static if(__traits(compiles, .decodeUnchecked!(DecodeType, attributes)(range)))
            {
                auto value = decodeUnchecked!(DecodeType, attributes)(range);

                static if (is(typeof(value) : T))
                {
                    // decoder who returned a Nullable!T; assign directly
                    mixin(builderPath) = value;
                }
                else
                {
                    mixin(builderPath) = value.nullable;
                }
            }
            else
            {
                pragma(msg, "While decoding field '" ~ constructorField ~ "' of type " ~ T.stringof ~ ":");

                // reproduce the error we swallowed earlier
                auto _ = .decodeUnchecked!(DecodeType, attributes)(range);
            }
        }
    }(name.cleanupIdentifier, name.cleanupIdentifier));
}

private mixin template XmlBuilderField(string constructorField, T, string builderPath, attributes...)
if (!Xml.attributeName!attributes(optionallyRemoveTrailingUnderline!constructorField).isNull)
{
    enum attributeName = Xml.attributeName!attributes(optionallyRemoveTrailingUnderline!constructorField).get;

    mixin(format!q{
        @(attributeName)
        void attribute_%s(const string value)
        {
            mixin(builderPath) = decodeAttributeLeaf!(T, attributeName, attributes)(value);
        }
    }(attributeName.cleanupIdentifier));
}

private mixin template XmlBuilderField(string constructorField, T, string builderPath, attributes...)
if (udaIndex!(Xml.Text, attributes) != -1)
{
    void text(string value)
    {
        mixin(builderPath) = value;
    }
}

private mixin template XmlBuilderField(string constructorField, T, string builderPath, attributes...)
if (is(Unqual!T : SumType!U, U...) || is(Unqual!T : SumType!U[], U...))
{
    static if (is(Unqual!T : SumType!U, U...))
    {
        alias Types = staticMap!(stripArray, U);
    }
    else static if (is(Unqual!T : SumType!U[], U...))
    {
        alias Types = U;
    }
    else
    {
        static assert(false, "Unknown kind of sum type: " ~ T.stringof);
    }

    SumType!Types[] decodedValues;

    static foreach (i, SubType; Types)
    {
        mixin XmlSumTypeBuilderMethod!(constructorField, T, builderPath, i);
    }

    mixin(format!q{
        void finalize_%s()
        {
            static if (is(Unqual!T : SumType!U, U...))
            {
                enforce!XmlException(this.decodedValues.length != 0,
                    format!`"%%s": no child element of %%(%%s, %%) in %%s`(
                        builderPath, [staticMap!(typeName, Types)], this.decodedValues));

                size_t[Types.length] occurrences;

                static foreach (i, Type; Types)
                {
                    occurrences[i] = this.decodedValues.count!(a => a.has!Type);
                }
                enforce!XmlException(occurrences[].count!"a > 0" == 1,
                    format!`"%%s": found more than one kind of element of %%(%%s, %%) in %%s`(
                        builderPath, [staticMap!(typeName, Types)], this.decodedValues));

                static foreach (i, Element; U)
                {
                    {
                        alias MatchType = stripArray!Element;

                        auto matches = this.decodedValues.filter!(a => a.has!MatchType).map!(a => a.get!MatchType);

                        static if (is(MatchType : Element))
                        {
                            if (!matches.empty)
                            {
                                enforce!XmlException(matches.dropOne.empty,
                                    format!`"%%s": found more than one %%s in %%s`(
                                        builderPath , MatchType.stringof, this.decodedValues));
                                mixin(builderPath) = T(matches.front);
                            }
                        }
                        else static if (is(MatchType[] : Element))
                        {
                            if (!matches.empty)
                            {
                                mixin(builderPath) = T(matches.array);
                            }
                        }
                        else
                        {
                            static assert(false,
                                "I forgot to handle this case sorry: " ~ MatchType.stringof ~ ", " ~ Element.stringof);
                        }
                    }
                }
            }
            else static if (is(Unqual!T : SumType!U[], U...))
            {
                mixin(builderPath) = this.decodedValues;
            }
            else
            {
                static assert(false, "Unknown kind of sum type: " ~ T.stringof);
            }
        }
    }(constructorField.cleanupIdentifier));
}

private alias stripArray(T) = T;
private alias stripArray(T : string) = T;
private alias stripArray(T : V[], V) = V;

private bool has(T, U : SumType!V, V...)(U value)
{
    return value.match!(
        (T _) => true,
        staticMap!((_) => false, Erase!(T, V)),
    );
}

private T get(T, U : SumType!V, V...)(U value)
{
    return value.match!(
        (T value) => value,
        staticMap!((_) => assert(false), Erase!(T, V)),
    );
}

// Separate template so I can redefine types.
private mixin template XmlSumTypeBuilderMethod(string constructorField, T, string builderPath, int i)
{
    static if (is(Unqual!T : SumType!U_, U_...))
    {
        alias U = U_;
        alias SumTypeMember = U[i];
    }
    else static if (is(Unqual!T : SumType!U_[], U_...))
    {
        alias U = U_;
        alias SumTypeMember = U[i];
    }
    else
    {
        static assert(false, "Unknown kind of sum type: " ~ T.stringof);
    }

    // SumType!(A[], B[])
    static if (!is(SumTypeMember == string) && is(SumTypeMember: V[], V))
    {
        alias BaseType = V;
    }
    else
    {
        alias BaseType = SumTypeMember;
    }

    alias attributes = AliasSeq!(__traits(getAttributes, BaseType));

    static if (Xml.elementName!attributes(typeName!BaseType).isNull)
    {
        static assert(false, fullyQualifiedName!BaseType ~
            ": SumType component type must have an Xml.Element attribute indicating its element name.");
    }
    else
    {
        enum name = Xml.elementName!attributes(typeName!BaseType).get;

        mixin(format!q{
            @(name)
            void tag_%s(ref XmlRange range)
            {
                this.decodedValues ~= typeof(this.decodedValues.front)(decodeUnchecked!(BaseType, attributes)(range));
            }
        }(name.cleanupIdentifier));
    }
}

// XML identifiers can have namespaces separated by colons; this is not valid in D.
private alias cleanupIdentifier = name => name.replace(":", "_");

/**
 * Skip past the current element.
 */
private void skipElement(ref XmlRange range)
in (range.isElement)
{
    range.byChildElement({ range.skipElement; }, { range.skipElement; });
}

/**
 * `range` must point to an element. While there are sub-elements, this function
 * points `range` at each sub-element and invokes `callback`. `callback` is required
 * to advance the range past that sub-element entirely.
 *
 * Throws: XMLParsingException on well-formedness violation.
 * Throws: XmlException on validity violation.
 */
private void byChildElement(ref XmlRange range, scope void delegate() nodeCallback, scope void delegate() textCallback)
in (range.isElement)
{
    if (range.front.type == dxml.parser.EntityType.elementEmpty)
    {
        // no descendants
        range.popFront;
        return;
    }

    auto tag = range.front.name;

    range.popFront;

    while (!range.empty)
    {
        final switch (range.front.type) with (dxml.parser.EntityType)
        {
            case cdata:
            case comment:
            case pi:
                range.popFront;
                continue;
            case elementEnd:
                enforce!XmlException(range.front.name == tag,
                    format!"mismatched xml start and end tags: '%s', '%s'"(tag, range.front.name));
                range.popFront;
                return;
            case text:
                textCallback();
                break;
            case elementEmpty:
            case elementStart:
                nodeCallback();
                break;
        }
    }
    throw new XmlException(format!"Unclosed XML tag %s"(tag));
}

private bool isElement(ref XmlRange range)
{
    return range.front.isElementStartToken;
}

private bool isElementStartToken(const ElementType!XmlRange token)
{
    return token.type == dxml.parser.EntityType.elementStart
        || token.type == dxml.parser.EntityType.elementEmpty;
}

/// Ditto.
private SumType!Types decodeToplevelSumtype(Types...)(ref XmlRange range)
{
    import text.xml.XmlException : XmlException;

    Nullable!(SumType!Types)[Types.length] decodedValues;

    static foreach (i, Type; Types)
    {{
        alias attributes = AliasSeq!(__traits(getAttributes, Type));

        static assert(
            !Xml.elementName!attributes(typeName!Type).isNull,
            fullyQualifiedName!Type ~
            ": SumType component type must have an Xml.Element attribute indicating its element name.");

        enum name = Xml.elementName!attributes(typeName!Type).get;

        if (range.front.name == name)
        {
            decodedValues[i] = SumType!Types(range.decodeUnchecked!Type);
        }
    }}

    const matchedValues = decodedValues[].count!(a => !a.isNull);

    enforce!XmlException(matchedValues != 0,
        format!`Element "%s": no child element of %(%s, %)`(range.front.name, [staticMap!(typeName, Types)]));
    enforce!XmlException(matchedValues == 1,
        format!`Element "%s": contained more than one of %(%s, %)`(range.front.name, [staticMap!(typeName, Types)]));

    return decodedValues[].find!(a => !a.isNull).front.get;
}

private SumType!Types[] decodeSumTypeArray(Types...)(XmlNode node)
{
    SumType!Types[] result;

    foreach (child; node.children)
    {
        static foreach (Type; Types)
        {{
            alias attributes = AliasSeq!(__traits(getAttributes, Type));

            static assert(
                !Xml.elementName!attributes(typeName!Type).isNull,
                fullyQualifiedName!Type ~
                ": SumType component type must have an Xml.Element attribute indicating its element name.");

            enum name = Xml.elementName!attributes(typeName!Type).get;

            if (child.tag == name)
            {
                result ~= SumType!Types(child.decodeUnchecked!Type);
            }
        }}
    }
    return result;
}

private enum typeName(T) = typeof(cast() T.init).stringof;

private auto decodeAttributeLeaf(T, string name, attributes...)(string value)
{
    alias typeAttributes = attributesOrNothing!T;

    static if (udaIndex!(Xml.Decode, attributes) != -1)
    {
        alias decodeFunction = attributes[udaIndex!(Xml.Decode, attributes)].DecodeFunction;

        return decodeFunction(value);
    }
    else static if (udaIndex!(Xml.Decode, typeAttributes) != -1)
    {
        alias decodeFunction = typeAttributes[udaIndex!(Xml.Decode, typeAttributes)].DecodeFunction;

        return decodeFunction(value);
    }
    else static if (is(T : Nullable!U, U))
    {
        import text.xml.Convert : Convert;

        return T(Convert.to!U(value));
    }
    else static if (is(T == enum))
    {
        import serialized.util.SafeEnum : safeToEnum;

        return value.safeToEnum!T;
    }
    else
    {
        import text.xml.Convert : Convert;

        return Convert.to!T(value);
    }
}

// must match decodeNodeLeaf
enum isNodeLeafType(T, attributes...) =
    udaIndex!(Xml.Decode, attributes) != -1
    || udaIndex!(Xml.Decode, attributesOrNothing!T) != -1
    || is(T == string)
    || is(T == enum)
    || __traits(compiles, Convert.to!(SafeUnqual!T)(string.init))
    || is(T : Nullable!U, U) && isNodeLeafType!(U, attributes);

private T decodeNodeLeaf(T, attributes...)(ref XmlRange range)
{
    import text.xml.Parser : parseRange;

    alias typeAttributes = attributesOrNothing!T;

    static if (udaIndex!(Xml.Decode, attributes) != -1 || udaIndex!(Xml.Decode, typeAttributes) != -1)
    {
        static if (udaIndex!(Xml.Decode, attributes) != -1)
        {
            alias decodeFunction = attributes[udaIndex!(Xml.Decode, attributes)].DecodeFunction;
        }
        else
        {
            alias decodeFunction = typeAttributes[udaIndex!(Xml.Decode, typeAttributes)].DecodeFunction;
        }

        auto node = parseRange(range);

        static if (__traits(isTemplate, decodeFunction))
        {
            return decodeFunction!T(node);
        }
        else
        {
            return decodeFunction(node);
        }
    }
    else
    {
        string text = parseTextElement(range);

        static if (is(T == enum))
        {
            import serialized.util.SafeEnum : safeToEnum;

            return text.safeToEnum!T;
        }
        else static if (is(T : Nullable!U, U))
        {
            if (text.empty)
            {
                return T();
            }
            return T(Convert.to!U(text));

        }
        else
        {
            return Convert.to!T(text);
        }
    }
}

private string parseTextElement(ref XmlRange range)
{
    import std.string : strip;

    string startName = null;
    string[] fragments = null;
    int level = 0;

    while (!range.empty)
    {
        final switch (range.front.type) with (dxml.parser.EntityType)
        {
            case cdata:
            case comment:
            case pi:
                range.popFront;
                break;
            case elementStart:
                if (level++ == 0)
                {
                    startName = range.front.name;
                }
                range.popFront;
                break;
            case elementEnd:
                enforce!XmlException(range.front.name == startName,
                    format!"mismatched xml start and end tags: '%s', '%s'"(startName, range.front.name));
                range.popFront;
                if (--level == 0)
                {
                    return fragments.join(" ").normalize;
                }
                break;
            case text:
                if (level == 1)
                {
                    fragments ~= dxml.util.decodeXML(range.front.text).strip.safetyDup(range.front.text);
                }
                range.popFront;
                break;
            case elementEmpty:
                range.popFront;
                if (level == 0)
                {
                    return fragments.join(" ").normalize;
                }
                break;
        }
    }
    throw new XmlException(format!"Unclosed XML tag %s"(startName));
}
