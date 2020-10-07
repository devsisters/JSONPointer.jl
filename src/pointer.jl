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

# TODO(odow): is there a better way to do this not using eval?
function _last_element_to_type!(jk)
    if !occursin("::", jk[end])
        return Any
    end
    x = split(jk[end], "::")
    jk[end] = String(x[1])
    return eval(Meta.parse(x[2]))
end

"""
Pointer(token::AbstractString; shift_index::Bool = false)

A JSON Pointer is a Unicode string containing a sequence of zero or more
reference tokens, each prefixed by a '/' (%x2F) character.

Follows IETF JavaScript Object Notation (JSON) Pointer https://tools.ietf.org/html/rfc6901.

## Arguments

- `shift_index` : shift given index by 1 for compatibility with original JSONPointer.

## Non-standard extensions

- Index numbers starts from '1' instead of '0'
- User can declare type with '::T' notation at the end. For example `/foo::Int`
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

"""
    null_value(p::Pointer{T}) where {T}
    null_value(::Type{T}) where {T}

Provide appropriate null value for 'T'.

For example, `null_value(Real) = 0` and `null_value(AbstractString) = ""`.
"""
null_value(p::Pointer) = null_value(eltype(p))
null_value(::Type{T}) where {T} = missing
null_value(::Type{<:AbstractArray{T}}) where {T <: Real} = T[]
null_value(::Type{<:AbstractArray{T}}) where {T <: AbstractString} = T[]
null_value(::Any) = Any[]

# This code block needs some explaining.
#
# Ideally, one would define methods like Base.haskey(::AbstractDict, ::Pointer).
# However, this causes an ambiguity with Base.haskey(::Dict, key), which has a
# more concrete first argument and a less concrete second argument. We could
# just define both methods to avoid the ambiguity with Dict, but this would
# probably break any package which defines an <:AbstractDict and fails to type
# the second argument to haskey, getindex, etc!
#
# To avoid the ambiguity issue, we have to manually encode each AbstractDict
# subtype that we support :(
for T in (Dict, OrderedCollections.OrderedDict)
    @eval begin
        # This method is used when creating new dictionaries from JSON pointers.
        function $T{K, V}(kv::Pair{<:Pointer, V}...) where {V, K<:Pointer}
            return $T{String, Any}()
        end

        _new_container(::$T) = $T{String, Any}()

        Base.haskey(dict::$T, p::Pointer) = _haskey(dict, p)
        Base.getindex(dict::$T, p::Pointer) = _getindex(dict, p)
        Base.setindex!(dict::$T, v, p::Pointer) = _setindex!(dict, v, p)
        Base.get(dict::$T, p::Pointer, default) = _get(dict, p, default)
    end
end

Base.getindex(A::AbstractArray, p::Pointer) = _getindex(A, p)
Base.haskey(A::AbstractArray, p::Pointer) = _haskey(A, p)

function Base.unique(arr::AbstractArray{<:Pointer, N}) where {N}
    out = deepcopy(arr)
    if isempty(arr)
        return out
    end
    pointers = getfield.(arr, :tokens)
    if allunique(pointers)
        return out
    end
    delete_target = Int[]
    for p in pointers
        indicies = findall(el -> el == p, pointers)
        if length(indicies) > 1
            append!(delete_target, indicies[1:end-1])
        end
    end
    deleteat!(out, unique(delete_target))
    return out
end

Base.:(==)(a::Pointer{U}, b::Pointer{U}) where {U} = a.tokens == b.tokens

# ==============================================================================

_checked_get(collection::AbstractArray, token::Int) = collection[token]

_checked_get(collection::AbstractDict, token::String) = collection[token]

function _checked_get(collection, token)
    error(
        "JSON pointer does not match the data-structure. I tried (and " *
        "failed) to index $(collection) with the key: $(token)"
    )
end

# ==============================================================================

_haskey(::Any, ::Pointer{Nothing}) = true

function _haskey(collection, p::Pointer)
    for token in p.tokens
        if !_haskey(collection, token)
            return false
        end
        collection = _checked_get(collection, token)
    end
    return true
end

_haskey(collection::AbstractDict, token::String) = haskey(collection, token)

function _haskey(collection::AbstractArray, token::Int)
    return 1 <= token <= length(collection)
end

_haskey(::Any, ::Any) = false

# ==============================================================================

_getindex(collection, ::Pointer{Nothing}) = collection

function _getindex(collection, p::Pointer)
    return _getindex(collection, p.tokens)
end

function _getindex(collection, tokens::Vector{Union{String, Int}})
    for token in tokens
        collection = _checked_get(collection, token)
    end
    return collection
end

# ==============================================================================

function _get(collection, p::Pointer, default)
    if _haskey(collection, p)
        return _getindex(collection, p)
    end
    return default
end

# ==============================================================================

_convert_v(v::U, ::Pointer{U}) where {U} = v
function _convert_v(v::V, p::Pointer{U}) where {U, V}
    v = ismissing(v) ? null_value(p) : v
    try
        return convert(eltype(p), v)
    catch
        msg = isa(v, Array) ? "Vector" : "Any"
        error(
            "$(v) is not valid value for $(p) use '::$(msg)' if you don't " *
            "need static type."
        )
    end
end

_new_data(::Any, n::Integer) = Vector{Any}(missing, n)
_new_data(::Any, ::Any) = OrderedCollections.OrderedDict{String, Any}()
_new_data(::AbstractDict, n::Integer) = Vector{Any}(missing, n)
_new_data(x::AbstractDict, ::Any) = _new_container(x)

_prep_prev(prev::Array, k::Integer) = grow_array!(prev, k)
_prep_prev(::Array, k) = throw(MethodError(setindex!, k))
_prep_prev(::Any, k::Integer) = throw(MethodError(setindex!, k))
function _prep_prev(prev::Any, k)
    if !haskey(prev, k)
        setindex!(prev, missing, k)
    end
end

function _setindex!(
    collection::AbstractDict, v, p::Pointer{U}
) where {U}
    v = _convert_v(v, p)
    prev = collection
    for (i, token) in enumerate(p.tokens)
        _prep_prev(prev, token)
        if i < length(p)
            if ismissing(_checked_get(prev, token))
                setindex!(prev, _new_data(prev, p.tokens[i + 1]), token)
            end
            prev = _checked_get(prev, token)
        end
    end
    return setindex!(prev, v, p.tokens[end])
end

_new_arr(::Type{T}, x::Int) where {T <: Real} = zeros(T, x)
_new_arr(::Type{Any}, x::Int) = Vector{Any}(missing, x)
_new_arr(::Type{T}, x::Int) where {T} = Vector{Union{T, Missing}}(missing, x)

function grow_array!(arr::Array{T, N}, target_size::Integer) where {T, N}
    x = target_size - length(arr)
    if x > 0
        append!(arr, _new_arr(T, x))
    end
    return arr
end
