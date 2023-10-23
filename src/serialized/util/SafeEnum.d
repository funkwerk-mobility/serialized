/// Functions for safely encoding/decoding enums that may contain D keyword members.
module serialized.util.SafeEnum;

import serialized.meta.reservedIdentifier;
import std.algorithm;
import std.conv : ConvException, to;
import std.format;
import std.traits;

T safeToEnum(T)(string str)
if (is(T == enum))
{
    switch (str)
    {
        static foreach (member; [EnumMembers!T])
        {
            static if (member.to!string.endsWith("_") && reservedIdentifier!(member.to!string()[0 .. $ - 1]))
            {
            // we had no choice but to add a _ to the back, as it was a reserved identifier
            case member.to!string[0 .. $ - 1]:
                return member;
            }
            else
            {
            case member.to!string:
                return member;
            }
        }
        default:
            throw new ConvException(format!"Enum %s did not contain member %s"(T.stringof, str));
    }
}

string safeToString(T)(T value)
if (is(T == enum))
{
    final switch (value)
    {
        static foreach (member; [EnumMembers!T])
        {
        case member:
            enum memberStr = member.to!string;

            static if (memberStr.endsWith("_") && reservedIdentifier!(memberStr[0 .. $ - 1]))
            {
                return memberStr[0 .. $ - 1];
            }
            else
            {
                return memberStr;
            }
        }
    }
}
