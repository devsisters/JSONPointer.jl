const TOKEN_PREFIX = '/'

macro j_str(token)
    Pointer(token)
end

"""
    _unescape_jpath(raw::String)

Transform escaped characters in JPaths back to their original value.
https://tools.ietf.org/html/rfc6901
"""
function _unescape_jpath(raw::AbstractString)
    m = match(r"%([0-9A-F]{2})", raw)
    if m !== nothing
        for c in m.captures
            raw = replace(raw, "%$(c)" => Char(parse(UInt8, "0x$(c)")))
        end
    end
    return raw
end

function _last_element_to_type!(jk)
    if !occursin("::", jk[end])
        return Any
    end
    x = split(jk[end], "::")
    jk[end] = String(x[1])
    if x[2] == "string"
        return String
    elseif x[2] == "number"
        return Union{Int, Float64}
    elseif x[2] == "object"
        return OrderedCollections.OrderedDict{String, Any}
    elseif x[2] == "array"
        return Vector{Any}
    elseif x[2] == "boolean"
        return Bool
    elseif x[2] == "null"
        return Missing
    else
        error(
            "You specified a type that JSON doesn't recognize! Instead of " *
            "`::$(x[2])`, you must use one of `::string`, `::number`, " *
            "`::object`, `::array`, `::boolean`, or `::null`."
        )
    end
end

"""
    Pointer(token::AbstractString; shift_index::Bool = false)

A JSON Pointer is a Unicode string containing a sequence of zero or more
reference tokens, each prefixed by a '/' (%x2F) character.

Follows IETF JavaScript Object Notation (JSON) Pointer https://tools.ietf.org/html/rfc6901.

## Arguments

- `shift_index`: shift given index by 1 for compatibility with original JSONPointer.

## Non-standard extensions

- Index numbers starts from `1` instead of `0`

- User can declare type with '::T' notation at the end. For example
  `/foo::string`. The type `T` must be one of the six types supported by JSON:
  * `::string`
  * `::number`
  * `::object`
  * `::array`
  * `::boolean`
  * `::null`

## Examples

    Pointer("/a")
    Pointer("/a/3")
    Pointer("/a/b/c::number")
    Pointer("/a/0/c::object"; shift_index = true)
"""
struct Pointer{T}
    tokens::Vector{Union{String, Int}}
end

function Pointer(token_string::AbstractString; shift_index::Bool = false)
    if startswith(token_string, "#")
        token_string = _unescape_jpath(token_string[2:end])
    end
    if isempty(token_string)
        return Pointer{Nothing}([""])
    end
    if !startswith(token_string, TOKEN_PREFIX)
        throw(ArgumentError("JSONPointer must starts with '$TOKEN_PREFIX' prefix"))
    end
    tokens = convert(
        Vector{Union{String, Int}},
        String.(split(token_string, TOKEN_PREFIX; keepempty = false)),
    )
    if length(tokens) == 0
        return Pointer{Any}([""])
    end
    T = _last_element_to_type!(tokens)
    for (i, token) in enumerate(tokens)
        if occursin(r"^\d+$", token) # index of a array
            tokens[i] = parse(Int, token)
            if shift_index
                tokens[i] += 1
            end
            if iszero(tokens[i])
                throw(ArgumentError("Julia uses 1-based indexing, use '1' instead of '0'"))
            end
        elseif occursin(r"^\\\d+$", token) # literal string for a number
            tokens[i] = String(chop(token; head = 1, tail = 0))
        elseif occursin("~", token)
            tokens[i] = replace(replace(token, "~0" => "~"), "~1" => "/")
        end
    end
    return Pointer{T}(tokens)
end

Base.length(x::Pointer) = length(x.tokens)

Base.eltype(::Pointer{T}) where {T} = T

function Base.show(io::IO, x::Pointer{T}) where {T}
    print(io, "JSONPointer{", T, "}(\"/", join(x.tokens, "/"), "\")")
end

function Base.show(io::IO, ::Pointer{Nothing})
    print(io, "JSONPointer{Nothing}(\"\")")
end


Base.:(==)(a::Pointer{U}, b::Pointer{U}) where {U} = a.tokens == b.tokens

# ==============================================================================
function _get(collection, p::Pointer, default)
    if _haskey(collection, p)
        return _getindex(collection, p)
    end
    return default
end

# ==============================================================================

_null_value(p::Pointer) = _null_value(eltype(p))
_null_value(::Type{Any}) = missing
_null_value(::Type{String}) = ""
_null_value(::Type{<:Real}) = 0
_null_value(::Type{<:AbstractDict}) = OrderedCollections.OrderedDict{String, Any}()
_null_value(::Type{<:AbstractVector{T}}) where {T} = T[]
_null_value(::Type{Bool}) = false
_null_value(::Type{Nothing}) = nothing
_null_value(::Type{Missing}) = missing

_convert_v(v::U, ::Pointer{U}) where {U} = v
function _convert_v(v::V, p::Pointer{U}) where {U, V}
    v = ismissing(v) ? _null_value(p) : v
    try
        return convert(eltype(p), v)
    catch
        error(
            "$(v)::$(typeof(v)) is not valid type for $(p). Remove type " *
            "assertion in the JSON pointer if you don't a need static type."
        )
    end
end

_new_data(::Any, n::Int) = Vector{Any}(missing, n)
_new_data(::AbstractVector, ::String) = OrderedCollections.OrderedDict{String, Any}()
_new_data(x::AbstractDict, ::String) = empty(x)