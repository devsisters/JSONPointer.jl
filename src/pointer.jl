const TOKEN_PREFIX = '/'

macro j_str(token)
    Pointer(token)
end

"""
    Pointer(token)

A JSON Pointer is a Unicode string containing a sequence of zero or more reference tokens, each prefixed
by a '/' (%x2F) character.

Follows IETF JavaScript Object Notation (JSON) Pointer https://tools.ietf.org/html/rfc6901

- Index numbers starts from '1' instead of '0'
- User can declare type with '::T' notation at the end

# Arguments
- `shift_index` : shift given index by 1 for compatibility with original JSONPointer

"""
struct Pointer{T}
    token::Tuple

    Pointer{T}(token::Tuple) where T = new{T}(token)
    function Pointer(token::AbstractString; shift_index = false)
        # URI Fragment
        if startswith(token, "#")
            token = token[2:end]
            token = unescape_jpath(token)
        end

        if isempty(token)
            return Pointer{Nothing}(tuple(""))
        end
        if !startswith(token, TOKEN_PREFIX)
            throw(ArgumentError("JSONPointer must starts with '$TOKEN_PREFIX' prefix"))
        end

        T = Any
        jk = convert(Array{Any, 1}, split(chop(token; head=1, tail=0), TOKEN_PREFIX))
        if occursin("::", jk[end])
            x = split(jk[end], "::")
            jk[end] = x[1]
            T = (x[2] == "Vector" ? "Vector{Any}" : x[2]) |> Meta.parse |> eval
        end
        @inbounds for i in 1:length(jk)
            if occursin(r"^\d+$", jk[i]) # index of a array
                jk[i] = if shift_index
                    parse(Int, string(jk[i])) + 1
                else
                    parse(Int, string(jk[i]))
                end

                if iszero(jk[i])
                    throw(ArgumentError("Julia uses 1-based indexing, use '1' instead of '0'"))
                end
            elseif occursin(r"^\\\d+$", jk[i]) # literal string for a number
                jk[i] = chop(jk[i]; head=1, tail=0)
            elseif occursin("~", jk[i])
                jk[i] = replace(replace(jk[i], "~0" => "~"), "~1" => "/")
            end
        end
        return new{T}(tuple(jk...))
    end
end

"""
    unescape_jpath(raw::String)

Transform escaped characters in JPaths back to their original value.
https://tools.ietf.org/html/rfc6901
"""
function unescape_jpath(raw::AbstractString)
    m = match(r"%([0-9A-F]{2})", raw)
    if m !== nothing
        for c in m.captures
            raw = replace(raw, "%$(c)" => Char(parse(UInt8, "0x$(c)")))
        end
    end
    return raw
end


"""
    null_value(p::Pointer{T}) where {T}
    null_value(::Type{T}) where {T}

Provide appropriate value for 'T'.

'Real' return 'zero(T)' and 'AbstractString' returns '""'

If user wants different null value for 'T' override 'null_value(::Type{T})' method.
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
        # TODO(odow): remove this method?
        function $T{K,V}(kv::Pair{<:Pointer,V}...) where {V, K<:Pointer}
            $T{String,Any}()
        end
        _new_container(::$T) = $T{String, Any}()

        Base.haskey(dict::$T, p::Pointer) = haskey_by_pointer(dict, p)

        Base.getindex(dict::$T, p::Pointer) = getindex_by_pointer(dict, p)

        function Base.setindex!(dict::$T, v, p::Pointer)
            return setindex_by_pointer!(dict, v, p)
        end

        function Base.get(dict::$T, p::Pointer, default)
            return get_by_pointer(dict, p, default)
        end
    end
end

Base.getindex(A::AbstractArray, p::Pointer{Any}) = getindex_by_pointer(A, p)

Base.haskey(A::AbstractArray, p::Pointer) = getindex_by_pointer(A, p)

function Base.unique(arr::Array{Pointer, N}) where {N}
    out = deepcopy(arr)
    if isempty(arr)
        return out
    end
    pointers = getfield.(arr, :token)
    if allunique(pointers)
        return out
    end
    delete_target = Int[]
    @inbounds for p in pointers
        indicies = findall(el -> el == p, pointers)
        if length(indicies) > 1
            append!(delete_target, indicies[1:end-1])
        end
    end
    deleteat!(out, unique(delete_target))
end

haskey_by_pointer(collection, p::Pointer{Nothing}) = true

function haskey_by_pointer(collection, p::Pointer)
    for k in p.token
        if !haskey_by_pointer(collection, k)
            return false
        end
        collection = collection[k]
    end
    return true
end

haskey_by_pointer(collection, k) = haskey(collection, k)

haskey_by_pointer(collection::AbstractArray, k) = false

function haskey_by_pointer(collection::AbstractArray, k::Integer)
    return 1 <= k <= length(collection)
end

function getindex_by_pointer(collection, ::Pointer{Nothing})
    return collection
end

function getindex_by_pointer(collection, p::Pointer)
    return getindex_by_pointer(collection, p.token)
end

function getindex_by_pointer(collection, tokens::Tuple)
    for token in tokens
        collection = collection[token]
    end
    return collection
end

function get_by_pointer(collection, p::Pointer, default)
    if haskey_by_pointer(collection, p)
        return getindex_by_pointer(collection, p)
    end
    return default
end

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

function setindex_by_pointer!(
    collection::T, v, p::Pointer{U}
) where {T <: AbstractDict, U}
    v = _convert_v(v, p)
    prev = collection
    for (i, k) in enumerate(p.token)
        _prep_prev(prev, k)
        if i < length(p)
            if ismissing(prev[k])
                setindex!(prev, _new_data(prev, p.token[i + 1]), k)
            end
            prev = prev[k]
        end
    end
    return setindex!(prev, v, p.token[end])
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

Base.length(x::Pointer) = length(x.token)

Base.eltype(::Pointer{T}) where {T} = T

function Base.show(io::IO, x::Pointer{T}) where {T}
    print(io, "JSONPointer{", T, "}(\"/", join(x.token, "/"), "\")")
end

function Base.show(io::IO, ::Pointer{Nothing})
    print(io, "JSONPointer{Nothing}(\"\")")
end
