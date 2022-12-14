module text.xml.Tree;

import boilerplate;
import dxml.parser;
import std.algorithm;
import std.range;
import std.typecons;
import text.xml.Writer;

alias Attribute = Tuple!(string, "name", string, "value");

/**
 * This struct holds a list of XML attributes as name/value pairs.
 */
struct Attributes
{

    private Attribute[] attributes;

    private alias lookup = (Attribute attr, string name) => attr.name == name;

    public this(R)(R range)
    if (isInputRange!R && is(ElementType!R == Attribute))
    {
        this = range;
    }

    public typeof(this) opAssign(R)(R range)
    if (isInputRange!R && is(ElementType!R == Attribute))
    {
        this.attributes = range.array;
        return this;
    }

    public inout(Attribute)[] opIndex() inout @nogc nothrow pure @safe
    {
        return this.attributes;
    }

    public string opIndex(string name) nothrow pure @safe
    in (!this.attributes.find!lookup(name).empty, "Attribute not found")
    {
        return this.attributes.find!lookup(name).front.value;
    }

    public ref string opIndexAssign(string value, string name) pure @safe
    {
        auto result = this.attributes.find!lookup(name);

        if (result.empty)
        {
            this.attributes ~= Attribute(name, value);
            return this.attributes.back.value;
        }
        return result.front.value = value;
    }

    public bool opBinaryRight(string op : "in")(string name) const
    {
        return this.attributes.canFind!lookup(name);
    }

    public void free()
    {
        import core.memory : GC;

        GC.free(this.attributes.ptr);
    }
}

/**
 * This struct represents an XML node.
 */
struct XmlNode
{

    enum Type : EntityType
    {
        cdata = EntityType.cdata,
        comment = EntityType.comment,
        text = EntityType.text,
        pi = EntityType.pi,
        element = EntityType.elementStart,
    }

    private Type type_;

    private string tag_;

    public XmlNode[] children;

    public Attributes attributes;

    public @property string tag() const @nogc nothrow pure @safe
    {
        return this.tag_;
    }

    public @property Type type() const @nogc nothrow pure @safe
    {
        return this.type_;
    }

    public auto findChildren(string tag) @nogc pure @safe
    {
        import std.traits : CopyConstness, Unqual;

        // Use mixin template to work around template symbol issue with
        // `FindChildrenRange(T)` instantiating itself with `const(T)`.
        template FindChildrenRangeImpl(T)
        {
            private T[] children;

            private string tag;

            @disable this();

            public this(T[] children, string tag)
            {
                this.children = children;
                this.tag = tag;
                prime;
            }

            public @property bool empty() const @nogc nothrow pure @safe
            {
                return this.children.empty;
            }

            public void popFront() @nogc nothrow pure @safe
            {
                this.children.popFront;
                prime;
            }

            public @property T front() @nogc nothrow pure @safe
            in (!empty)
            {
                return this.children.front;
            }

            public @property auto save() const @nogc nothrow pure @safe
            {
                return ConstFindChildrenRange(children, tag);
            }

            private void prime() @nogc nothrow pure @safe
            {
                while (!empty && (front.type_ != Type.element || front.tag_ != this.tag))
                {
                    this.children.popFront;
                }
            }
        }

        static struct ConstFindChildrenRange
        {
            mixin FindChildrenRangeImpl!(const XmlNode);
        }

        static struct FindChildrenRange
        {
            mixin FindChildrenRangeImpl!XmlNode;
        }

        return FindChildrenRange(this.children, tag);
    }

    public Nullable!XmlNode findChild(string tag) @nogc pure @safe
    {
        auto result = findChildren(tag);

        return result.empty ? typeof(return)() : nullable(result.front);
    }

    public @property string text() const pure @safe
    {
        if (this.type == Type.text)
        {
            return this.tag;
        }
        return this.children.map!(child => child.text).join;
    }

    public string toString() const
    {
        auto sink = appender!string();
        auto writer = customXmlWriter!(No.pretty)(sink);

        writer.write(this);
        return sink.data;
    }

    public void toString(scope void delegate(const(char)[]) sink) const
    {
        auto writer = customXmlWriter!(No.pretty)(sink);

        writer.write(this);
    }

    public XmlNode addAttribute(string name, string value)
    {
        this.attributes.attributes ~= Attribute(name, value);
        return this;
    }

    public void free()
    {
        import core.memory : GC;

        this.children.each!"a.free";
        GC.free(this.children.ptr);
        this.attributes.free;
    }
}
