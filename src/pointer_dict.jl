struct PointerDict
    d::AbstractDict{K,V} where {K,V}

    PointerDict() = new(Dict{String,Any}())
    function PointerDict(ps::Pair...) where V 
        pd = PointerDict()
        for kv in ps
            setindex!(pd, kv[2], kv[1])
        end
        return pd
    end    
end
PointerDict(kv::AbstractArray{Pair})  = PointerDict(kv...)

# function PointerDict(ps::Pair...)
#     md = Dict(ps...)
#     return PointerDict(md)
# end
function PointerDict(kv::Pair)
    pd = PointerDict()
    setindex!(pd, kv[2], kv[1])
    return pd
end


## Functions

## Most functions are simply delegated to the wrapped Dict
DataStructures.@delegate PointerDict.d [Base.get, Base.get!, Base.getkey,
                        Base.length, Base.isempty, Base.eltype,
                        Base.iterate, Base.keys, Base.values, sizehint!, 
                        Base.copy, Base.empty, Base.delete!, Base.empty!,
                        Base.in, Base.pop!, Base.push!, Base.count, 
                        Base.size]

# ==============================================================================
Base.haskey(::PointerDict, ::Pointer{Nothing}) = true
Base.haskey(A::AbstractArray, p::Pointer) = _haskey(A, p)
Base.haskey(dict::PointerDict, p::Pointer) = _haskey(dict, p)

function _haskey(collection, p::Pointer)
    for token in p.tokens
        if !_haskey(collection, token)
            return false
        end
        collection = _checked_get(collection, token)
    end
    return true
end

_haskey(collection::PointerDict, token::String) = haskey(collection.d, token)
_haskey(collection::AbstractDict, token::String) = haskey(collection, token)
function _haskey(collection::AbstractArray, token::Integer)
    return 1 <= token <= length(collection)
end


# ==============================================================================
Base.getindex(A::AbstractArray, p::Pointer) = _getindex(A, p.tokens)

function Base.getindex(collection::PointerDict, p::Pointer)
    return _getindex(collection.d, p.tokens)
end
Base.getindex(collection::PointerDict, i) = getindex(collection.d, i)
Base.getindex(collection::PointerDict, ::Pointer{Nothing}) = collection

_getindex(collection, p::Pointer) = _getindex(collection, p.tokens) 
function _getindex(collection, tokens::Vector{Union{String, Int}})
    for token in tokens
        collection = _checked_get(collection, token)
    end
    return collection
end

function Base.get(collection::PointerDict, p::Pointer, default)
    if haskey(collection, p)
        return collection[p]
    end
    return default
end

# ==============================================================================
_checked_get(collection::PointerDict, token::String) = _checked_get(collection.d, token)
_checked_get(collection::AbstractDict, token::String) = collection[token]
_checked_get(collection::AbstractArray, token::Integer) = collection[token]

function _checked_get(collection, token)
    error(
        "JSON pointer does not match the data-structure. I tried (and " *
        "failed) to index $(collection) with the key: $(token)"
    )
end

# ==============================================================================
function _add_element_if_needed(prev::AbstractVector{T}, k::Int) where {T}
    x = k - length(prev)
    if x > 0
        append!(prev, [_null_value(T) for _ = 1:x])
    end
    return
end

function _add_element_if_needed(
    prev::AbstractDict{K, V}, k::String
) where {K, V}
    if !haskey(prev, k)
        prev[k] = _null_value(V)
    end
end

function _add_element_if_needed(collection, token)
    error(
        "JSON pointer does not match the data-structure. I tried (and " *
        "failed) to set $(collection) at the index: $(token)"
    )
end

Base.setindex!(collection::PointerDict, v, p) = _setindex!(collection.d, v, p)
_setindex!(collection::AbstractDict, v, p) = setindex!(collection, v, p)
function _setindex!(collection::AbstractDict, v::Any, p::Pointer)
    prev = collection
    for (i, token) in enumerate(p.tokens)
        _add_element_if_needed(prev, token)
        if i != length(p)
            if ismissing(prev[token])
                prev[token] = _new_data(prev, p.tokens[i + 1])
            end
            prev = prev[token]
        end
    end
    prev[p.tokens[end]] = _convert_v(v, p)
    return v
end